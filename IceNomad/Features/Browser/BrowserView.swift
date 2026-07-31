//
//  BrowserView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//
//  Full-screen(ish) browser: a two-row top bar (address bar, then
//  announce/back/forward/page-name/favorites/reload/stop/download) and
//  the page content itself. The announce button is a dropdown of known
//  MU sites (NomadNet nodes) rather than an in-Browser drawer — tapping
//  one connects immediately, no tab switch needed. A node can also be
//  reached from the Announce tab itself (tap/swipe a "MU Sites" row).
//  The system tab bar stays visible like every other tab — no more
//  custom floating dock standing in for it.
//

import SwiftUI

struct BrowserView: View {

    @Binding var selectedTab: AppTab
    @Binding var pendingChatHex: String?
    /// Set by AnnounceView's "Browse" swipe action.
    @Binding var pendingBrowseHex: String?

    @StateObject private var browserState = BrowserState()
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var contactStore = ContactStore.shared
    @ObservedObject private var favoritesStore = FavoritesStore.shared
    @ObservedObject private var peerStore = PeerStore.shared

    @State private var isShowingDownloads = false
    @State private var isShowingSitesDropdown = false
    @State private var isShowingFavoritesManager = false
    @State private var isEditingAddress = false
    @State private var addressDraft = ""

    /// Prose never wraps narrower than this, regardless of the actual
    /// viewport — roughly an 80-column terminal at the current Dynamic
    /// Type body size, a common real-world assumption baked into how
    /// NomadNet page authors format their content.
    private static let virtualTerminalWidth: CGFloat = {
        let approxCharWidth = UIFont.preferredFont(forTextStyle: .body).pointSize * 0.6
        return approxCharWidth * 80
    }()

    var body: some View {
        VStack(spacing: 0) {

            topBar

            Divider()

            if browserState.current == nil {

                // Nothing navigated to yet — lead with the logo and
                // either saved pages or a short explainer, instead of
                // dropping straight into placeholder Micron content.
                BrowserHomeView(
                    favorites: favoritesStore.favorites,
                    onSelect: { favorite in
                        browserState.navigate(
                            to: BrowserState.PageRef(destinationHashHex: favorite.destinationHashHex, path: favorite.path)
                        )
                    },
                    onDelete: { favorite in
                        favoritesStore.remove(destinationHashHex: favorite.destinationHashHex, path: favorite.path)
                    }
                )

            } else {

                // Real Micron pages mix ASCII-art banners (which only
                // hold their shape unwrapped — the page pans horizontally
                // like an image for these) with ordinary prose (which
                // needs to wrap somewhere, or every paragraph becomes one
                // unreadable giant line). But that wrap point shouldn't
                // be the live portrait viewport width — real .mu pages
                // assume something closer to a fixed-width terminal, and
                // squeezing prose down to a narrow phone-in-portrait
                // width breaks the page's intended structure/alignment
                // the same way reflowing ASCII art would. So prose wraps
                // to a fixed virtual-terminal width instead, never
                // narrower than that regardless of orientation — portrait
                // pans horizontally same as art does; a wider viewport
                // (landscape, iPad) still gets to use its extra room.
                GeometryReader { geometry in

                    ScrollViewReader { scrollProxy in

                        ScrollView([.horizontal, .vertical]) {

                            VStack(spacing: 0) {

                                // Zero-size anchor purely so scrollTo has
                                // something to target at the very top —
                                // without this, a freshly-loaded page (or
                                // a refresh) kept whatever scroll offset
                                // the previous page was left at instead of
                                // starting at the top like a real page load.
                                Color.clear.frame(width: 1, height: 1).id("top")

                                MicronView(
                                    source: browserState.content,
                                    availableWidth: max(Self.virtualTerminalWidth, geometry.size.width - 32) // matches the .padding() below
                                ) { link in

                                    if link.isMessagingLink, let hex = link.destinationHashHex {

                                        pendingChatHex = hex
                                        selectedTab = .messages

                                    } else if link.isFileLink {

                                        if let hex = link.destinationHashHex ?? browserState.current?.destinationHashHex {
                                            downloadManager.download(path: link.path, from: hex)
                                        }

                                    } else {
                                        browserState.followLink(link)
                                    }
                                }
                                .padding()
                            }
                        }
                        .background(Theme.background)
                        .scrollDismissesKeyboard(.immediately)
                        .onChange(of: browserState.isLoading) { _, isLoading in

                            guard isLoading else { return }
                            scrollProxy.scrollTo("top", anchor: .topLeading)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingDownloads) {
            DownloadsView()
        }
        .sheet(item: $downloadManager.pendingExport) { export in

            DocumentExporterView(url: export.url) {
                downloadManager.pendingExport = nil
            }
        }
        .onChange(of: pendingBrowseHex) { _, hex in

            guard let hex else { return }

            browserState.connect(to: hex)
            pendingBrowseHex = nil
        }
    }


    private var topBar: some View {

        VStack(spacing: 8) {
            addressRow
            controlsRow
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .sheet(isPresented: $isEditingAddress) {

            AddressEditSheet(text: $addressDraft) {
                browserState.addressText = addressDraft
                browserState.navigateFromAddressBar()
            }
        }
    }


    private var addressRow: some View {

        // Tapping opens a full-size sheet to edit the address — the
        // toolbar has nowhere near enough width to show or edit a whole
        // "hash:/path" address inline without constantly scrolling the
        // field's contents past the visible edge.
        Button {
            addressDraft = browserState.addressText
            isEditingAddress = true
        } label: {

            Text(browserState.addressText.isEmpty ? "Node hash : path" : browserState.addressText)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(browserState.addressText.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }


    private var controlsRow: some View {

        HStack(spacing: 14) {

            Button {
                isShowingSitesDropdown.toggle()
            } label: {
                Image(systemName: AppTab.announce.icon)
            }
            .popover(isPresented: $isShowingSitesDropdown, arrowEdge: .top) {

                MUSitesDropdown(sites: knownSites, contactStore: contactStore) { site in

                    browserState.connect(to: site.destinationHashHex)
                    isShowingSitesDropdown = false
                }
                .presentationCompactAdaptation(.popover)
            }

            Button {
                browserState.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!browserState.canGoBack)

            Button {
                browserState.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!browserState.canGoForward)

            Text(pageDisplayName)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            // Short tap: favorite/unfavorite the current page. Long press:
            // open the full management popover (rename, folders, delete) —
            // two different actions on one button rather than a second
            // toolbar slot, since they're both "the star button" to a user.
            Button {
                guard let current = browserState.current else { return }
                favoritesStore.toggle(destinationHashHex: current.destinationHashHex, path: current.path, label: nil)
            } label: {
                Image(systemName: isCurrentFavorited ? "star.fill" : "star")
            }
            .disabled(browserState.current == nil)
            .onLongPressGesture {
                isShowingFavoritesManager = true
            }
            .popover(isPresented: $isShowingFavoritesManager, arrowEdge: .top) {

                FavoritesManagerPopover(favoritesStore: favoritesStore) { favorite in

                    browserState.navigate(
                        to: BrowserState.PageRef(destinationHashHex: favorite.destinationHashHex, path: favorite.path)
                    )
                    isShowingFavoritesManager = false
                }
                .presentationCompactAdaptation(.popover)
            }

            Button {
                browserState.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(browserState.current == nil)

            Button {
                browserState.cancelLoad()
            } label: {
                Image(systemName: "xmark")
            }
            .disabled(!browserState.isLoading)

            DownloadsButton(progress: downloadManager.activeProgress) {
                isShowingDownloads = true
            }
        }
    }


    /// NomadNet nodes ("MU sites") the app currently knows about from
    /// live announces — most recently heard first, so the dropdown leads
    /// with what's actually reachable right now rather than something
    /// heard once a long time ago.
    private var knownSites: [Peer] {

        peerStore.peers
            .filter(\.isNomadNetNode)
            .sorted { $0.lastSeen > $1.lastSeen }
    }


    private var pageDisplayName: String {

        guard let current = browserState.current else {
            return "Not Connected"
        }

        return contactStore.displayName(for: current.destinationHashHex)
    }


    private var isCurrentFavorited: Bool {

        guard let current = browserState.current else { return false }
        return favoritesStore.isFavorite(destinationHashHex: current.destinationHashHex, path: current.path)
    }
}


// MARK: - Address edit sheet

private struct AddressEditSheet: View {

    @Binding var text: String
    let onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Address") {

                    TextField("Node hash : path", text: $text, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3...6)
                        .focused($isFocused)
                }
            }
            .navigationTitle("Edit Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {

                    Button("Go") {
                        onSubmit()
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.fraction(0.3), .medium])
    }
}
