//
//  MessagesView.swift
//  IceNomad
//

import SwiftUI
import UIKit

private enum ConversationSort: String, CaseIterable, Identifiable {

    case time = "Time"
    case name = "Name"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .time: return "clock"
        case .name: return "textformat"
        }
    }
}


struct MessagesView: View {

    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var contactStore = ContactStore.shared
    // Not read directly below — its only job is to make this view
    // re-render when a new announce resolves a peer's name, so
    // `contactStore.displayName(for:)` (which falls back to PeerStore's
    // live announced name for anyone without a manually-set label) stays
    // up to date instead of only refreshing "by accident" whenever some
    // other unrelated state change happens to trigger a redraw.
    @ObservedObject private var peerStore = PeerStore.shared
    @ObservedObject private var userProfile = UserProfile.shared

    @State private var isComposing = false
    @State private var pendingComposedHex: String?
    @State private var isShowingContacts = false
    @State private var isShowingQRCode = false
    @State private var sortOption: ConversationSort = .time
    /// Click-then-expand for the name in identityHeader — Bryan's
    /// explicit ask: clickable name row (pencil to its right), tapping
    /// it drops down the actual edit field + Save & Announce button,
    /// rather than an always-open TextField.
    @State private var isEditingName = false
    /// Seeded from userProfile.displayName the moment editing starts
    /// (see identityHeader's Button action) — a local draft rather than
    /// binding straight to the real value, so Save & Announce is a real
    /// explicit commit, not something that happens on every keystroke.
    @State private var nameDraft = ""
    /// Briefly true right after tapping Send Announce, for the same
    /// "Sent" checkmark feedback the old Announce tab's toolbar button
    /// used to show.
    @State private var didSendAnnounce = false
    /// Right-side drawer of LXMF-announced peers ("who can I message"),
    /// same pattern as Browser's old favorites drawer — replaces
    /// Browser's now-removed announce/NomadNet-sites drawer, which
    /// Bryan called out as confusing since it duplicated what used to
    /// be a separate Announce tab (also removed — its NomadNet-node and
    /// LoRa-specific views were dropped, since node discovery now
    /// happens through Tux search in Browser and there wasn't another
    /// obvious home for the LoRa view). This one is genuinely useful
    /// here since it's filtered to exactly what Messages needs (see
    /// lxmfPeers below).
    @State private var isShowingLXMFDrawer = false
    /// Single source of truth for navigation — the conversation list's
    /// own NavigationLink(value:) and the compose-sheet's completion both
    /// push onto this. (A cross-tab "open this chat" hint used to also
    /// feed in here, but that's now a modal sheet presented directly from
    /// ContentView instead — see its comment for why: relying on this
    /// view's onChange while its tab might not be the active one was
    /// unreliable across two separate fix attempts.)
    @State private var path: [String] = []

    /// Your own LXMF address — used by the identity header below.
    private static let lxmfAddress = LXMFDestination.myDestinationHashHex

    var body: some View {
        ZStack {

            messagesStack

            // Contacts opens from the left, Announced Contacts from the
            // right — Bryan's explicit ask, same dimmed-scrim/slide-in
            // visual language Browser's drawers already use, on both
            // platforms (this view isn't platform-branched the way
            // BrowserView is).
            if isShowingContacts {

                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { isShowingContacts = false }
                    .zIndex(1)

                HStack(spacing: 0) {

                    ContactsManagerPopover(contactStore: contactStore) { hex in
                        isShowingContacts = false
                        path.append(hex)
                    } onDone: {
                        isShowingContacts = false
                    }
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
                    .background(Theme.surface)

                    Spacer(minLength: 0)
                }
                .transition(.move(edge: .leading))
                .zIndex(2)
            }

            if isShowingLXMFDrawer {

                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { isShowingLXMFDrawer = false }
                    .zIndex(1)

                HStack(spacing: 0) {

                    Spacer(minLength: 0)

                    AnnounceDrawerView(
                        title: "Announced Contacts",
                        sites: lxmfPeers,
                        emptyStateText: "No announced contacts yet.",
                        contactStore: contactStore
                    ) { peer in
                        isShowingLXMFDrawer = false
                        path.append(peer.destinationHashHex)
                    } onClose: {
                        isShowingLXMFDrawer = false
                    }
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
                    .background(Theme.surface)
                }
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isShowingContacts)
        .animation(.easeInOut(duration: 0.22), value: isShowingLXMFDrawer)
    }


    /// Every LXMF-announced peer currently known — most recently heard
    /// first isn't imposed here since AnnounceDrawerView does its own
    /// sorting (time/hops/A-Z, user-selectable), matching what Browser's
    /// old drawer already gave people for NomadNet nodes.
    private var lxmfPeers: [Peer] {
        peerStore.peers.filter(\.isLXMFPeer)
    }


    private var messagesStack: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {

                identityHeader

                Divider()

                actionRow

                Divider()

                conversationListSection
            }
            .background(Theme.background)
            .navigationTitle("Messages")
            .navigationDestination(for: String.self) { hex in
                ChatView(peerHashHex: hex)
            }
            // A .popover here (as Contacts used to use, before it became
            // a drawer) is anchored to the ToolbarItem's underlying
            // UIBarButtonItem on Mac Catalyst, and that specific
            // combination crashes inside UIKitCore every time —
            // confirmed via a real crash report (SIGTRAP in
            // UIKeyboardSceneDelegate/UIPresentationController internals,
            // zero app frames), reproduced even after deferring the state
            // change by a run-loop tick, which ruled out a timing race.
            // .sheet sidesteps the bug entirely, so both of this view's
            // remaining sheets (QR code, Compose) use it, none a popover.
            .sheet(isPresented: $isShowingQRCode) {
                QRCodeView(label: "LXMF", value: Self.lxmfAddress, scheme: "lxmf")
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
        }
    }


    /// Your name, address, and QR/copy — moved here from Settings
    /// ("Your Identity") and Connections (`myAddressesCard`/
    /// `addressRow`) per Bryan's mockup: this is where people actually
    /// go looking for "how do I get reached," and it's the first thing
    /// shown in this tab now, not hidden behind a button. The name
    /// itself is a clickable row (name + trailing pencil) rather than
    /// an always-editable field — tapping it drops down the actual
    /// edit field and "Save & Announce" button beneath it, per Bryan's
    /// explicit ask for a click-then-expand interaction instead of a
    /// permanently-open TextField.
    private var identityHeader: some View {

        VStack(spacing: 10) {

            Button {

                if !isEditingName {
                    nameDraft = userProfile.displayName
                }
                isEditingName.toggle()

            } label: {
                HStack(spacing: 8) {
                    Text(userProfile.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "pencil")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if isEditingName {

                HStack(spacing: 8) {

                    TextField("Display Name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveNameDraft)

                    Button("Save & Announce") {
                        saveNameDraft()
                        isEditingName = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty || nameDraft == userProfile.displayName)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Text(Self.lxmfAddress)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 10) {

                identityActionButton(icon: "qrcode", label: "Display QR") {
                    isShowingQRCode = true
                }

                identityActionButton(icon: "doc.on.doc", label: "Copy Address") {
                    UIPasteboard.general.string = Self.lxmfAddress
                }

                // Unconditional — sends a real announce any time,
                // regardless of whether the name changed. Bryan's ask:
                // "a button to send a announcement for our lxmf
                // regardless." Replaces the trigger the old Announce
                // tab's toolbar Menu used to hold.
                identityActionButton(
                    icon: didSendAnnounce ? "checkmark.circle.fill" : "megaphone",
                    label: didSendAnnounce ? "Sent" : "Send Announce",
                    tint: didSendAnnounce ? Theme.success : nil
                ) {

                    InterfaceManager.shared.sendAnnounce()
                    didSendAnnounce = true

                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        didSendAnnounce = false
                    }
                }
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.2), value: isEditingName)
    }


    /// Icon-on-top, small text below — Bryan's fix for the horizontal
    /// icon+text Label wrapping into an awkward mid-word hyphenated
    /// break ("Ad-dress", "An-nounce") on a narrow phone screen.
    private func identityActionButton(icon: String, label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {

        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                Text(label)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }


    private func saveNameDraft() {

        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else { return }

        userProfile.displayName = trimmed
        nameDraft = trimmed
        // "Save & Announce" — the button's own label says what it does,
        // so this always sends a real announce, not just a local save.
        InterfaceManager.shared.sendAnnounce()
    }


    /// Contacts (far left), New Message (middle), Announced Contacts
    /// (far right) — a dedicated row instead of nav-bar toolbar items,
    /// per Bryan's mockup. "Announced Contacts" reads better than "LXMF
    /// Announces" to someone who doesn't know what LXMF means (Bryan's
    /// call). Equal-width buttons via frame(maxWidth: .infinity) inside
    /// a zero-spacing HStack gives the far-left/middle/far-right
    /// arrangement without needing explicit Spacers.
    private var actionRow: some View {

        HStack(spacing: 0) {

            actionButton(icon: "person.2", label: "Contacts") {
                isShowingContacts = true
                isShowingLXMFDrawer = false
            }

            actionButton(icon: "square.and.pencil", label: "New Message") {
                isComposing = true
            }

            actionButton(icon: "shareplay", label: "Announced Contacts") {
                isShowingLXMFDrawer = true
                isShowingContacts = false
            }
        }
        .padding(.vertical, 4)
    }


    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {

        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }


    /// Sort control (Time/Name) sits right above the list — same
    /// tap/click-driven Menu convention used everywhere else in this
    /// app rather than swipe gestures, which don't exist on a Mac
    /// trackpad click.
    @ViewBuilder
    private var conversationListSection: some View {

        if messageStore.conversationHashes.isEmpty {

            ContentUnavailableView(
                "No Conversations",
                systemImage: "message",
                description: Text("Start a new message to a contact or a known address.")
            )

        } else {

            VStack(spacing: 0) {

                HStack {

                    Text("Conversations")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    Spacer()

                    Picker("Sort", selection: $sortOption) {

                        ForEach(ConversationSort.allCases) { option in
                            Label(option.rawValue, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                // A per-row Menu instead of .swipeActions — swiping
                // needs a real drag gesture, which a trackpad click
                // doesn't produce under Mac Catalyst (confirmed: it
                // just didn't work at all on Mac). A tap/click-driven
                // menu behaves identically on both platforms.
                List(sortedConversationHashes, id: \.self) { hex in

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
    }


    private var sortedConversationHashes: [String] {

        switch sortOption {

        // conversationHashes is already sorted most-recent-first.
        case .time: return messageStore.conversationHashes

        case .name:
            return messageStore.conversationHashes.sorted {
                contactStore.displayName(for: $0)
                    .localizedCaseInsensitiveCompare(contactStore.displayName(for: $1)) == .orderedAscending
            }
        }
    }


    @ViewBuilder
    private func conversationRow(_ hex: String) -> some View {

        let unreadCount = messageStore.unreadCount(for: hex)

        HStack(spacing: 12) {

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 2) {

                Text(contactStore.displayName(for: hex))
                    .font(unreadCount > 0 ? .headline : .subheadline)

                if let last = messageStore.lastMessage(for: hex) {

                    Text(last.text)
                        .font(.subheadline)
                        .foregroundStyle(unreadCount > 0 ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {

                if let last = messageStore.lastMessage(for: hex) {

                    Text(last.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }

                if unreadCount > 0 {

                    Text("\(unreadCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.accent, in: Capsule())
                }
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


