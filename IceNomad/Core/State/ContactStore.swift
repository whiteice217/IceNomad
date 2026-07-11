//
//  ContactStore.swift
//  IceNomad
//
//  App-specific contacts, persisted locally. Entirely separate from
//  Apple's Contacts app / CNContact — these two are different entities
//  by design, and this store never touches the system address book.
//

import Foundation
import Combine


final class ContactStore: ObservableObject {

    static let shared = ContactStore()

    private init() {

        contacts = ContactStorage.shared.load()
    }


    @Published private(set) var contacts: [Contact] = []


    func isContact(_ hex: String) -> Bool {

        contacts.contains { $0.destinationHashHex == hex }
    }


    func contact(for hex: String) -> Contact? {

        contacts.first { $0.destinationHashHex == hex }
    }


    @discardableResult
    func addContact(hex: String, label: String? = nil) -> Contact {

        if let existing = contact(for: hex) {
            return existing
        }

        let contact = Contact(
            destinationHashHex: hex,
            customLabel: label,
            dateAdded: Date()
        )

        contacts.append(contact)
        persist()

        return contact
    }


    func removeContact(hex: String) {

        contacts.removeAll { $0.destinationHashHex == hex }
        persist()
    }


    /// Sets (or clears, if label is nil/empty) a custom label for a peer.
    /// If the peer isn't already a contact, labeling them adds them as one —
    /// naming someone implies you want to remember them.
    func setLabel(_ label: String?, for hex: String) {

        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = (trimmed?.isEmpty ?? true) ? nil : trimmed

        guard let index = contacts.firstIndex(where: { $0.destinationHashHex == hex }) else {

            addContact(hex: hex, label: finalLabel)
            return
        }

        contacts[index].customLabel = finalLabel
        persist()
    }


    /// Resolves what to actually display for a destination hash, in priority order:
    /// 1. A custom label you've set
    /// 2. The peer's live announced name, if currently known
    /// 3. A short, readable fallback built from the hash
    func displayName(for hex: String) -> String {

        if let label = contact(for: hex)?.customLabel, !label.isEmpty {
            return label
        }

        if let announced = PeerStore.shared.peers.first(where: { $0.destinationHashHex == hex })?.displayName {
            return announced
        }

        return "Unnamed (\(String(hex.prefix(8))))"
    }


    private func persist() {

        ContactStorage.shared.save(contacts)
    }
}


// MARK: - Storage

private class ContactStorage {

    static let shared = ContactStorage()

    private let key = "app_contacts"

    func save(_ contacts: [Contact]) {

        if let data = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> [Contact] {

        guard let data = UserDefaults.standard.data(forKey: key),
              let contacts = try? JSONDecoder().decode([Contact].self, from: data)
        else {
            return []
        }

        return contacts
    }
}
