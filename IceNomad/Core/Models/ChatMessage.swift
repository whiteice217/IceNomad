//
//  ChatMessage.swift
//  IceNomad
//

import Foundation

enum DeliveryStatus: String, Codable {
    case sending
    case sent
    case delivered
    case failed
}

struct ChatMessage: Identifiable, Codable {

    let id: UUID
    let peerHashHex: String
    var text: String
    let isOutgoing: Bool
    let timestamp: Date
    var status: DeliveryStatus

    init(
        peerHashHex: String,
        text: String,
        isOutgoing: Bool,
        timestamp: Date = Date(),
        status: DeliveryStatus = .sent
    ) {
        self.id = UUID()
        self.peerHashHex = peerHashHex
        self.text = text
        self.isOutgoing = isOutgoing
        self.timestamp = timestamp
        self.status = status
    }
}
