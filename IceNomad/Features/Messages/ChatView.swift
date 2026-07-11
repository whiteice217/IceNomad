//
//  ChatView.swift
//  IceNomad
//

import SwiftUI

struct ChatView: View {

    let peerHashHex: String

    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var contactStore = ContactStore.shared
    @ObservedObject private var peerStore = PeerStore.shared

    @State private var draft = ""
    @State private var isEditingLabel = false
    @State private var labelDraft = ""

    var body: some View {
        VStack(spacing: 0) {

            ScrollViewReader { proxy in

                ScrollView {

                    LazyVStack(alignment: .leading, spacing: 8) {

                        ForEach(messages) { message in

                            bubble(for: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {

                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onAppear {

                    if let lastId = messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            Divider()

            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {

            ToolbarItem(placement: .principal) {

                VStack(spacing: 0) {

                    Text(displayName)
                        .font(.headline)

                    Text(peerHashHex)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {

                Button {
                    labelDraft = contactStore.contact(for: peerHashHex)?.customLabel ?? ""
                    isEditingLabel = true
                } label: {
                    Image(systemName: "person.text.rectangle")
                }
            }
        }
        .alert("Label This Contact", isPresented: $isEditingLabel) {

            TextField("Name", text: $labelDraft)

            Button("Save") {
                contactStore.setLabel(labelDraft, for: peerHashHex)
            }

            Button("Cancel", role: .cancel) {}

        } message: {
            Text("This label only affects how you see this contact — it isn't shared with them.")
        }
    }


    private var messages: [ChatMessage] {

        messageStore.messages(for: peerHashHex)
    }


    private var displayName: String {

        contactStore.displayName(for: peerHashHex)
    }


    // MARK: - Bubble

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {

        HStack {

            if message.isOutgoing {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 2) {

                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(message.isOutgoing ? Color.blue : Color(.secondarySystemBackground))
                    .foregroundStyle(message.isOutgoing ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !message.isOutgoing {
                Spacer(minLength: 40)
            }
        }
    }


    // MARK: - Input Bar

    private var inputBar: some View {

        HStack(spacing: 10) {

            TextField("Message", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)

            Button {
                sendDraft()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }


    private func sendDraft() {

        messageStore.send(text: draft, to: peerHashHex)
        draft = ""
    }
}
