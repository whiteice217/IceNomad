//
//  ResourceReceiver.swift
//  IceNomad
//
//  Receive-only implementation of RNS's Resource transfer: the reliable,
//  windowed protocol NomadNet uses for anything that doesn't fit in a
//  single Link packet — which is most real pages, since NomadNet
//  auto-compresses responses by default. Traced against the real
//  Resource.py (accept/receive_part/request_next/hashmap_update).
//
//  Key fact this hinges on: the sender encrypts the WHOLE reassembled
//  blob once before splitting it into parts (Resource.py: `self.data =
//  self.link.encrypt(self.data)` happens before parts are cut) — so
//  individual RESOURCE-context part packets are raw, unencrypted slices
//  of one ciphertext, and we only call Link.decrypt() once, after
//  concatenating every part in hashmap order.
//

import Foundation

// MARK: - Advertisement

struct ResourceAdvertisement {

    let transferSize: Int      // t — size of the (encrypted, possibly compressed) wire blob
    let dataSize: Int          // d — uncompressed size, informational only
    let partCount: Int         // n
    let hash: Data              // h — 32-byte full hash of (decompressed data + randomHash)
    let randomHash: Data        // r — 4 bytes
    let segmentIndex: Int       // i
    let totalSegments: Int      // l
    let requestId: Data?        // q
    let flags: UInt8            // f
    let hashmapSegment: Data    // m — this advertisement's slice of the hashmap (segment 0)

    var isEncrypted: Bool { flags & 0x01 != 0 }
    var isCompressed: Bool { (flags >> 1) & 0x01 != 0 }
    var isResponse: Bool { (flags >> 4) & 0x01 != 0 }
    var hasMetadata: Bool { (flags >> 5) & 0x01 != 0 }

    init?(data: Data) {

        guard case .map(let pairs) = (try? MsgpackValue.decode(data)) ?? .null else {
            return nil
        }

        var dict: [String: MsgpackValue] = [:]
        for (key, value) in pairs {
            if case .string(let k) = key {
                dict[k] = value
            }
        }

        func intValue(_ key: String) -> Int? {
            if case .int(let v)? = dict[key] { return Int(v) }
            return nil
        }

        func binValue(_ key: String) -> Data? {
            if case .binary(let v)? = dict[key] { return v }
            return nil
        }

        guard let t = intValue("t"), let d = intValue("d"), let n = intValue("n"),
              let h = binValue("h"), let r = binValue("r"),
              let i = intValue("i"), let l = intValue("l"), let f = intValue("f"),
              let m = binValue("m")
        else {
            return nil
        }

        transferSize = t
        dataSize = d
        partCount = n
        hash = h
        randomHash = r
        segmentIndex = i
        totalSegments = l
        flags = UInt8(f & 0xFF)
        hashmapSegment = m
        requestId = binValue("q")
    }
}


// MARK: - Receiver

final class ResourceReceiver {

    // Matches RNS.Link.MDU (431, for MTU=500) and
    // ResourceAdvertisement.OVERHEAD (134) exactly — needed to place
    // hashmap-update segments at the correct absolute part index, since
    // the sender computes segment numbers using this same constant.
    private static let mapHashLength = 4
    private static let hashmapMaxLen = 74
    private static let randomHashSize = 4
    private static let hashmapExhausted: UInt8 = 0xFF
    private static let hashmapNotExhausted: UInt8 = 0x00
    private static let window = 4 // fixed, modest — real RNS ramps this adaptively for speed; correctness doesn't depend on it

    let resourceHash: Data
    private let randomHash: Data
    private let partCount: Int
    private let isCompressed: Bool

    private weak var link: ReticulumLink?

    /// True for a resource advertised in answer to one of our own
    /// REQUESTs (NomadNet-style, where RNS.Link.handle_request() wraps
    /// the payload as msgpack([request_id, response]) regardless of
    /// packet-vs-resource size). False for a resource pushed to us
    /// unsolicited (e.g. an LXMF DIRECT-method message delivered over an
    /// incoming link), whose content is the raw payload with no wrapping.
    private let unwrapsResponseEnvelope: Bool

    private var hashmap: [Data?]
    private var parts: [Data?]
    private var receivedCount = 0
    private var outstandingParts = 0
    private var consecutiveCompletedHeight = -1
    private var waitingForHMU = false
    private var isCancelled = false

    var onComplete: ((Result<Data, ResourceError>) -> Void)?

    enum ResourceError: Error {
        case cancelled
        case corrupt
        case linkGone
    }


    init(advertisement adv: ResourceAdvertisement, link: ReticulumLink, unwrapsResponseEnvelope: Bool = true) {

        resourceHash = adv.hash
        randomHash = adv.randomHash
        partCount = adv.partCount
        isCompressed = adv.isCompressed
        self.link = link
        self.unwrapsResponseEnvelope = unwrapsResponseEnvelope

        hashmap = Array(repeating: nil, count: adv.partCount)
        parts = Array(repeating: nil, count: adv.partCount)

        applyHashmapSegment(adv.hashmapSegment, startingAt: 0)
    }


    func begin() {
        requestNext()
    }


    func cancel() {
        isCancelled = true
        onComplete?(.failure(.cancelled))
    }


    // MARK: - Hashmap

    private func applyHashmapSegment(_ segment: Data, startingAt segmentIndex: Int) {

        let entryCount = segment.count / Self.mapHashLength
        let base = segmentIndex * Self.hashmapMaxLen

        for entry in 0..<entryCount {

            let idx = base + entry
            guard idx < hashmap.count else {
                break
            }

            let start = segment.index(segment.startIndex, offsetBy: entry * Self.mapHashLength)
            let end = segment.index(start, offsetBy: Self.mapHashLength)

            hashmap[idx] = Data(segment[start..<end])
        }

        waitingForHMU = false
    }


    /// `plaintext` = resourceHash(32) + msgpack([segment, hashmapBytes]).
    func receiveHashmapUpdate(_ plaintext: Data) {

        guard waitingForHMU, !isCancelled, plaintext.count > 32 else {
            return
        }

        let body = Data(plaintext.dropFirst(32))

        guard case .array(let elements) = (try? MsgpackValue.decode(body)) ?? .null,
              elements.count >= 2,
              case .int(let segmentValue) = elements[0],
              case .binary(let hashmapBytes) = elements[1],
              hashmapBytes.count >= Self.mapHashLength
        else {
            cancel()
            return
        }

        applyHashmapSegment(hashmapBytes, startingAt: Int(segmentValue))
        requestNext()
    }


    // MARK: - Receiving parts

    func receivePart(_ partData: Data) {

        guard !isCancelled else {
            return
        }

        let partHash = Hash.truncated(partData + randomHash, length: Self.mapHashLength)

        let searchStart = consecutiveCompletedHeight >= 0 ? consecutiveCompletedHeight : 0
        let searchEnd = min(searchStart + Self.window, hashmap.count)

        // Doesn't break after the first match — mirrors RNS.Resource.
        // receive_part(), which scans the whole window slice on every
        // packet (a 4-byte map hash collision within one window is
        // astronomically unlikely, but this costs nothing to match).
        for i in searchStart..<searchEnd {

            guard hashmap[i] == partHash, parts[i] == nil else {
                continue
            }

            parts[i] = partData
            receivedCount += 1
            outstandingParts = max(0, outstandingParts - 1)

            if i == consecutiveCompletedHeight + 1 {
                consecutiveCompletedHeight = i
                var cp = consecutiveCompletedHeight + 1
                while cp < parts.count, parts[cp] != nil {
                    consecutiveCompletedHeight = cp
                    cp += 1
                }
            }
        }

        if receivedCount == partCount {
            assemble()
        } else if outstandingParts == 0 {
            requestNext()
        }
    }


    private func requestNext() {

        guard !isCancelled, !waitingForHMU else {
            return
        }

        outstandingParts = 0
        var hashmapExhausted = Self.hashmapNotExhausted
        var requestedHashes = Data()

        // Matches RNS.Resource.request_next() exactly: scan a FIXED
        // window-sized slice starting right after the last consecutively
        // completed part, not "keep scanning until window gaps found".
        var pn = consecutiveCompletedHeight + 1
        let searchEnd = min(pn + Self.window, parts.count)
        var requestedCount = 0

        while pn < searchEnd {

            if parts[pn] == nil {

                if let partHash = hashmap[pn] {
                    requestedHashes.append(partHash)
                    outstandingParts += 1
                    requestedCount += 1
                } else {
                    hashmapExhausted = Self.hashmapExhausted
                }
            }

            pn += 1

            if requestedCount >= Self.window || hashmapExhausted == Self.hashmapExhausted {
                break
            }
        }

        var requestData = Data([hashmapExhausted])

        if hashmapExhausted == Self.hashmapExhausted {

            guard let lastKnown = hashmap.last(where: { $0 != nil }) ?? nil else {
                cancel()
                return
            }

            requestData.append(lastKnown)
            waitingForHMU = true
        }

        requestData.append(resourceHash)
        requestData.append(requestedHashes)

        guard requestedHashes.count > 0 || hashmapExhausted == Self.hashmapExhausted else {
            // Nothing left to ask for and not waiting on more hashmap —
            // either fully requested already or done.
            return
        }

        guard let link, let framed = try? link.encryptedLinkPacket(context: PacketBuilder.Context.resourceReq, plaintext: requestData) else {
            onComplete?(.failure(.linkGone))
            return
        }

        link.send?(framed)
    }


    // MARK: - Assembly

    private func assemble() {

        guard let link else {
            onComplete?(.failure(.linkGone))
            return
        }

        let ciphertext = parts.compactMap { $0 }.reduce(Data(), +)

        guard let decrypted = try? link.decrypt(ciphertext) else {
            onComplete?(.failure(.corrupt))
            return
        }

        guard decrypted.count >= Self.randomHashSize else {
            onComplete?(.failure(.corrupt))
            return
        }

        let stripped = Data(decrypted.dropFirst(Self.randomHashSize))

        let finalData: Data

        if isCompressed {
            guard let decompressed = try? BZip2.decompress(stripped) else {
                onComplete?(.failure(.corrupt))
                return
            }
            finalData = decompressed
        } else {
            finalData = stripped
        }

        let calculatedHash = Hash.full(finalData + randomHash)

        guard calculatedHash == resourceHash else {
            onComplete?(.failure(.corrupt))
            return
        }

        sendProof(finalData: finalData, link: link)

        guard unwrapsResponseEnvelope else {
            onComplete?(.success(finalData))
            return
        }

        // A RESPONSE-type resource carries the exact same [request_id,
        // response] msgpack envelope as the single-packet RESPONSE path
        // (RNS.Link.handle_request(): `packed_response =
        // umsgpack.packb([request_id, response])` is built BEFORE the
        // size check that decides packet-vs-Resource) — so the resource's
        // decompressed content still needs unwrapping, matching
        // response_resource_concluded()'s non-metadata branch.
        guard case .array(let elements) = (try? MsgpackValue.decode(finalData)) ?? .null,
              elements.count >= 2,
              case .binary(let responseBytes) = elements[1]
        else {
            onComplete?(.failure(.corrupt))
            return
        }

        onComplete?(.success(responseBytes))
    }


    private func sendProof(finalData: Data, link: ReticulumLink) {

        // Proof isn't over Link.encrypt like most other over-link
        // traffic — PROOF packets with destination-type LINK are left
        // unencrypted at the packet level (RNS.Packet.pack()'s special
        // case for `packet_type == PROOF and destination.type == LINK`).
        // RNS.Resource.prove(): proof = full_hash(self.data + self.hash),
        // where self.data is the final DECOMPRESSED content.
        let proof = Hash.full(finalData + resourceHash)
        let proofData = resourceHash + proof

        let raw = PacketBuilder.buildLinkPacket(linkId: link.linkId, packetType: PacketBuilder.packetTypeProof, context: PacketBuilder.Context.resourcePrf, payload: proofData)
        link.send?(PacketBuilder.hdlcFrame(raw))
    }
}
