//
//  MessageHistoryStore.swift
//  IceNomad
//
//  Tracks every peer you've ever exchanged a message with, independent of
//  MessageStore's conversation data. Deleting a conversation clears its
//  messages, but the fact that you talked to that peer stays here until
//  the user explicitly clears it from the Contacts popover's History
//  section — a separate, append-only log rather than a view over
//  MessageStore.
//

import Foundation
import Combine


struct MessageHistoryEntry: Identifiable, Codable {

    var destinationHashHex: String
    var firstSeen: Date

    var id: String { destinationHashHex }
}


final class MessageHistoryStore: ObservableObject {

    static let shared = MessageHistoryStore()

    private init() {

        entries = MessageHistoryStorage.shared.load()
    }


    @Published private(set) var entries: [MessageHistoryEntry] = []


    /// Called on every outgoing and incoming message. Deliberately doesn't
    /// touch ContactStore or set any label — History rows resolve their
    /// display name live via ContactStore.displayName(for:), the same
    /// fallback-to-latest-announce chain conversations already use.
    func recordActivity(hex: String) {

        guard !entries.contains(where: { $0.destinationHashHex == hex }) else {
            return
        }

        entries.append(MessageHistoryEntry(destinationHashHex: hex, firstSeen: Date()))
        persist()
    }


    func clear(hex: String) {

        entries.removeAll { $0.destinationHashHex == hex }
        persist()
    }


    func clearAll() {

        entries.removeAll()
        persist()
    }


    private func persist() {

        MessageHistoryStorage.shared.save(entries)
    }
}


// MARK: - Storage

private class MessageHistoryStorage {

    static let shared = MessageHistoryStorage()

    private let key = "app_message_history"

    func save(_ entries: [MessageHistoryEntry]) {

        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> [MessageHistoryEntry] {

        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([MessageHistoryEntry].self, from: data)
        else {
            return []
        }

        return entries
    }
}
