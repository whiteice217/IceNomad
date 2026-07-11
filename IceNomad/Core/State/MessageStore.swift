//
//  MessageStore.swift
//  IceNomad
//
//  Local conversation storage, keyed by peer destination hash.
//
//  IMPORTANT: `send(text:to:)` is LOCAL-ONLY right now. It records the
//  message and marks it "sent" so the messaging UI/UX can be built and
//  tested end-to-end, but nothing is actually transmitted over the
//  Reticulum network yet. Real delivery requires establishing an
//  encrypted Link to the destination, which needs the crypto layer
//  (Core/Services/Crypto — currently empty stub files) to be built out
//  first. Wire real sending in here once that exists.
//

import Foundation
import Combine


final class MessageStore: ObservableObject {

    static let shared = MessageStore()

    private init() {

        messagesByPeer = MessageStorage.shared.load()
    }


    @Published private(set) var messagesByPeer: [String: [ChatMessage]] = [:]


    func messages(for hex: String) -> [ChatMessage] {

        (messagesByPeer[hex] ?? []).sorted { $0.timestamp < $1.timestamp }
    }


    func lastMessage(for hex: String) -> ChatMessage? {

        messages(for: hex).last
    }


    /// All peer hashes with at least one message, for the conversation list.
    var conversationHashes: [String] {

        messagesByPeer
            .filter { !$0.value.isEmpty }
            .keys
            .sorted {
                (lastMessage(for: $0)?.timestamp ?? .distantPast) >
                (lastMessage(for: $1)?.timestamp ?? .distantPast)
            }
    }


    // MARK: - Sending / Receiving

    /// See the LOCAL-ONLY note at the top of this file.
    func send(text: String, to hex: String) {

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return
        }

        let message = ChatMessage(
            peerHashHex: hex,
            text: trimmed,
            isOutgoing: true,
            status: .sent
        )

        append(message, for: hex)
    }


    func receive(text: String, from hex: String) {

        let message = ChatMessage(
            peerHashHex: hex,
            text: text,
            isOutgoing: false
        )

        append(message, for: hex)
    }


    private func append(_ message: ChatMessage, for hex: String) {

        messagesByPeer[hex, default: []].append(message)
        persist()
    }


    private func persist() {

        MessageStorage.shared.save(messagesByPeer)
    }
}


// MARK: - Storage

private class MessageStorage {

    static let shared = MessageStorage()

    private let key = "app_messages_by_peer"

    func save(_ dict: [String: [ChatMessage]]) {

        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> [String: [ChatMessage]] {

        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: [ChatMessage]].self, from: data)
        else {
            return [:]
        }

        return dict
    }
}
