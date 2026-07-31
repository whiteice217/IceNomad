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
    /// Unread-badge tracking. Outgoing messages are always "read" (they're
    /// ours); incoming ones start unread until the conversation is opened.
    /// Decoded with a default of `true` so messages persisted before this
    /// field existed don't retroactively show as unread.
    var isRead: Bool

    init(
        peerHashHex: String,
        text: String,
        isOutgoing: Bool,
        timestamp: Date = Date(),
        status: DeliveryStatus = .sent,
        isRead: Bool = true
    ) {
        self.id = UUID()
        self.peerHashHex = peerHashHex
        self.text = text
        self.isOutgoing = isOutgoing
        self.timestamp = timestamp
        self.status = status
        self.isRead = isRead
    }

    private enum CodingKeys: String, CodingKey {
        case id, peerHashHex, text, isOutgoing, timestamp, status, isRead
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        peerHashHex = try container.decode(String.self, forKey: .peerHashHex)
        text = try container.decode(String.self, forKey: .text)
        isOutgoing = try container.decode(Bool.self, forKey: .isOutgoing)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        status = try container.decode(DeliveryStatus.self, forKey: .status)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? true
    }
}
