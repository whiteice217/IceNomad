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
                .background(Theme.background)
                .onChange(of: messages.count) {

                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }

                    // A message can arrive while this chat is already open —
                    // mark it read immediately rather than leaving it to
                    // show as unread until the user backs out and back in.
                    messageStore.markAsRead(peerHashHex)
                }
                .onAppear {

                    if let lastId = messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }

                    messageStore.currentlyOpenPeerHex = peerHashHex
                    messageStore.markAsRead(peerHashHex)
                }
                .onDisappear {

                    if messageStore.currentlyOpenPeerHex == peerHashHex {
                        messageStore.currentlyOpenPeerHex = nil
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
                        .foregroundStyle(Theme.textSecondary)
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
                    .background(message.isOutgoing ? Theme.outgoingBubble : Theme.incomingBubble)
                    .foregroundStyle(message.isOutgoing ? .white : Theme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 4) {

                    Text(message.timestamp, style: .time)

                    if message.isOutgoing {
                        statusLabel(for: message)
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            }

            if !message.isOutgoing {
                Spacer(minLength: 40)
            }
        }
    }


    @ViewBuilder
    private func statusLabel(for message: ChatMessage) -> some View {

        switch message.status {

        case .sending:
            SendingIndicator()

        case .failed:
            Button {
                messageStore.retry(messageId: message.id, hex: peerHashHex)
            } label: {
                Label("Failed — Tap to Retry", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.danger)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)

        case .sent, .delivered:
            Text("Sent")
        }
    }


    // MARK: - Input Bar

    private var inputBar: some View {

        HStack(alignment: .bottom, spacing: 10) {

            TextField("Message", text: $draft, axis: .vertical)
                .font(.system(size: 17))
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 1)
                )
                // A vertical-axis TextField treats Return as "insert a
                // newline" by default with no built-in way to distinguish
                // plain Return from Shift+Return — `onSubmit` never fires
                // at all. Intercepting the key press ourselves gets the
                // desktop-chat convention Bryan asked for (Mac keyboard:
                // Return sends, Shift+Return inserts a newline) without
                // giving up multi-line composing.
                .onKeyPress(phases: .down) { press in

                    guard press.key == .return, !press.modifiers.contains(.shift) else {
                        return .ignored
                    }

                    sendDraft()
                    return .handled
                }

            Button {
                sendDraft()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.outgoingBubble, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }


    private func sendDraft() {

        messageStore.send(text: draft, to: peerHashHex)
        draft = ""
    }
}


/// Cycling "Sending." / "Sending.." / "Sending..." — purely time-driven
/// via `TimelineView` rather than an owned `Timer`/`@State` counter, so
/// there's nothing to invalidate/leak if the bubble scrolls offscreen or
/// the status changes mid-animation.
private struct SendingIndicator: View {

    var body: some View {

        TimelineView(.periodic(from: .now, by: 0.5)) { context in

            let dotCount = Int(context.date.timeIntervalSinceReferenceDate / 0.5) % 3 + 1

            Text("Sending" + String(repeating: ".", count: dotCount))
        }
    }
}
