//
//  MessageStore.swift
//  IceNomad
//
//  Local conversation storage, keyed by peer destination hash.
//
//  send(text:to:) now actually transmits: it encrypts the message to
//  the peer's known public key and sends a real DATA packet via
//  InterfaceManager. This only works once you've heard from that peer
//  at least once (an announce, or a prior message from them) — Reticulum
//  has no way to encrypt to someone whose public key you don't have.
//  If their key isn't known yet, the message is stored with status
//  .failed instead of silently pretending to send.
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

    /// Sends via DIRECT (Link-based) delivery first — confirmed against a
    /// real LXMF listener that plain opportunistic packets to this
    /// network don't arrive reliably, while DIRECT does every time.
    /// Falls back to opportunistic only if a Link genuinely can't be
    /// established but we still know the peer's public key. Either path
    /// actively asks the network for an unknown peer's identity first
    /// (via LinkManager/PeerStore), rather than failing instantly for a
    /// peer that's actually reachable — the message shows as .sending
    /// while that's in flight.
    @discardableResult
    func send(text: String, to hex: String) -> ChatMessage {

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return ChatMessage(peerHashHex: hex, text: "", isOutgoing: true, status: .failed)
        }

        let message = ChatMessage(peerHashHex: hex, text: trimmed, isOutgoing: true, status: .sending)
        append(message, for: hex)

        InterfaceManager.shared.sendDirectMessage(text: trimmed, to: hex) { [weak self] succeeded in

            guard let self else {
                return
            }

            if succeeded {
                self.updateStatus(.sent, forMessageId: message.id, hex: hex)
                return
            }

            // DIRECT failed — fall back to opportunistic if we at least
            // know the peer's public key (a Link-specific failure, e.g.
            // they don't accept links, doesn't mean they're unreachable).
            guard let peer = PeerStore.shared.peers.first(where: { $0.destinationHashHex == hex.lowercased() }) else {
                self.updateStatus(.failed, forMessageId: message.id, hex: hex)
                return
            }

            let opportunisticSucceeded = InterfaceManager.shared.sendMessage(
                text: trimmed,
                to: hex,
                recipientPublicKey: peer.identityPublicKey
            )

            self.updateStatus(opportunisticSucceeded ? .sent : .failed, forMessageId: message.id, hex: hex)
        }

        return message
    }


    private func updateStatus(_ status: DeliveryStatus, forMessageId id: UUID, hex: String) {

        guard var peerMessages = messagesByPeer[hex],
              let index = peerMessages.firstIndex(where: { $0.id == id })
        else {
            return
        }

        peerMessages[index].status = status
        messagesByPeer[hex] = peerMessages
        persist()
    }


    func deleteConversation(for hex: String) {

        messagesByPeer.removeValue(forKey: hex)
        persist()
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
