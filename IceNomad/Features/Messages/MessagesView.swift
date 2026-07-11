//
//  MessagesView.swift
//  IceNomad
//

import SwiftUI

struct MessagesView: View {

    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var contactStore = ContactStore.shared

    @State private var isComposing = false
    @State private var navigationTarget: String?

    var body: some View {
        NavigationStack {
            Group {

                if messageStore.conversationHashes.isEmpty {

                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "message",
                        description: Text("Start a new message to a contact or a known address.")
                    )

                } else {

                    List(messageStore.conversationHashes, id: \.self) { hex in

                        NavigationLink(value: hex) {
                            conversationRow(hex)
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .navigationDestination(for: String.self) { hex in
                ChatView(peerHashHex: hex)
            }
            .toolbar {

                ToolbarItem(placement: .topBarTrailing) {

                    Button {
                        isComposing = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $isComposing) {

                NewConversationView { hex in

                    isComposing = false
                    navigationTarget = hex
                }
            }
            .navigationDestination(item: $navigationTarget) { hex in
                ChatView(peerHashHex: hex)
            }
        }
    }


    @ViewBuilder
    private func conversationRow(_ hex: String) -> some View {

        HStack(spacing: 12) {

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {

                Text(contactStore.displayName(for: hex))
                    .font(.headline)

                if let last = messageStore.lastMessage(for: hex) {

                    Text(last.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let last = messageStore.lastMessage(for: hex) {

                Text(last.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}


// MARK: - New Conversation

private struct NewConversationView: View {

    let onSelect: (String) -> Void

    @ObservedObject private var contactStore = ContactStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var manualHash = ""
    @State private var manualLabel = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {

                Section("Enter an Address") {

                    TextField("Destination hash (32 hex characters)", text: $manualHash)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))

                    TextField("Label (optional)", text: $manualLabel)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Start Conversation") {
                        startManualConversation()
                    }
                    .disabled(manualHash.isEmpty)
                }

                if !contactStore.contacts.isEmpty {

                    Section("Contacts") {

                        ForEach(contactStore.contacts) { contact in

                            Button {
                                onSelect(contact.destinationHashHex)
                            } label: {

                                VStack(alignment: .leading) {

                                    Text(contactStore.displayName(for: contact.destinationHashHex))
                                        .foregroundStyle(.primary)

                                    Text(contact.destinationHashHex)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }


    private func startManualConversation() {

        let cleaned = manualHash
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard cleaned.count == 32,
              cleaned.allSatisfy({ $0.isHexDigit })
        else {
            errorMessage = "A destination hash is 32 hex characters (16 bytes)."
            return
        }

        let label = manualLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        contactStore.addContact(
            hex: cleaned,
            label: label.isEmpty ? nil : label
        )

        onSelect(cleaned)
    }
}
