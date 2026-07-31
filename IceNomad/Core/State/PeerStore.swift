//
//  PeerStore.swift
//  IceNomad
//
//  Tracks peers discovered via ANNOUNCE packets. Shared as a singleton
//  so any view can observe it regardless of which InterfaceManager
//  instance is actually receiving traffic.
//
//  This is intentionally NOT persisted — it repopulates from live
//  announces each time the app runs. For persisted, user-curated
//  entries (with custom labels), see ContactStore.
//

import Foundation
import Combine
import SwiftUI


struct Peer: Identifiable {

    var id: String { destinationHashHex }

    let destinationHashHex: String
    var displayName: String?
    var lastSeen: Date
    var hopCount: UInt8?
    let nameHash: Data
    let identityPublicKey: Data
    /// Which interface most recently delivered an announce/message from
    /// this peer — nil if learned some other way. Drives the blue
    /// (RNode) / green (TCP) color-coding in Announce and Browser.
    var lastInterfaceType: ConnectionType?

    /// Blue for RNode, green for TCP — nil (default text color) if we
    /// don't know how we heard from them.
    var interfaceColor: Color? {

        switch lastInterfaceType {
        case .rNode: return Theme.rnodeBlue
        case .tcpClient: return Theme.tcpGreen
        case nil: return nil
        }
    }

    /// An announce's `nameHash` is a truncated hash of the destination's
    /// full aspect name — every peer on a shared public network isn't
    /// necessarily running IceNomad or even Reticulum-flavored LXMF/
    /// NomadNet at all, so these two are genuine *positive* checks
    /// against each protocol's real expected name hash (see
    /// NomadNetNode.expectedNameHash / LXMFDestination.nameHash), not
    /// just "isn't the other one" — a peer can be neither.
    var isNomadNetNode: Bool { NomadNetNode.isNode(self) }
    var isLXMFPeer: Bool { nameHash == LXMFDestination.nameHash }
}


final class PeerStore: ObservableObject {

    static let shared = PeerStore()

    static let announceLimitOptions = [10, 25, 75, 100, 250, 500]
    private static let maxAnnouncesKey = "peer_store_max_announces"
    private static let defaultMaxAnnounces = 75

    private init() {

        let saved = UserDefaults.standard.integer(forKey: Self.maxAnnouncesKey)
        maxAnnounces = saved == 0 ? Self.defaultMaxAnnounces : saved
    }


    @Published private(set) var peers: [Peer] = []

    /// Caps how many announced peers we keep around — oldest (by
    /// lastSeen) are evicted first once this is exceeded.
    @Published var maxAnnounces: Int {
        didSet {
            UserDefaults.standard.set(maxAnnounces, forKey: Self.maxAnnouncesKey)
            enforceLimit()
        }
    }

    private var index: [String: Int] = [:]

    /// Peers actively being connected to or browsed right now — exempt
    /// from eviction the same as saved contacts. Without this, a busy
    /// network can evict a peer between when you see it in the drawer
    /// and when your connection attempt actually lands, turning a slow
    /// handshake into a silent "haven't heard this node announce yet."
    private var pinnedHashes: Set<String> = []

    func pin(_ hex: String) {
        pinnedHashes.insert(hex)
    }

    func unpin(_ hex: String) {
        pinnedHashes.remove(hex)
    }


    func handle(frame: ReticulumFrame, source: ConnectionType) {

        let packet = ReticulumPacket(frame: frame)

        guard packet.isAnnounce else {
            return
        }

        guard let announce = AnnouncePacket(packet: packet) else {
            return
        }

        upsert(announce: announce, hopCount: frame.hopCount, source: source)
    }


    private func upsert(announce: AnnouncePacket, hopCount: UInt8?, source: ConnectionType) {

        let hex = announce.destinationHashHex
        let now = Date()

        if let existingIndex = index[hex] {

            peers[existingIndex].lastSeen = now
            peers[existingIndex].hopCount = hopCount
            peers[existingIndex].lastInterfaceType = source

            if let name = announce.displayName {
                peers[existingIndex].displayName = name
            }

        } else {

            let peer = Peer(
                destinationHashHex: hex,
                displayName: announce.displayName,
                lastSeen: now,
                hopCount: hopCount,
                nameHash: announce.nameHash,
                identityPublicKey: announce.encryptionPublicKey + announce.signingPublicKey,
                lastInterfaceType: source
            )

            index[hex] = peers.count
            peers.append(peer)
            enforceLimit()
        }
    }


    /// Records/updates a peer learned directly from a decrypted message
    /// envelope (not an announce) — so replying works even before
    /// they've announced. Their name_hash is assumed to be IceNomad's
    /// own shared aspect, since only a peer using the same app
    /// convention could have messaged you in the first place.
    func recordDirectContact(destinationHashHex: String, identityPublicKey: Data) {

        let now = Date()

        if let existingIndex = index[destinationHashHex] {

            peers[existingIndex].lastSeen = now

        } else {

            let peer = Peer(
                destinationHashHex: destinationHashHex,
                displayName: nil,
                lastSeen: now,
                hopCount: nil,
                nameHash: ReticulumDestination.nameHash,
                identityPublicKey: identityPublicKey,
                lastInterfaceType: nil
            )

            index[destinationHashHex] = peers.count
            peers.append(peer)
            enforceLimit()
        }
    }


    func clear() {

        peers.removeAll()
        index.removeAll()
    }


    /// Resolves a peer's identity, actively asking the network for it if
    /// we haven't already heard an announce from them — e.g. an address
    /// typed in by hand, or one heard on a different node than this
    /// session. Without this, connecting/messaging someone the app
    /// hasn't directly observed an announce from always failed locally
    /// before a single byte reached the network, even though the peer
    /// was perfectly reachable (confirmed against reticulum.saltycapn.com
    /// with the real Python RNS/LXMF libraries — this exact scenario
    /// delivers in under a second once a path request is sent).
    func resolveIdentity(for hex: String, timeout: TimeInterval = 10, completion: @escaping (Peer?) -> Void) {

        let hex = hex.lowercased()

        if let known = peers.first(where: { $0.destinationHashHex == hex }) {
            completion(known)
            return
        }

        guard let destinationHash = Data(hexString: hex),
              let pathRequest = PacketBuilder.buildPathRequestPacket(destinationHash: destinationHash)
        else {
            completion(nil)
            return
        }

        InterfaceManager.shared.send(PacketBuilder.hdlcFrame(pathRequest))

        let deadline = Date().addingTimeInterval(timeout)
        pollForIdentity(hex: hex, deadline: deadline, completion: completion)
    }


    private func pollForIdentity(hex: String, deadline: Date, completion: @escaping (Peer?) -> Void) {

        if let found = peers.first(where: { $0.destinationHashHex == hex }) {
            completion(found)
            return
        }

        guard Date() < deadline else {
            completion(nil)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.pollForIdentity(hex: hex, deadline: deadline, completion: completion)
        }
    }


    /// Evicts the oldest (by lastSeen) announced peers once over the
    /// limit — saved contacts and pinned (actively-connecting-to) peers
    /// are never evicted, since losing their cached public key would
    /// silently break messaging or connecting to them.
    private func enforceLimit() {

        guard peers.count > maxAnnounces else {
            return
        }

        let excess = peers.count - maxAnnounces
        let evictionCandidates = peers
            .filter { !ContactStore.shared.isContact($0.destinationHashHex) && !pinnedHashes.contains($0.destinationHashHex) }
            .sorted { $0.lastSeen < $1.lastSeen }

        let hexesToEvict = Set(evictionCandidates.prefix(excess).map { $0.destinationHashHex })

        guard !hexesToEvict.isEmpty else {
            return
        }

        peers.removeAll { hexesToEvict.contains($0.destinationHashHex) }

        index.removeAll()
        for (i, peer) in peers.enumerated() {
            index[peer.destinationHashHex] = i
        }
    }
}
