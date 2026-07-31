//
//  LXMFMessage.swift
//  IceNomad
//
//  A real LXMF message: pack/compose for sending, parse/verify for
//  receiving. Confirmed byte-for-byte against the actual, currently
//  running LXMF source (LXMessage.py pack()/unpack_from_bytes()) —
//  not inferred. Wire format:
//
//    destination_hash (16) + source_hash (16) + signature (64) + msgpack(payload)
//    payload = [timestamp, title, content, fields]   <- TITLE BEFORE CONTENT
//
//  Signature covers MORE than just the visible fields:
//    hashed_part  = destination_hash + source_hash + packed_payload
//    message_hash = full SHA-256(hashed_part)   (32 bytes, NOT truncated)
//    signed_part  = hashed_part + message_hash   <- this is what's actually signed
//
//  Unlike our own icenomad.chat envelope, real LXMF messages do NOT
//  carry the sender's public key — only their 16-byte source hash.
//  That means you can only receive/verify a message from someone whose
//  announce you've already heard (their public key must already be
//  cached), exactly matching how real Reticulum/LXMF clients work.
//

import Foundation

struct LXMFMessage {

    let destinationHash: Data  // 16 bytes
    let sourceHash: Data       // 16 bytes
    let signature: Data        // 64 bytes
    let timestamp: Date
    let title: String
    let content: String


    // MARK: - Composing (outgoing)

    /// Builds and signs a new outgoing message from your own identity.
    static func compose(to destinationHash: Data, title: String = "", content: String) -> LXMFMessage? {

        let identity = IdentityStore.shared.myIdentity

        guard identity.hasPrivateKey else {
            return nil
        }

        let sourceHash = LXMFDestination.myDestinationHash
        let timestamp = Date()

        let payloadBytes = Self.pack(timestamp: timestamp, title: title, content: content)

        let hashedPart = destinationHash + sourceHash + payloadBytes
        let messageHash = Hash.full(hashedPart) // full 32-byte SHA-256, matching RNS.Identity.full_hash
        let signedPart = hashedPart + messageHash

        guard let signature = identity.sign(signedPart) else {
            return nil
        }

        return LXMFMessage(
            destinationHash: destinationHash,
            sourceHash: sourceHash,
            signature: signature,
            timestamp: timestamp,
            title: title,
            content: content
        )
    }


    /// Packs to the full wire format: destination_hash + source_hash +
    /// signature + payload. Used as-is for DIRECT (Link-based) delivery,
    /// and as the basis for the stripped opportunistic format below.
    var packedData: Data {

        let payloadBytes = Self.pack(timestamp: timestamp, title: title, content: content)
        return destinationHash + sourceHash + signature + payloadBytes
    }


    /// Wire format for OPPORTUNISTIC (single-packet) delivery: the
    /// destination_hash is stripped, since it's redundant with the
    /// packet's own addressing — matches RNS.LXMessage.__as_packet():
    /// `self.packed[DESTINATION_LENGTH:]` for method == OPPORTUNISTIC.
    /// The signature still covers the full (unstripped) envelope, since
    /// signing happens before this truncation on the wire.
    var opportunisticPackedData: Data {
        Data(packedData.dropFirst(16))
    }


    /// [timestamp, title, content, fields] — title before content, matching
    /// LXMessage.pack()'s `self.payload = [self.timestamp, self.title, self.content, self.fields]`.
    private static func pack(timestamp: Date, title: String, content: String) -> Data {

        let payload = MsgpackValue.array([
            .double(timestamp.timeIntervalSince1970),
            .binary(Data(title.utf8)),
            .binary(Data(content.utf8)),
            .map([]) // fields — none, for now
        ])

        return payload.encode()
    }


    // MARK: - Parsing (incoming)

    /// Parses and verifies a decrypted LXMF message. Requires already
    /// knowing the sender's public key (from a prior announce) — see
    /// the header comment for why.
    static func parse(_ data: Data, senderPublicKey: Data) -> LXMFMessage? {

        guard data.count > 96 else {
            return nil
        }

        let destinationHash = Data(data.prefix(16))
        let sourceHash = Data(data.dropFirst(16).prefix(16))
        let signature = Data(data.dropFirst(32).prefix(64))
        let payloadBytes = Data(data.dropFirst(96))

        let hashedPart = destinationHash + sourceHash + payloadBytes
        let messageHash = Hash.full(hashedPart)
        let signedPart = hashedPart + messageHash

        guard let sender = ReticulumIdentity(publicKeyBytes: senderPublicKey) else {
            return nil
        }

        guard sender.validate(signature: signature, message: signedPart) else {
            return nil
        }

        guard let value = try? MsgpackValue.decode(payloadBytes),
              case .array(let elements) = value,
              elements.count >= 3
        else {
            return nil
        }

        var timestamp = Date()
        if case .double(let t) = elements[0] {
            timestamp = Date(timeIntervalSince1970: t)
        }

        // Title before content — matches unpack_from_bytes():
        // title_bytes = unpacked_payload[1], content_bytes = unpacked_payload[2]
        let title = Self.stringValue(elements[1])
        let content = Self.stringValue(elements[2])

        return LXMFMessage(
            destinationHash: destinationHash,
            sourceHash: sourceHash,
            signature: signature,
            timestamp: timestamp,
            title: title,
            content: content
        )
    }


    /// Parses a message received via OPPORTUNISTIC (single-packet)
    /// delivery: `data` is missing its leading destination_hash (stripped
    /// on the wire — see `opportunisticPackedData`), so it's reconstructed
    /// from our own destination hash before delegating to `parse(_:senderPublicKey:)`.
    /// Matches RNS.LXMRouter.delivery_packet()'s OPPORTUNISTIC branch:
    /// `lxmf_data = packet.destination.hash + data`.
    static func parseOpportunistic(_ data: Data, myDestinationHash: Data, senderPublicKey: Data) -> LXMFMessage? {
        parse(myDestinationHash + data, senderPublicKey: senderPublicKey)
    }


    private static func stringValue(_ value: MsgpackValue) -> String {

        switch value {
        case .binary(let d): return String(data: d, encoding: .utf8) ?? ""
        case .string(let s): return s
        default: return ""
        }
    }


    var sourceHashHex: String {
        sourceHash.map { String(format: "%02x", $0) }.joined()
    }
}
