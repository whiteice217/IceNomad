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


struct Peer: Identifiable {

    var id: String { destinationHashHex }

    let destinationHashHex: String
    var displayName: String?
    var lastSeen: Date
    var hopCount: UInt8?
    let nameHash: Data
    let identityPublicKey: Data
}


final class PeerStore: ObservableObject {

    static let shared = PeerStore()

    private init() {}


    @Published private(set) var peers: [Peer] = []

    private var index: [String: Int] = [:]


    func handle(frame: ReticulumFrame) {

        let packet = ReticulumPacket(frame: frame)

        guard packet.isAnnounce else {
            return
        }

        guard let announce = AnnouncePacket(packet: packet) else {
            return
        }

        upsert(announce: announce, hopCount: frame.hopCount)
    }


    private func upsert(announce: AnnouncePacket, hopCount: UInt8?) {

        let hex = announce.destinationHashHex
        let now = Date()

        if let existingIndex = index[hex] {

            peers[existingIndex].lastSeen = now
            peers[existingIndex].hopCount = hopCount

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
                identityPublicKey: announce.encryptionPublicKey + announce.signingPublicKey
            )

            index[hex] = peers.count
            peers.append(peer)
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
                identityPublicKey: identityPublicKey
            )

            index[destinationHashHex] = peers.count
            peers.append(peer)
        }
    }


    func clear() {

        peers.removeAll()
        index.removeAll()
    }
}
