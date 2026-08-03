//
//  ReticulumLink.swift
//  IceNomad
//
//  A Reticulum Link: the ECDH-handshake session NomadNet (and LXMF's
//  DIRECT delivery method) needs on top of plain single-destination
//  messaging. Matches RNS.Link's essential behavior for BOTH roles —
//  confirmed byte-for-byte against the real Link.py/Packet.py source.
//
//  Initiator handshake (browsing, and any link we open ourselves): we
//  generate a fresh ephemeral X25519 + Ed25519 keypair, send an
//  unencrypted LINKREQUEST (data = ephemeralPub + signingPub, no MTU
//  signalling — a bare 64-byte request makes a real node fall back to
//  defaults that match what we assume anyway: AES256_CBC, Reticulum.MTU).
//  link_id = truncated_hash(hashable part of that packet) becomes the
//  address for every subsequent packet on this link. The peer replies
//  with a PROOF/LRPROOF (signature over link_id+theirEphemeralPub+
//  theirSigningPub, signed with their LONG-TERM identity key — which we
//  must already know from a prior announce, same requirement as LXMF).
//
//  Responder handshake (accepting an incoming link — e.g. someone
//  delivering us an LXMF message via DIRECT method): the LINKREQUEST
//  already carries the initiator's ephemeral keys, so we can derive the
//  shared key immediately and reply with our own LRPROOF signed by OUR
//  long-term identity. We never learn the initiator's identity this way
//  ("initiator anonymity") — for LXMF that's fine, since the message
//  itself carries a source_hash we resolve via PeerStore, same as
//  opportunistic delivery.
//
//  Either way: shared_key = ourEphemeralPriv.exchange(theirEphemeralPub),
//  derivedKey = HKDF(shared_key, salt: link_id, length: 64), and every
//  packet after that is just ReticulumToken keyed by derivedKey — no
//  ephemeral-key prefix, unlike Identity.encrypt (the handshake already
//  did the key exchange).
//
//  Post-handshake identification (identify()/LINKIDENTIFY, RNS.Packet
//  context 0xFB): a link's ECDH handshake alone never reveals either
//  side's long-term identity — that's "initiator anonymity" by design.
//  The INITIATOR may optionally call identify(as:) once the link is
//  active to prove who they are to the specific peer on the other end
//  (signed_data = link_id + identity.publicKeyBytes, sent link-encrypted).
//  Confirmed byte-for-byte against real Link.py (identify() ~line 454,
//  the LINKIDENTIFY receive/validate branch ~line 963) — this was
//  entirely unimplemented in IceNomad prior to this addition.
//

import Foundation
import CryptoKit
import OSLog

final class ReticulumLink {

    enum Status {
        case pending
        case handshake
        case active
        case closed
    }

    enum LinkError: Error {
        case notActive
    }

    let destinationHash: Data
    private let peerIdentityPublicKey: Data // their 64-byte long-term identity pubkey, from a prior announce — empty/unused for accepted (responder) links, since initiator anonymity means we don't need it to accept

    let isInitiator: Bool

    private(set) var linkId: Data = Data()
    private(set) var status: Status = .pending

    private let ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey
    private let signingPrivateKey: Curve25519.Signing.PrivateKey
    private var derivedKey: Data?

    /// Set by LinkManager to InterfaceManager.shared.send — Link stays
    /// passive about actual transmission, it just knows how to build and
    /// encrypt its own packets.
    var send: ((Data) -> Void)?

    var onEstablished: (() -> Void)?
    var onFailed: (() -> Void)?
    var onClosed: (() -> Void)?

    /// The peer's identity, once revealed via LINKIDENTIFY — nil until
    /// then. Only ever set on an ACCEPTED (responder-role) link: initiator
    /// anonymity means we never learn who opened a link to us unless they
    /// explicitly call identify(). Matches RNS.Link.get_remote_identity().
    private(set) var remoteIdentity: ReticulumIdentity?
    var onRemoteIdentified: ((ReticulumIdentity) -> Void)?

    /// Fires for plain (context=NONE) data delivered on an ACCEPTED
    /// (responder-role) link — e.g. an LXMF message sent via DIRECT
    /// method as a single packet rather than a Resource.
    var onIncomingPayload: ((Data) -> Void)?

    private var pendingRequests: [Data: (Result<Data, LinkError>) -> Void] = [:]
    private var pendingProgressHandlers: [Data: (Double) -> Void] = [:] // keyed by request_id
    private var pendingResourceReceivers: [Data: ResourceReceiver] = [:] // keyed by request_id
    /// Resource(s) pushed to us unsolicited on an accepted link — no
    /// request_id to key by, so keyed by the resource's own hash instead.
    private var incomingResourceReceivers: [Data: ResourceReceiver] = [:]


    /// Initiator-role: we're establishing a link OUT to a known destination.
    init?(destinationHash: Data, peerIdentityPublicKey: Data) {

        guard peerIdentityPublicKey.count == ReticulumIdentity.publicKeySize else {
            return nil
        }

        self.isInitiator = true
        self.destinationHash = destinationHash
        self.peerIdentityPublicKey = peerIdentityPublicKey
        self.ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        self.signingPrivateKey = Curve25519.Signing.PrivateKey()
    }


    /// Responder-role: we're accepting an incoming LINKREQUEST addressed
    /// to one of our own destinations. Initiator anonymity means we don't
    /// need (and don't get) their long-term identity to accept the link —
    /// only the ephemeral keys in the LINKREQUEST itself.
    init(acceptingLinkId linkId: Data, forDestination destinationHash: Data) {

        self.isInitiator = false
        self.destinationHash = destinationHash
        self.peerIdentityPublicKey = Data()
        self.linkId = linkId
        self.ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        self.signingPrivateKey = Curve25519.Signing.PrivateKey()
    }


    // MARK: - Handshake

    /// Builds and sends the outbound LINKREQUEST, deriving link_id.
    func open() {

        let (raw, linkId) = PacketBuilder.buildLinkRequestPacket(
            destinationHash: destinationHash,
            ephemeralPublicKey: ephemeralPrivateKey.publicKey.rawRepresentation,
            signingPublicKey: signingPrivateKey.publicKey.rawRepresentation,
            transportId: InterfaceManager.shared.lastKnownTransportId
        )

        self.linkId = linkId
        self.status = .handshake

        send?(PacketBuilder.hdlcFrame(raw))

        let myLinkId = linkId
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in

            guard let self, self.linkId == myLinkId, self.status == .handshake else {
                return
            }

            self.status = .closed
            self.onFailed?()
        }
    }


    /// Handles the PROOF/LRPROOF packet completing the handshake.
    /// `payload` is `signature(64) + theirEphemeralPub(32) [+ 3-byte MTU signalling]`.
    private func handleProof(_ payload: Data) {

        guard status == .handshake else {
            return
        }

        guard payload.count == 96 || payload.count == 99 else {
            Log.reticulum.error("LRPROOF for link \(self.linkId.hexString, privacy: .public) has an unexpected size (\(payload.count) bytes) — dropped")
            return
        }

        let signature = Data(payload.prefix(64))
        let theirEphemeralPub = Data(payload.dropFirst(64).prefix(32))
        let theirSigningPub = Data(peerIdentityPublicKey.suffix(32))
        let signalling = payload.count == 99 ? Data(payload.suffix(3)) : Data()

        let signedData = linkId + theirEphemeralPub + theirSigningPub + signalling

        guard let peerIdentity = ReticulumIdentity(publicKeyBytes: peerIdentityPublicKey) else {
            return
        }

        guard peerIdentity.validate(signature: signature, message: signedData) else {
            Log.reticulum.error("LRPROOF for link \(self.linkId.hexString, privacy: .public) failed signature validation — dropped")
            return
        }

        do {
            let sharedSecret = try X25519.sharedSecret(
                privateKeyBytes: ephemeralPrivateKey.rawRepresentation,
                publicKeyBytes: theirEphemeralPub
            )

            derivedKey = ReticulumHKDF.derive(length: 64, inputKeyMaterial: sharedSecret, salt: linkId)
            status = .active

            Log.reticulum.info("Link \(self.linkId.hexString, privacy: .public) established with \(self.destinationHash.hexString, privacy: .public)")

            sendLRRTT()
            onEstablished?()

        } catch {
            Log.reticulum.error("Link \(self.linkId.hexString, privacy: .public) handshake failed while deriving shared key: \(error)")
            status = .closed
            onFailed?()
        }
    }


    /// Accepts an incoming LINKREQUEST: derives the shared key immediately
    /// (we hold both halves — our fresh ephemeral key and their ephemeral
    /// pub key from the request), then proves control of our long-term
    /// identity back to them. Matches RNS.Link.validate_request()+prove():
    /// signed_data = link_id + our_ephemeral_pub + our_signing_pub +
    /// signalling_bytes, signed with our LONG-TERM identity (not
    /// ephemeral) — that's what lets a peer who knows our identity key
    /// (from a prior announce) trust this link is really with us.
    func acceptAndProve(initiatorEphemeralPublicKey: Data) {

        guard !isInitiator, status == .pending else {
            return
        }

        status = .handshake

        do {
            let sharedSecret = try X25519.sharedSecret(
                privateKeyBytes: ephemeralPrivateKey.rawRepresentation,
                publicKeyBytes: initiatorEphemeralPublicKey
            )

            derivedKey = ReticulumHKDF.derive(length: 64, inputKeyMaterial: sharedSecret, salt: linkId)

            let ourEphemeralPub = ephemeralPrivateKey.publicKey.rawRepresentation
            let ourSigningPub = signingPrivateKey.publicKey.rawRepresentation
            let signalling = PacketBuilder.linkSignallingBytes

            let signedData = linkId + ourEphemeralPub + ourSigningPub + signalling

            guard let signature = IdentityStore.shared.myIdentity.sign(signedData) else {
                status = .closed
                onFailed?()
                return
            }

            let proofData = signature + ourEphemeralPub + signalling
            let raw = PacketBuilder.buildLinkPacket(linkId: linkId, packetType: PacketBuilder.packetTypeProof, context: PacketBuilder.Context.lrProof, payload: proofData)

            status = .active
            Log.reticulum.info("Accepted incoming link \(self.linkId.hexString, privacy: .public) on destination \(self.destinationHash.hexString, privacy: .public)")

            send?(PacketBuilder.hdlcFrame(raw))
            onEstablished?()

        } catch {
            Log.reticulum.error("Failed to accept link \(self.linkId.hexString, privacy: .public): \(error)")
            status = .closed
            onFailed?()
        }
    }


    private func sendLRRTT() {

        guard let framed = try? encryptedLinkPacket(context: PacketBuilder.Context.lrrtt, plaintext: MsgpackValue.double(0).encode()) else {
            return
        }

        send?(framed)
    }


    /// Pushes plain (context=NONE) data over the link, unsolicited — the
    /// initiator-side counterpart to handleIncomingPayload, matching how
    /// real LXMF delivers a message via DIRECT method: `__as_packet()`
    /// sends the full envelope link-encrypted with no request/response
    /// wrapper. Requires the link to already be active.
    @discardableResult
    func sendPayload(_ plaintext: Data) -> Bool {

        guard status == .active, let framed = try? encryptedLinkPacket(context: PacketBuilder.Context.none, plaintext: plaintext) else {
            return false
        }

        send?(framed)
        return true
    }


    /// Reveals our identity to the remote peer over the already-active,
    /// encrypted link — RNS.Link.identify()/LINKIDENTIFY. Initiator-only
    /// (matches Link.py: the responder side never calls this — only
    /// validates it), and only the peer on the other end of THIS link
    /// learns who we are; initiator anonymity is preserved for everyone
    /// else. plaintext = our 64-byte combined public key + a signature
    /// over (link_id + public key), signed with our long-term identity —
    /// proves control of that identity without exposing our private key.
    @discardableResult
    func identify(as identity: ReticulumIdentity) -> Bool {

        guard isInitiator, status == .active else {
            return false
        }

        let signedData = linkId + identity.publicKeyBytes

        guard let signature = identity.sign(signedData),
              let framed = try? encryptedLinkPacket(context: PacketBuilder.Context.linkIdentify, plaintext: identity.publicKeyBytes + signature)
        else {
            return false
        }

        send?(framed)
        return true
    }


    // MARK: - Encrypt / decrypt (Token keyed by derivedKey — no ephemeral prefix)

    func encrypt(_ plaintext: Data) throws -> Data {

        guard let derivedKey else {
            throw LinkError.notActive
        }

        return try ReticulumToken.encrypt(plaintext: plaintext, key: derivedKey)
    }


    func decrypt(_ ciphertext: Data) throws -> Data {

        guard let derivedKey else {
            throw LinkError.notActive
        }

        return try ReticulumToken.decrypt(token: ciphertext, key: derivedKey)
    }


    /// Encrypts `plaintext` and wraps it as an HDLC-framed packet
    /// addressed to this link (destination-type LINK).
    func encryptedLinkPacket(context: UInt8, plaintext: Data) throws -> Data {

        let ciphertext = try encrypt(plaintext)
        let raw = PacketBuilder.buildLinkPacket(linkId: linkId, context: context, payload: ciphertext)
        return PacketBuilder.hdlcFrame(raw)
    }


    // MARK: - Request / Response

    /// Sends a REQUEST over the link. `completion` fires exactly once,
    /// either with the assembled response bytes or a failure.
    @discardableResult
    func request(
        path: String,
        data: MsgpackValue = .null,
        timeout: TimeInterval = 20,
        onProgress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<Data, LinkError>) -> Void
    ) -> Bool {

        guard status == .active else {
            completion(.failure(.notActive))
            return false
        }

        let pathHash = Hash.truncated(Data(path.utf8))
        let requestPayload = MsgpackValue.array([
            .double(Date().timeIntervalSince1970),
            .binary(pathHash),
            data
        ]).encode()

        guard let ciphertext = try? encrypt(requestPayload) else {
            completion(.failure(.notActive))
            return false
        }

        let raw = PacketBuilder.buildLinkPacket(linkId: linkId, context: PacketBuilder.Context.request, payload: ciphertext)
        let requestId = PacketBuilder.truncatedHash(ofRawPacket: raw)

        pendingRequests[requestId] = completion

        if let onProgress {
            pendingProgressHandlers[requestId] = onProgress
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in

            guard let self, let stillPending = self.pendingRequests[requestId] else {
                return
            }

            self.pendingRequests.removeValue(forKey: requestId)
            self.pendingProgressHandlers.removeValue(forKey: requestId)
            self.pendingResourceReceivers.removeValue(forKey: requestId)
            stillPending(.failure(.notActive))
        }

        send?(PacketBuilder.hdlcFrame(raw))
        return true
    }


    // MARK: - Incoming packet dispatch

    /// Called by LinkManager for every packet addressed to this link
    /// (destinationHash == link_id), or the LRPROOF completing handshake.
    func receive(packetType: String, context: UInt8, payload: Data) {

        if packetType == "PROOF", context == PacketBuilder.Context.lrProof {
            handleProof(payload)
            return
        }

        guard status == .active else {
            return
        }

        switch context {

        case PacketBuilder.Context.none:
            handleIncomingPayload(payload)

        case PacketBuilder.Context.response:
            handleResponse(payload)

        case PacketBuilder.Context.resourceAdv:
            handleResourceAdvertisement(payload)

        case PacketBuilder.Context.resource, PacketBuilder.Context.resourceHmu,
             PacketBuilder.Context.resourceIcl:
            handleResourcePacket(context: context, payload: payload)

        case PacketBuilder.Context.linkIdentify:
            handleLinkIdentify(payload)

        case PacketBuilder.Context.linkClose:
            handleLinkClose(payload)

        default:
            break
        }
    }


    /// A plain (context=NONE) packet delivered on the link — the small-
    /// payload form of an unsolicited push (e.g. LXMF DIRECT method
    /// sending a message that fits in one packet, via `__as_packet()`).
    private func handleIncomingPayload(_ ciphertext: Data) {

        guard let plaintext = try? decrypt(ciphertext) else {
            return
        }

        onIncomingPayload?(plaintext)
    }


    private func handleResponse(_ ciphertext: Data) {

        guard let plaintext = try? decrypt(ciphertext),
              case .array(let elements) = (try? MsgpackValue.decode(plaintext)) ?? .null,
              elements.count >= 2,
              case .binary(let requestId) = elements[0]
        else {
            return
        }

        guard let completion = pendingRequests.removeValue(forKey: requestId) else {
            return
        }

        pendingProgressHandlers.removeValue(forKey: requestId)
        pendingResourceReceivers.removeValue(forKey: requestId)

        if case .binary(let responseBytes) = elements[1] {
            completion(.success(responseBytes))
            return
        }

        // A single-packet file-download response carries `[filename,
        // filedata]` as the response value itself (real NomadNet's
        // Browser.download_file single-packet case), rather than a plain
        // binary blob — the caller derives the filename from the request
        // path instead (see DownloadManager), so just unwrap the data here.
        if case .array(let inner) = elements[1], inner.count >= 2, case .binary(let fileData) = inner[1] {
            completion(.success(fileData))
            return
        }

        completion(.failure(.notActive))
    }


    private func handleResourceAdvertisement(_ ciphertext: Data) {

        guard let plaintext = try? decrypt(ciphertext), let adv = ResourceAdvertisement(data: plaintext) else {
            return
        }

        // A response to one of OUR OWN outstanding requests (NomadNet-style).
        if adv.isResponse, let requestId = adv.requestId, let completion = pendingRequests[requestId] {

            let receiver = ResourceReceiver(advertisement: adv, link: self)
            pendingResourceReceivers[requestId] = receiver
            receiver.onProgress = pendingProgressHandlers[requestId]

            receiver.onComplete = { [weak self] result in

                guard let self else {
                    return
                }

                self.pendingRequests.removeValue(forKey: requestId)
                self.pendingProgressHandlers.removeValue(forKey: requestId)
                self.pendingResourceReceivers.removeValue(forKey: requestId)

                switch result {
                case .success(let data): completion(.success(data))
                case .failure: completion(.failure(.notActive))
                }
            }

            receiver.begin()
            return
        }

        // Otherwise: an unsolicited push on a link we accepted (e.g. an
        // LXMF DIRECT-method message too big for a single packet).
        guard !isInitiator else {
            return
        }

        let receiver = ResourceReceiver(advertisement: adv, link: self, unwrapsResponseEnvelope: false)
        incomingResourceReceivers[adv.hash] = receiver

        receiver.onComplete = { [weak self] result in

            guard let self else {
                return
            }

            self.incomingResourceReceivers.removeValue(forKey: adv.hash)

            if case .success(let data) = result {
                self.onIncomingPayload?(data)
            }
        }

        receiver.begin()
    }


    private func handleResourcePacket(context: UInt8, payload: Data) {

        // RESOURCE (actual part data) is unencrypted at the packet level —
        // the sender encrypts the whole reassembled blob once, not each
        // part (RNS.Resource.py: `self.data = self.link.encrypt(self.data)`
        // happens before splitting). RESOURCE_HMU/RESOURCE_ICL ARE
        // link-encrypted and carry the resource hash up front, so we can
        // route them to the right receiver instead of broadcasting.
        if context == PacketBuilder.Context.resource {

            // A link only ever has one page/file request (or, for an
            // accepted link, one incoming push) outstanding at a time in
            // this client, but real Resource part packets carry no
            // request-id — hand it to every receiver, same as
            // RNS.Link.receive() iterating incoming_resources.
            for receiver in pendingResourceReceivers.values {
                receiver.receivePart(payload)
            }
            for receiver in incomingResourceReceivers.values {
                receiver.receivePart(payload)
            }
            return
        }

        guard let plaintext = try? decrypt(payload), plaintext.count >= 32 else {
            return
        }

        let resourceHash = Data(plaintext.prefix(32))

        guard let receiver = pendingResourceReceivers.values.first(where: { $0.resourceHash == resourceHash })
                ?? incomingResourceReceivers.values.first(where: { $0.resourceHash == resourceHash })
        else {
            return
        }

        switch context {
        case PacketBuilder.Context.resourceHmu:
            receiver.receiveHashmapUpdate(plaintext)
        case PacketBuilder.Context.resourceIcl:
            receiver.cancel()
        default:
            break
        }
    }


    /// Handles an incoming LINKIDENTIFY on a link we accepted — the
    /// initiator revealing their identity to us. plaintext = 64-byte
    /// combined public key + 64-byte Ed25519 signature over
    /// (link_id + public_key). Responder-only, matching Link.py's
    /// `if not self.initiator` guard — an initiator ignores this context
    /// since only it can legitimately send one.
    private func handleLinkIdentify(_ ciphertext: Data) {

        guard !isInitiator, remoteIdentity == nil,
              let plaintext = try? decrypt(ciphertext),
              plaintext.count == ReticulumIdentity.publicKeySize + 64
        else {
            return
        }

        let publicKey = Data(plaintext.prefix(ReticulumIdentity.publicKeySize))
        let signature = Data(plaintext.suffix(64))
        let signedData = linkId + publicKey

        guard let identity = ReticulumIdentity(publicKeyBytes: publicKey), identity.validate(signature: signature, message: signedData) else {
            Log.reticulum.error("LINKIDENTIFY on link \(self.linkId.hexString, privacy: .public) failed signature validation — dropped")
            return
        }

        remoteIdentity = identity
        onRemoteIdentified?(identity)
    }


    private func handleLinkClose(_ ciphertext: Data) {

        guard let plaintext = try? decrypt(ciphertext), plaintext == linkId else {
            return
        }

        status = .closed
        onClosed?()
    }


    // MARK: - Teardown

    func teardown() {

        guard status == .active else {
            status = .closed
            return
        }

        if let framed = try? encryptedLinkPacket(context: PacketBuilder.Context.linkClose, plaintext: linkId) {
            send?(framed)
        }

        status = .closed
    }
}
