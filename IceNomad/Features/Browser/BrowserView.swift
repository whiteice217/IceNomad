//
//  BrowserView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//
//  Full-screen(ish) browser: a two-row top bar (address bar, then
//  announce/Tux/back/forward/page-name/favorites/reload/stop/download)
//  and the page content itself. On iOS, the announce and favorites
//  buttons open popovers (MUSitesDropdown / FavoritesManagerPopover) —
//  tapping a result connects immediately, no tab switch needed. A node
//  can also be reached from the Announce tab itself (tap/swipe a
//  "MU Sites" row). On Mac Catalyst, those same two buttons instead
//  open a real in-view side drawer (AnnounceDrawerView on the left,
//  FavoritesDrawerView on the right) that shrinks the page content
//  column rather than floating over it — a deliberate, Mac-only
//  reintroduction of the node-drawer idiom commit 69a72da removed in
//  favor of popovers; a persistent side panel reads as more native on a
//  full Mac window than it does on a phone screen, which is why iOS
//  keeps the popover behavior unchanged. The system tab bar stays
//  visible like every other tab — no more custom floating dock standing
//  in for it.
//

import SwiftUI

/// Reports a view's actual rendered size up to an ancestor via
/// .background(GeometryReader{...}) + .preference — the standard
/// SwiftUI "measure, then use the measurement" pattern. Used by
/// BrowserView's Micron scale-to-fit below.
private struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}


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
    /// Mac Catalyst only — drives the two in-view side drawers. iOS
    /// keeps using isShowingSitesDropdown/isShowingFavoritesManager
    /// above for its popovers, untouched.
    @State private var isShowingAnnounceDrawer = false
    @State private var isShowingFavoritesDrawer = false
    @State private var isEditingAddress = false
    @State private var addressDraft = ""
    /// The Micron content's actual rendered size at its full, unscaled
    /// virtualTerminalWidth — measured via SizeKey, then used to compute
    /// how far to shrink it to fit the real viewport. Starts at .zero
    /// (nothing measured yet on a fresh page), which the scale
    /// computation below treats as "don't scale" rather than divide by
    /// zero, at the cost of one brief unscaled/oversized frame before
    /// the real measurement lands and this view re-renders correctly.
    @State private var micronNaturalSize: CGSize = .zero

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

            #if targetEnvironment(macCatalyst)
            HStack(spacing: 0) {

                if isShowingAnnounceDrawer {

                    AnnounceDrawerView(sites: knownSites, contactStore: contactStore) { site in
                        browserState.connect(to: site.destinationHashHex)
                        isShowingAnnounceDrawer = false
                    } onClose: {
                        isShowingAnnounceDrawer = false
                    }
                    .frame(width: 280)
                    .background(Theme.surface)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    Divider()
                }

                browserContent

                if isShowingFavoritesDrawer {

                    Divider()

                    FavoritesDrawerView(
                        favoritesStore: favoritesStore,
                        currentPage: browserState.current,
                        isCurrentFavorited: isCurrentFavorited,
                        onToggleCurrent: {
                            guard let current = browserState.current else { return }
                            favoritesStore.toggle(destinationHashHex: current.destinationHashHex, path: current.path, label: nil)
                        },
                        onSelect: { favorite in
                            browserState.navigate(
                                to: BrowserState.PageRef(destinationHashHex: favorite.destinationHashHex, path: favorite.path)
                            )
                            isShowingFavoritesDrawer = false
                        },
                        onClose: {
                            isShowingFavoritesDrawer = false
                        }
                    )
                    .frame(width: 280)
                    .background(Theme.surface)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isShowingAnnounceDrawer)
            .animation(.easeInOut(duration: 0.22), value: isShowingFavoritesDrawer)
            #else
            browserContent
            #endif
        }
        .sheet(isPresented: $isShowingDownloads) {
            DownloadsView()
        }
        // The completed-download export prompt (pendingExport) is
        // presented from ContentView instead of here — a sheet can't
        // reliably stack on top of another sheet from sibling modifiers
        // on the same view, so if a download finished while the
        // Downloads sheet above was open, this second sheet silently
        // never showed. ContentView is always live regardless of what's
        // presented here, same fix already used for pendingChatHex.
        .onChange(of: pendingBrowseHex) { _, hex in

            guard let hex else { return }

            browserState.connect(to: hex)
            pendingBrowseHex = nil
        }
        .onAppear {

            guard browserState.current == nil else { return }

            // An explicit user choice (Settings > Browsing > Homepage)
            // always wins over the automatic default below.
            if let customHomepage = BrowserSettings.shared.customHomepage {

                browserState.navigate(to: customHomepage)

            // Tux as the Browser tab's home page is opt-in on a
            // successful startup preload only (StartupManager +
            // TuxPreloadStore) — shown instantly, no loading state to
            // watch. Without one (no connection, bypassed at the splash
            // screen, or a genuine failure), Browser falls back to
            // exactly its original behavior — the static favorites/
            // welcome screen (current stays nil) — rather than attempting
            // its own live fetch, which is exactly the loading state
            // Bryan didn't want to see, and would be redundant with the
            // explicit bypass he already chose at startup if that's why
            // there's no preload.
            } else if let preloaded = TuxPreloadStore.shared.content {

                browserState.loadPreloadedHome(content: preloaded)
            }
        }
    }


    /// The actual page content — favorites/welcome screen when nothing's
    /// loaded yet, otherwise the real Micron page renderer. Pulled out of
    /// `body` into its own property so it can sit inside the drawer-hosting
    /// HStack on Mac Catalyst and directly in the plain VStack on iOS,
    /// without duplicating this ~140-line block in both places.
    private var browserContent: some View {

        Group {

            if browserState.current == nil {

                // Momentary — connect(to:) below fires the instant this
                // appears, so this only shows for the brief window before
                // Tux's real content replaces it. Never re-fires once
                // `current` is set (nothing nils it back out), matching
                // "the first load of the session," not every tab switch.

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
                // hold their shape at their authored character
                // positions) with ordinary prose, both assuming
                // something closer to an 80-column terminal than a
                // phone screen. An AI-assisted "Reader" rewrite was
                // tried and real-device-tested, then removed after live
                // testing found it fabricating content — see
                // BrowserState.loadPage's header comment and Roadmap &
                // Ideas.md for the full story. Rendering the page at its
                // normal, correct, art-intact layout and scaling the
                // whole thing down uniformly to fit a narrow viewport
                // (same idea as "zoom to fit" in a PDF viewer) is what's
                // actually live: everything stays exactly as authored,
                // nothing reconstructed, nothing to hallucinate or
                // duplicate — just smaller. A wide viewport (Mac, iPad
                // landscape) skips scaling entirely and keeps this app's
                // original behavior: prose gets to use the extra room at
                // normal reading size rather than being scaled up past
                // it.
                GeometryReader { geometry in

                    let needsScaling = geometry.size.width - 32 < Self.virtualTerminalWidth
                    let scale: CGFloat = {
                        guard needsScaling, micronNaturalSize.width > 0 else { return 1 }
                        return min(1, (geometry.size.width - 32) / micronNaturalSize.width)
                    }()

                    ScrollViewReader { scrollProxy in

                        ScrollView(needsScaling ? .vertical : [.horizontal, .vertical]) {

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
                                    // Always the full terminal width when
                                    // scaling — MicronView lays out exactly
                                    // as authored, at its normal (unscaled)
                                    // size; the scaleEffect below shrinks
                                    // the whole rendered result afterward,
                                    // rather than asking MicronView itself
                                    // to lay out any differently.
                                    availableWidth: needsScaling ? Self.virtualTerminalWidth : geometry.size.width - 32,
                                    formState: browserState.formState,
                                    searchSuggestions: browserState.pageSuggestions,
                                    onSearchQueryChange: { browserState.updatePageSuggestions(for: $0) },
                                    onSelectSearchSuggestion: { browserState.selectSuggestion($0) }
                                ) { link in
                                    handleLinkTap(link)
                                }
                                .padding()
                                .background(
                                    // Measures the content's real,
                                    // unscaled size so the frame below
                                    // can be set to match the *scaled*
                                    // size — scaleEffect alone only
                                    // affects rendering, not the layout
                                    // space SwiftUI reserves for it, so
                                    // without this a narrow phone would
                                    // still reserve the full unscaled
                                    // width/height, leaving the visually-
                                    // shrunk content stranded in a much
                                    // larger blank area rather than
                                    // filling the actual viewport.
                                    GeometryReader { contentGeo in
                                        Color.clear.preference(key: SizeKey.self, value: contentGeo.size)
                                    }
                                )
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(
                                    width: needsScaling ? micronNaturalSize.width * scale : nil,
                                    height: needsScaling ? micronNaturalSize.height * scale : nil,
                                    alignment: .topLeading
                                )
                            }
                            // A ScrollView centers content that's narrower
                            // than its own viewport by default, rather
                            // than pinning it to the top-leading corner —
                            // barely noticeable for a full page, but
                            // glaring for anything short (the "Fetching…"
                            // loading message, a short page, a wide Mac
                            // window showing terminal-width content). Only
                            // a *minimum* width/height, not maxWidth:
                            // .infinity — that would fight the ScrollView's
                            // own sizing for content that's genuinely
                            // wider/taller than the viewport (a wide art
                            // banner still needs to pan, a long page still
                            // needs to scroll), min just guarantees short
                            // content still fills out to the corner.
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                        }
                        .onPreferenceChange(SizeKey.self) { size in
                            if size != .zero {
                                micronNaturalSize = size
                            }
                        }
                        .background(Theme.background)
                        .scrollDismissesKeyboard(.immediately)
                        .refreshable {
                            browserState.refresh()
                        }
                        .onChange(of: browserState.content) { _, _ in

                            // Was keyed off isLoading turning true — but
                            // isLoading flips back to false in a separate
                            // statement *before* content actually gets set
                            // to the real page (see BrowserState.loadPage),
                            // so that only ever caught the moment the tiny
                            // "Fetching…" placeholder appeared, never the
                            // moment real content actually arrived — which
                            // is when a reset is actually needed. content
                            // itself changes on every one of those
                            // transitions (loading placeholder, real page,
                            // error), so it's the trigger that actually
                            // means "something new just got laid out."
                            //
                            // Deferred a tick — calling scrollTo in the
                            // same synchronous pass as the content change
                            // races SwiftUI's own layout pass for the
                            // freshly-changed MicronView (new content size
                            // isn't known yet), so the scroll lands against
                            // stale geometry and silently does nothing.
                            // Confirmed on a real device specifically —
                            // Mac Catalyst's more immediate execution
                            // apparently doesn't expose the race the same
                            // way physical hardware does.
                            DispatchQueue.main.async {
                                scrollProxy.scrollTo("top", anchor: .topLeading)
                            }
                        }
                    }
                }
            }
        }
    }


    private var topBar: some View {

        VStack(spacing: 8) {
            addressRow

            #if targetEnvironment(macCatalyst)
            // iPhone's suggestions live inside the edit sheet instead —
            // no inline field there to drop a list under (see addressRow).
            if !browserState.addressSuggestions.isEmpty {
                AddressSuggestionsList(suggestions: browserState.addressSuggestions) { suggestion in
                    browserState.selectSuggestion(suggestion)
                    addressDraft = browserState.addressText
                }
            }
            #endif

            controlsRow
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .sheet(isPresented: $isEditingAddress) {

            AddressEditSheet(
                text: $addressDraft,
                suggestions: browserState.addressSuggestions,
                onQueryChange: { browserState.updateAddressSuggestions(for: $0) },
                onSelectSuggestion: { suggestion in browserState.selectSuggestion(suggestion) }
            ) {
                browserState.addressText = addressDraft
                browserState.navigateFromAddressBar()
            }
        }
    }


    private var addressRow: some View {

        #if targetEnvironment(macCatalyst)
        // Mac has a real toolbar-width field to work with — no need for
        // the iPhone sheet workaround below, just edit it in place.
        TextField("Node hash : path", text: $addressDraft)
            .font(.system(.footnote, design: .monospaced))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onAppear {
                addressDraft = browserState.addressText
            }
            .onChange(of: browserState.addressText) { _, newValue in
                // Keep the field in sync when navigation happens some
                // other way (a tapped link, Back/Forward, a favorite) —
                // don't leave it showing a stale address.
                addressDraft = newValue
                browserState.clearAddressSuggestions()
            }
            .onChange(of: addressDraft) { _, newValue in
                browserState.updateAddressSuggestions(for: newValue)
            }
            .onSubmit {
                browserState.addressText = addressDraft
                browserState.navigateFromAddressBar()
                browserState.clearAddressSuggestions()
            }
        #else
        // Tapping opens a full-size sheet to edit the address — the
        // toolbar has nowhere near enough width to show or edit a whole
        // "hash:/path" address inline without constantly scrolling the
        // field's contents past the visible edge.
        Button {
            addressDraft = browserState.addressText
            browserState.clearAddressSuggestions()
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
        #endif
    }


    private var controlsRow: some View {

        HStack(spacing: 14) {

            Button {
                #if targetEnvironment(macCatalyst)
                isShowingAnnounceDrawer.toggle()
                if isShowingAnnounceDrawer { isShowingFavoritesDrawer = false }
                #else
                isShowingSitesDropdown.toggle()
                #endif
            } label: {
                Image(systemName: AppTab.announce.icon)
            }
            #if !targetEnvironment(macCatalyst)
            .popover(isPresented: $isShowingSitesDropdown, arrowEdge: .top) {

                MUSitesDropdown(sites: knownSites, contactStore: contactStore) { site in

                    browserState.connect(to: site.destinationHashHex)
                    isShowingSitesDropdown = false
                }
                .presentationCompactAdaptation(.popover)
            }
            #endif

            Button {
                browserState.connect(to: BrowserState.tuxDestinationHashHex)
            } label: {
                Image(systemName: "sparkle.magnifyingglass")
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

            // iOS: short tap favorites/unfavorites the current page, long
            // press opens the full management popover (rename, folders,
            // delete) — two actions on one button rather than a second
            // toolbar slot, since they're both "the star button" to a
            // user. Mac Catalyst: a click always opens the equivalent
            // side drawer instead — the quick add/remove-current-page
            // action lives inside that drawer now (FavoritesDrawerView's
            // "Add/Remove This Page" row) rather than on this button.
            Button {
                #if targetEnvironment(macCatalyst)
                isShowingFavoritesDrawer.toggle()
                if isShowingFavoritesDrawer { isShowingAnnounceDrawer = false }
                #else
                guard let current = browserState.current else { return }
                favoritesStore.toggle(destinationHashHex: current.destinationHashHex, path: current.path, label: nil)
                #endif
            } label: {
                Image(systemName: isCurrentFavorited ? "star.fill" : "star")
            }
            #if !targetEnvironment(macCatalyst)
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
            #endif

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
            .sorted { peerStore.lastSeen(for: $0.destinationHashHex) > peerStore.lastSeen(for: $1.destinationHashHex) }
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


    /// Shared by both MicronView and IceReaderView's onLinkTap — a
    /// tapped link means the same thing regardless of which renderer
    /// produced it.
    private func handleLinkTap(_ link: MicronLink) {

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
}


// MARK: - Address bar autocomplete (Tux-backed, both platforms)

/// Live, database-backed suggestions — sourced from Tux's own search
/// index over Reticulum, not local text prediction — shown under the
/// Mac's inline address field and inside the iPhone edit sheet alike.
struct AddressSuggestionsList: View {

    let suggestions: [BrowserState.Suggestion]
    let onSelect: (BrowserState.Suggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in

                Button {
                    onSelect(suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {

                        Text(suggestion.label)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)

                        if !suggestion.snippet.isEmpty {
                            Text(suggestion.snippet)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < suggestions.count - 1 {
                    Divider()
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}


// MARK: - Address edit sheet

private struct AddressEditSheet: View {

    @Binding var text: String
    let suggestions: [BrowserState.Suggestion]
    let onQueryChange: (String) -> Void
    let onSelectSuggestion: (BrowserState.Suggestion) -> Void
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
                        .onChange(of: text) { _, newValue in
                            onQueryChange(newValue)
                        }
                }

                if !suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggestions) { suggestion in
                            Button {
                                onSelectSuggestion(suggestion)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {

                                    Text(suggestion.label)
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundStyle(Theme.textPrimary)

                                    if !suggestion.snippet.isEmpty {
                                        Text(suggestion.snippet)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
