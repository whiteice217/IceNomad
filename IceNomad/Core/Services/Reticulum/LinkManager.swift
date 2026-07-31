//
//  LinkManager.swift
//  IceNomad
//
//  Owns every active/pending Link, keyed by both the target's destination
//  hash (so callers can ask "give me a link to this node") and the link's
//  own link_id (so incoming packets addressed to a link can be routed to
//  the right ReticulumLink instance). One link is reused per node while
//  browsing it — InterfaceManager routes LINKREQUEST/PROOF packet types,
//  and any DATA packet not addressed to one of our own identity
//  destinations, here.
//

import Foundation

final class LinkManager {

    static let shared = LinkManager()
    private init() {}

    enum ConnectError: Error {
        case invalidHash
        case unknownPeer   // no announce heard yet — can't build a Link without their identity key
        case invalidPeerKey
        case timeout
    }

    private var linksByDestination: [String: ReticulumLink] = [:]
    private var linksByLinkId: [String: ReticulumLink] = [:]
    private var waiters: [String: [(Result<ReticulumLink, ConnectError>) -> Void]] = [:]

    /// Set once by InterfaceManager: fires with the raw decrypted,
    /// full-envelope LXMF message bytes whenever one is delivered over
    /// an accepted (DIRECT-method) link — whether as a single packet or
    /// a completed Resource, both funnel through here.
    var onIncomingLXMFMessage: ((Data) -> Void)?


    // MARK: - Connecting

    func connect(to destinationHashHex: String, completion: @escaping (Result<ReticulumLink, ConnectError>) -> Void) {

        let hex = destinationHashHex.lowercased()

        if let existing = linksByDestination[hex] {

            if existing.status == .active {
                completion(.success(existing))
                return
            }

            if existing.status == .handshake || existing.status == .pending {
                waiters[hex, default: []].append(completion)
                return
            }
            // .closed — fall through and establish a fresh one.
        }

        guard let destinationHash = Data(hexString: hex) else {
            completion(.failure(.invalidHash))
            return
        }

        // Actively asks the network for this peer's identity if we
        // haven't already heard an announce from them — a manually-typed
        // address, or one heard on a different node than this session,
        // used to fail right here with .unknownPeer before a single byte
        // reached the network, even when the peer was perfectly reachable.
        PeerStore.shared.resolveIdentity(for: hex) { [weak self] peer in

            guard let self else {
                return
            }

            guard let peer else {
                completion(.failure(.unknownPeer))
                return
            }

            self.beginHandshake(hex: hex, destinationHash: destinationHash, peer: peer, completion: completion)
        }
    }


    private func beginHandshake(hex: String, destinationHash: Data, peer: Peer, completion: @escaping (Result<ReticulumLink, ConnectError>) -> Void) {

        guard let link = ReticulumLink(destinationHash: destinationHash, peerIdentityPublicKey: peer.identityPublicKey) else {
            completion(.failure(.invalidPeerKey))
            return
        }

        link.send = { InterfaceManager.shared.send($0) }

        link.onEstablished = { [weak self, weak link] in
            guard let link else { return }
            self?.fireWaiters(for: hex, result: .success(link))
        }

        link.onFailed = { [weak self, weak link] in
            guard let link else { return }
            self?.remove(link)
            self?.fireWaiters(for: hex, result: .failure(.timeout))
        }

        link.onClosed = { [weak self, weak link] in
            guard let link else { return }
            self?.remove(link)
        }

        waiters[hex] = [completion]
        linksByDestination[hex] = link

        // Ask the network to refresh its route to this destination before
        // attempting the handshake — having received an announce once
        // doesn't guarantee every hop's path table still holds a fresh
        // route by the time we act on it, especially on a busy network.
        // Real clients (nomadnet, Sideband) do this too before connecting.
        if let pathRequest = PacketBuilder.buildPathRequestPacket(destinationHash: destinationHash) {
            InterfaceManager.shared.send(PacketBuilder.hdlcFrame(pathRequest))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self, weak link] in

            guard let self, let link, self.linksByDestination[hex] === link else {
                return
            }

            link.open()
            self.linksByLinkId[link.linkId.hexString] = link
        }
    }


    func disconnect(from destinationHashHex: String) {

        let hex = destinationHashHex.lowercased()

        guard let link = linksByDestination[hex] else {
            return
        }

        link.teardown()
        remove(link)
    }


    private func remove(_ link: ReticulumLink) {

        // Only remove an entry if IT'S STILL the same instance — a
        // superseding link (e.g. a fresh reconnect after this one went
        // stale) may already occupy that slot, and a delayed close/fail
        // callback on the old instance must not evict the new one.
        if linksByDestination[link.destinationHash.hexString] === link {
            linksByDestination.removeValue(forKey: link.destinationHash.hexString)
        }

        if linksByLinkId[link.linkId.hexString] === link {
            linksByLinkId.removeValue(forKey: link.linkId.hexString)
        }
    }


    private func fireWaiters(for destinationHashHex: String, result: Result<ReticulumLink, ConnectError>) {

        let callbacks = waiters.removeValue(forKey: destinationHashHex) ?? []

        for callback in callbacks {
            callback(result)
        }
    }


    // MARK: - Accepting incoming links
    //
    // We only ever accept links to our LXMF delivery destination — that's
    // what lets real LXMF clients (Sideband, NomadNet, ...) deliver a
    // message via DIRECT method, which is their default for a fresh
    // conversation (no ratchet yet). Called by InterfaceManager for every
    // LINKREQUEST packet type it sees.

    @discardableResult
    func handleIncomingLinkRequest(packet: ReticulumPacket) -> Bool {

        guard let destinationHash = packet.destinationHash, destinationHash == LXMFDestination.myDestinationHash else {
            return false
        }

        guard packet.payload.count >= 64 else {
            return false
        }

        guard let linkId = PacketBuilder.linkId(fromReceivedLinkRequest: packet.frame) else {
            return false
        }

        // A retransmitted/duplicate LINKREQUEST for a link we're already
        // handling — nothing to do, but not an error either.
        guard linksByLinkId[linkId.hexString] == nil else {
            return true
        }

        let initiatorEphemeralPublicKey = Data(packet.payload.prefix(32))

        let link = ReticulumLink(acceptingLinkId: linkId, forDestination: destinationHash)
        link.send = { InterfaceManager.shared.send($0) }

        link.onFailed = { [weak self, weak link] in
            guard let link else { return }
            self?.linksByLinkId.removeValue(forKey: link.linkId.hexString)
        }

        link.onClosed = { [weak self, weak link] in
            guard let link else { return }
            self?.linksByLinkId.removeValue(forKey: link.linkId.hexString)
        }

        link.onIncomingPayload = { [weak self] data in
            self?.onIncomingLXMFMessage?(data)
        }

        linksByLinkId[linkId.hexString] = link
        link.acceptAndProve(initiatorEphemeralPublicKey: initiatorEphemeralPublicKey)

        return true
    }


    // MARK: - Incoming packet routing
    //
    // Called by InterfaceManager for PROOF packets (always LRPROOF for us
    // — we never accept incoming links, so the only PROOF we'd ever
    // receive is one completing a handshake WE initiated) and any DATA
    // packet whose destination doesn't match one of our own identity
    // destinations. Returns whether the packet belonged to a known link.

    @discardableResult
    func handle(packet: ReticulumPacket) -> Bool {

        guard let destinationHash = packet.destinationHash else {
            return false
        }

        guard let link = linksByLinkId[destinationHash.hexString] else {
            return false
        }

        link.receive(packetType: packet.packetType, context: packet.context ?? 0, payload: packet.payload)
        return true
    }
}
