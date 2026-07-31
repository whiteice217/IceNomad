//
//  MessagesView.swift
//  IceNomad
//

import SwiftUI

struct MessagesView: View {

    @Binding var pendingChatHex: String?

    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var contactStore = ContactStore.shared

    @State private var isComposing = false
    @State private var pendingComposedHex: String?
    /// Single source of truth for navigation — the conversation list's
    /// own NavigationLink(value:), the compose-sheet's completion, and
    /// the cross-tab pendingChatHex hint (QR scan, Micron lxmf@hash link)
    /// all push onto this SAME path now. Previously the sheet/hint flow
    /// used a separate `navigationDestination(item:)` alongside the
    /// list's `navigationDestination(for: String.self)` — two resolvers
    /// registered for the same underlying String type on one
    /// NavigationStack is a real SwiftUI conflict (confirmed by it
    /// actually breaking: a QR scan routed to the Messages tab but never
    /// pushed the chat), so there's only one mechanism now.
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {

                if messageStore.conversationHashes.isEmpty {

                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "message",
                        description: Text("Start a new message to a contact or a known address.")
                    )

                } else {

                    // A per-row Menu instead of .swipeActions — swiping
                    // needs a real drag gesture, which a trackpad click
                    // doesn't produce under Mac Catalyst (confirmed: it
                    // just didn't work at all on Mac). A tap/click-driven
                    // menu behaves identically on both platforms.
                    List(messageStore.conversationHashes, id: \.self) { hex in

                        HStack {

                            NavigationLink(value: hex) {
                                conversationRow(hex)
                            }

                            Menu {

                                Button(role: .destructive) {
                                    messageStore.deleteConversation(for: hex)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title2)
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Theme.surface)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                }
            }
            .background(Theme.background)
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
            // Deferred to onDismiss for the same reason as the QR scanner
            // sheet in ConnectionsView: pushing navigation synchronously
            // inside the sheet's own completion closure races its
            // dismissal animation and can get silently dropped.
            .sheet(isPresented: $isComposing, onDismiss: {

                if let hex = pendingComposedHex {
                    pendingComposedHex = nil
                    path.append(hex)
                }

            }) {
                NewConversationView { hex in

                    pendingComposedHex = hex
                    isComposing = false
                }
            }
            .onChange(of: pendingChatHex) { _, hex in

                guard let hex else { return }

                path.append(hex)
                pendingChatHex = nil
            }
        }
    }


    @ViewBuilder
    private func conversationRow(_ hex: String) -> some View {

        HStack(spacing: 12) {

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 2) {

                Text(contactStore.displayName(for: hex))
                    .font(.headline)

                if let last = messageStore.lastMessage(for: hex) {

                    Text(last.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let last = messageStore.lastMessage(for: hex) {

                Text(last.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
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
                                        .foregroundStyle(Theme.textSecondary)
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
