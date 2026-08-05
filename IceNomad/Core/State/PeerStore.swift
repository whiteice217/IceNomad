//
//  PeerStore.swift
//  IceNomad
//
//  Tracks peers discovered via ANNOUNCE packets. Shared as a singleton
//  so any view can observe it regardless of which InterfaceManager
//  instance is actually receiving traffic.
//
//  The live peer list itself is intentionally NOT persisted — it
//  repopulates from live announces each time the app runs. For
//  persisted, user-curated entries (with custom labels), see
//  ContactStore. Display *names* are the one exception (see
//  persistedNames below) — losing hop count/interface type on relaunch
//  is harmless, but a name you've already learned reverting to
//  "Unnamed" every time the app restarts, until that peer happens to
//  announce again, is a real regression a user notices immediately.
//

import Foundation
import Combine
import SwiftUI
import OSLog


struct Peer: Identifiable {

    var id: String { destinationHashHex }

    let destinationHashHex: String
    var displayName: String?
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

    /// Same idea as interfaceColor, but as text — color alone isn't a
    /// reliable way to communicate "heard over LoRa vs. a TCP gateway,"
    /// especially for anyone colorblind or just not aware of the
    /// convention. nil if we don't know how we heard from them.
    var interfaceLabel: String? {

        switch lastInterfaceType {
        case .rNode: return "RNode"
        case .tcpClient: return "TCP"
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

    // Used to be user-configurable (a picker on the old Announce tab,
    // 10-500 range) — that tab is gone now, and Bryan asked to just fix
    // this "behind the scenes" instead of rebuilding a settings UI for
    // it: "I doubt we would need more than that." 250 per category is
    // comfortably above the busiest real-world traffic actually measured
    // (rns.icenomad.net, bridged to a wider mesh, sustaining roughly one
    // *new distinct* real peer announcing per second) while still
    // bounding memory — a much lower default (75) was the original
    // culprit behind an "announces don't work" report that turned out to
    // be silent eviction, not a networking bug.
    private static let maxAnnouncesPerCategory = 250

    private init() {
        persistedNames = UserDefaults.standard.dictionary(forKey: Self.persistedNamesKey) as? [String: String] ?? [:]
    }


    @Published private(set) var peers: [Peer] = []

    /// Updated on *every* announce, including repeats that change
    /// nothing else — kept out of the `@Published` array on purpose.
    /// Any mutation of `peers` (even a single field via subscript)
    /// republishes the whole array, which SwiftUI then re-filters/
    /// re-sorts/redraws — on a busy relay (confirmed live: ~1 new
    /// distinct real peer announcing per second) that happened dozens
    /// of times a minute even when literally nothing about a peer had
    /// changed. `upsert` still needs an accurate "last seen" for
    /// eviction ordering, so it's tracked here instead, silently — the
    /// displayed "X ago" text updates on its own via SwiftUI's built-in
    /// relative-date formatting regardless of whether the parent view
    /// re-renders, so no publish is needed just to keep that fresh.
    private var lastSeenByHex: [String: Date] = [:]

    func lastSeen(for hex: String) -> Date {
        lastSeenByHex[hex] ?? .distantPast
    }


    private static let persistedNamesKey = "peer_store_persisted_names"

    /// The last name actually heard for a hex, surviving relaunch even
    /// though the live `peers` list doesn't. Consulted by
    /// ContactStore.displayName(for:) as a fallback below the live
    /// peer's own name (which wins if this session has already heard a
    /// fresher announce) but above the raw-hash "Unnamed" text.
    private var persistedNames: [String: String] {
        didSet {
            UserDefaults.standard.set(persistedNames, forKey: Self.persistedNamesKey)
        }
    }

    func lastKnownDisplayName(for hex: String) -> String? {
        persistedNames[hex]
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

        // Debug-level (hidden unless explicitly requested with `log
        // show --debug`/`log stream --level debug`) — a successful
        // announce receipt was previously silent by design ("arrives
        // constantly, only failures are worth logging"), which made it
        // impossible to tell "no announce arrived" apart from "arrived
        // and got silently dropped/miscategorized somewhere after this."
        Log.reticulum.debug("Announce IN from \(hex, privacy: .public) name=\(announce.displayName ?? "nil", privacy: .public) nameHash=\(announce.nameHash.hexString, privacy: .public) hops=\(hopCount.map(String.init) ?? "nil", privacy: .public) via=\(String(describing: source), privacy: .public)")

        lastSeenByHex[hex] = now

        if let existingIndex = index[hex] {

            // Compare against what we already have — a busy relay
            // re-announces the same peer with the same info constantly,
            // and touching `peers` (even just `lastSeen`, which now
            // lives in `lastSeenByHex` instead) for a no-op update would
            // force every observing view to redraw for nothing. Only
            // peers whose hop count, source interface, or name actually
            // changed are worth republishing.
            let existing = peers[existingIndex]
            let hopChanged = hopCount != existing.hopCount
            let sourceChanged = source != existing.lastInterfaceType
            let nameChanged = announce.displayName != nil && announce.displayName != existing.displayName

            guard hopChanged || sourceChanged || nameChanged else {
                return
            }

            peers[existingIndex].hopCount = hopCount
            peers[existingIndex].lastInterfaceType = source

            if let name = announce.displayName {
                peers[existingIndex].displayName = name
                persistedNames[hex] = name
            }

        } else {

            let peer = Peer(
                destinationHashHex: hex,
                displayName: announce.displayName,
                hopCount: hopCount,
                nameHash: announce.nameHash,
                identityPublicKey: announce.encryptionPublicKey + announce.signingPublicKey,
                lastInterfaceType: source
            )

            index[hex] = peers.count
            peers.append(peer)
            enforceLimit()

            if let name = announce.displayName {
                persistedNames[hex] = name
            }
        }
    }


    /// Records/updates a peer learned directly from a decrypted message
    /// envelope (not an announce) — so replying works even before
    /// they've announced. Their name_hash is assumed to be IceNomad's
    /// own shared aspect, since only a peer using the same app
    /// convention could have messaged you in the first place.
    func recordDirectContact(destinationHashHex: String, identityPublicKey: Data) {

        let now = Date()

        lastSeenByHex[destinationHashHex] = now

        if index[destinationHashHex] == nil {

            let peer = Peer(
                destinationHashHex: destinationHashHex,
                displayName: nil,
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
        lastSeenByHex.removeAll()
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


    /// Evicts the oldest (by lastSeen) announced peers once a *category*
    /// (LXMF / MU Sites / Other — same partition as Announce's own scope
    /// picker) exceeds `maxAnnouncesPerCategory`, independently per
    /// category — a flood of "Other" traffic can't evict LXMF/MU-Site
    /// peers, and vice versa. Saved contacts and pinned
    /// (actively-connecting-to) peers are never evicted, since losing
    /// their cached public key would silently break messaging or
    /// connecting to them. Sorts by `lastSeenByHex`, not any field on
    /// `Peer` itself — a peer can be re-announcing constantly with
    /// nothing else changing (see `upsert`), so `Peer` itself carries no
    /// lastSeen of its own anymore; the side table is the only accurate
    /// record of recency.
    private func enforceLimit() {

        var hexesToEvict: Set<String> = []

        for categoryPeers in categorized(peers) {

            guard categoryPeers.count > Self.maxAnnouncesPerCategory else {
                continue
            }

            let excess = categoryPeers.count - Self.maxAnnouncesPerCategory
            let evictionCandidates = categoryPeers
                .filter { !ContactStore.shared.isContact($0.destinationHashHex) && !pinnedHashes.contains($0.destinationHashHex) }
                .sorted { lastSeen(for: $0.destinationHashHex) < lastSeen(for: $1.destinationHashHex) }

            hexesToEvict.formUnion(evictionCandidates.prefix(excess).map { $0.destinationHashHex })
        }

        guard !hexesToEvict.isEmpty else {
            return
        }

        peers.removeAll { hexesToEvict.contains($0.destinationHashHex) }
        for hex in hexesToEvict {
            lastSeenByHex.removeValue(forKey: hex)
        }

        index.removeAll()
        for (i, peer) in peers.enumerated() {
            index[peer.destinationHashHex] = i
        }
    }


    /// Splits by destination kind (`Peer.isNomadNetNode`/`isLXMFPeer` are
    /// real positive checks against each aspect's actual expected name
    /// hash, not a guess) — mutually exclusive by construction, since a
    /// peer's nameHash matches at most one of the two real aspects.
    private func categorized(_ peers: [Peer]) -> [[Peer]] {

        var nodes: [Peer] = []
        var lxmf: [Peer] = []
        var other: [Peer] = []

        for peer in peers {

            if peer.isNomadNetNode {
                nodes.append(peer)
            } else if peer.isLXMFPeer {
                lxmf.append(peer)
            } else {
                other.append(peer)
            }
        }

        return [nodes, lxmf, other]
    }
}
