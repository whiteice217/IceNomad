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
                hopCount: hopCount
            )

            index[hex] = peers.count
            peers.append(peer)
        }
    }


    func clear() {

        peers.removeAll()
        index.removeAll()
    }
}
