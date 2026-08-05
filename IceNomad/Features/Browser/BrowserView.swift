//
//  BrowserView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//
//  The two platforms use genuinely different toolbar chrome, not just a
//  resized version of the same one:
//
//  - Mac Catalyst: a single consolidated row modeled on Mac Safari's own
//    toolbar (back/forward, then an address field with cache-toggle and
//    reload/stop nested inside it, then Home, Favorites, Downloads) —
//    see topBar/addressField.
//  - iOS: a bottom bar modeled directly on mobile Safari (Bryan's own
//    reference screenshots), not a shrunk copy of the Mac layout — see
//    bottomBar. Compact state: back/forward, a cache-toggle icon (only
//    once a page is loaded, matching Safari's own conditional icon),
//    a tap-to-expand address/search pill, and a trailing "..." menu
//    holding Home/Favorites/Reload/Stop/Downloads — the things Safari's
//    own "..." holds are tabs/extensions/bookmarks, which don't map onto
//    IceNomad's feature set, so this menu holds IceNomad's own
//    equivalents instead of trying to be pixel-identical. Tapping the
//    pill expands it in place (no modal sheet) into a full-width field
//    with live Tux-backed suggestions above it, matching Safari's own
//    expand-in-place behavior instead of the old iPhone-only edit sheet.
//
//  Both platforms share the favorites side drawer (FavoritesDrawerView)
//  — a deliberate reintroduction of the node-drawer idiom commit 69a72da
//  removed in favor of popovers, brought back because a persistent panel
//  turned out to be worth the screen real estate on both platforms, not
//  just Mac. Mac Catalyst has room to actually shrink the page content
//  column and show the drawer as a real sibling (see body's #if
//  branch); iOS has nowhere to shrink to on a phone-width screen, so it
//  instead slides in from the right as a dimmed overlay on top of the
//  content, dismissible by tapping the scrim. Browser used to have its
//  own matching announce/NomadNet-sites drawer here too, but it just
//  duplicated the app's real Announce tab and Bryan called it out as
//  confusing — removed entirely; Messages has its own LXMF-filtered
//  version of that same drawer pattern instead, which is what Messages
//  actually needs it for (finding people to message, not nodes to
//  browse). The system tab bar stays visible like every other tab — no
//  more custom floating dock standing in for it.
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


/// Display strings/colors for BrowserState.PageSource's badge (see
/// pageSourceBadge) — kept here rather than on the enum itself since
/// BrowserState is a pure Core/State model with no SwiftUI dependency.
private extension BrowserState.PageSource {

    var label: String {
        switch self {
        case .tuxHTTP: return "Tux HTTP"
        case .tuxCache: return "Tux Cache"
        case .live: return "Live"
        }
    }

    var color: Color {
        switch self {
        case .tuxHTTP: return Theme.pageSourceTuxHTTP
        case .tuxCache: return Theme.pageSourceTuxCache
        case .live: return Theme.pageSourceLive
        }
    }
}


struct BrowserView: View {

    @Binding var selectedTab: AppTab
    @Binding var pendingChatHex: String?
    /// Set after a QR scan (Connections) resolves to a NomadNet page —
    /// the Announce tab used to also set this, but that tab was removed.
    @Binding var pendingBrowseHex: String?

    @StateObject private var browserState = BrowserState()
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var contactStore = ContactStore.shared
    @ObservedObject private var favoritesStore = FavoritesStore.shared
    @ObservedObject private var browserSettings = BrowserSettings.shared
    /// Drives the cache-toggle buttons' disabled/relabeled state below
    /// — Tux's cache is a relay-specific feature, so those buttons need
    /// to react live if the user reconnects onto/off of the IceNomad
    /// Public Relay while Browser is open, not just at launch.
    @ObservedObject private var interfaceManager = InterfaceManager.shared
    /// This drawer's back on both platforms now — Mac got it back first
    /// (Bryan's explicit ask, after the Announce tab it used to
    /// duplicate was deleted entirely, leaving Browser with no way to
    /// discover NomadNet nodes), iOS followed shortly after ("add the
    /// reticulum mu announces back to the ... dots button").
    @ObservedObject private var peerStore = PeerStore.shared

    @State private var isShowingDownloads = false
    /// Reached only via the homepage's hidden 7-tap logo gate — see
    /// TuxHTMLWebView.onAdminGateTriggered and TuxAdminWebView.
    @State private var isShowingTuxAdmin = false
    /// Drives the favorites drawer on both platforms — presented as a
    /// push/shrink sibling on Mac Catalyst, a dimmed overlay on iOS (see
    /// body).
    @State private var isShowingFavoritesDrawer = false
    /// "Browse the Reticulum Net" drawer — see peerStore's declaration
    /// above for the back-and-forth on which platforms have this.
    @State private var isShowingAnnounceDrawer = false
    /// Compact vs. expanded state for iOS's bottomBar (see its header
    /// comment) — Mac's addressRow edits addressDraft inline and never
    /// touches this, so it's effectively iOS-only despite being shared
    /// state, kept ungated since both platforms already share
    /// addressDraft below.
    @State private var isEditingAddress = false
    @State private var addressDraft = ""
    #if !targetEnvironment(macCatalyst)
    /// Auto-focuses the address field the moment isEditingAddress flips
    /// true (see its .onAppear) — plain SwiftUI TextField, no custom
    /// UIViewRepresentable needed now that it starts empty instead of
    /// pre-filled-and-selected.
    @FocusState private var isAddressFieldFocused: Bool
    /// Width of the drawer-hosting ZStack on iOS, captured via a
    /// `.background(GeometryReader)` side channel rather than wrapping
    /// browserContent in a GeometryReader directly — nesting a second
    /// GeometryReader immediately above browserContent's own internal
    /// one (used for Micron's scale-to-fit math) is a known SwiftUI trap
    /// where the inner reader can end up reporting the wrong width. This
    /// keeps browserContent's ancestor chain identical to how it sat
    /// before drawers existed on iOS; only the (unrelated) drawer sizing
    /// reads this value.
    @State private var iosContentWidth: CGFloat = UIScreen.main.bounds.width
    #endif
    /// The Micron content's actual rendered size at its full, unscaled
    /// virtualTerminalWidth — measured via SizeKey, then used to compute
    /// how far to shrink it to fit the real viewport. Starts at .zero
    /// (nothing measured yet on a fresh page), which the scale
    /// computation below treats as "don't scale" rather than divide by
    /// zero, at the cost of one brief unscaled/oversized frame before
    /// the real measurement lands and this view re-renders correctly.
    @State private var micronNaturalSize: CGSize = .zero

    /// A page's document-wide background color, reported up via
    /// MicronBackgroundKey — nil for the ordinary case (no declared
    /// background), non-nil for pages that commit to one color
    /// throughout (banner/art pages). Only used to decide whether the
    /// rendered content gets the rounded "card" framing Tux's own HTTP
    /// renderer gives these pages (main.py's view_page route only sets
    /// container_style when the page has a background) — the app used
    /// to always render a colored page as a flat, square-cornered fill
    /// with no such framing.
    @State private var pageBackground: Color? = nil

    /// Prose never wraps narrower than this, regardless of the actual
    /// viewport — roughly an 80-column terminal at the current Dynamic
    /// Type body size, a common real-world assumption baked into how
    /// NomadNet page authors format their content.
    private static let virtualTerminalWidth: CGFloat = {
        let approxCharWidth = UIFont.preferredFont(forTextStyle: .body).pointSize * 0.6
        return approxCharWidth * 80
    }()

    var body: some View {
        contentAndChrome
            .sheet(isPresented: $isShowingDownloads) {
                DownloadsView()
            }
            .fullScreenCover(isPresented: $isShowingTuxAdmin) {
                TuxAdminWebView(onDone: { isShowingTuxAdmin = false })
            }
            // The download save-location prompt (pendingExport — asked
            // *before* fetching, see DownloadManager's header comment) is
            // presented from ContentView instead of here — a sheet can't
            // reliably stack on top of another sheet from sibling modifiers
            // on the same view, so if a link were tapped while the
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
                // there's no preload. The real HTML homepage wins whenever
                // both preloads landed — Bryan's call: the app's own
                // homepage should always be "the full version" when it's
                // reachable at all, not the plainer native reconstruction.
                } else if let html = TuxPreloadStore.shared.htmlContent {

                    browserState.loadPreloadedHomeHTML(html: html)

                } else if let preloaded = TuxPreloadStore.shared.content {

                    browserState.loadPreloadedHome(content: preloaded)
                }
            }
    }


    /// Mac keeps the bar on top; iOS moves it to the bottom (see the
    /// header comment) — different enough between platforms that this
    /// is two real branches, not one shared VStack with the bar's
    /// position parameterized.
    @ViewBuilder
    private var contentAndChrome: some View {

        #if targetEnvironment(macCatalyst)
        VStack(spacing: 0) {

            topBar

            Divider()

            HStack(spacing: 0) {

                browserContent

                // Both drawers open from the right now (Bryan's call —
                // same edge, same idea as Favorites), mutually exclusive
                // via the toggle guards on each button, so sharing this
                // one slot is safe: only one is ever actually shown.
                if isShowingAnnounceDrawer {

                    Divider()

                    AnnounceDrawerView(
                        title: "Browse the Reticulum Net",
                        sites: knownSites,
                        emptyStateText: "No NomadNet sites heard yet.",
                        contactStore: contactStore
                    ) { site in
                        browserState.connect(to: site.destinationHashHex)
                        isShowingAnnounceDrawer = false
                    } onClose: {
                        isShowingAnnounceDrawer = false
                    }
                    .frame(width: 280)
                    .background(Theme.surface)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

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
            .animation(.easeInOut(duration: 0.22), value: isShowingFavoritesDrawer)
            .animation(.easeInOut(duration: 0.22), value: isShowingAnnounceDrawer)
        }
        #else
        // Bottom-anchored, Safari-style (see the header comment) — the
        // bar sits below the content instead of above it, so this VStack
        // is content-then-bar, the reverse of Mac's order above. The
        // favorites drawer slides in from the right, matching where the
        // "..." menu that opens it lives.
        VStack(spacing: 0) {

            // No room to shrink content on a phone-width screen, so the
            // drawer overlays instead of pushing — a dimmed scrim behind
            // it (tap to dismiss) is the standard mobile side-drawer
            // convention. Sized as a fraction of the real available
            // width (iosContentWidth, captured via a background side
            // channel — see its declaration) rather than a fixed point
            // value, so it reads sensibly on both a compact iPhone and a
            // wide iPad window, capped at 340pt so it doesn't sprawl on
            // iPad.
            ZStack {

                browserContent

                // "Browse the Reticulum Net" — back on iOS too now,
                // reached from the "..." menu (Bryan: "add the
                // reticulum mu announces back to the ... dots button"),
                // same right-side slide-in as Favorites since it opens
                // from the same trailing control.
                if isShowingAnnounceDrawer {

                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { isShowingAnnounceDrawer = false }
                        .zIndex(1)

                    HStack(spacing: 0) {

                        Spacer(minLength: 0)

                        AnnounceDrawerView(
                            title: "Browse the Reticulum Net",
                            sites: knownSites,
                            emptyStateText: "No NomadNet sites heard yet.",
                            contactStore: contactStore
                        ) { site in
                            browserState.connect(to: site.destinationHashHex)
                            isShowingAnnounceDrawer = false
                        } onClose: {
                            isShowingAnnounceDrawer = false
                        }
                        .frame(width: min(340, iosContentWidth * 0.85))
                        .frame(maxHeight: .infinity)
                        .background(Theme.surface)
                    }
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
                }

                if isShowingFavoritesDrawer {

                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { isShowingFavoritesDrawer = false }
                        .zIndex(1)

                    HStack(spacing: 0) {

                        Spacer(minLength: 0)

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
                        .frame(width: min(340, iosContentWidth * 0.85))
                        .frame(maxHeight: .infinity)
                        .background(Theme.surface)
                    }
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { iosContentWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newWidth in iosContentWidth = newWidth }
                }
            )
            .animation(.easeInOut(duration: 0.25), value: isShowingFavoritesDrawer)
            .animation(.easeInOut(duration: 0.25), value: isShowingAnnounceDrawer)

            Divider()

            bottomBar
        }
        #endif
    }


    /// The actual page content — favorites/welcome screen when nothing's
    /// loaded yet, otherwise the real Micron page renderer. Pulled out of
    /// `body` into its own property so it can sit inside the drawer-hosting
    /// HStack on Mac Catalyst and directly in the plain VStack on iOS,
    /// without duplicating this ~140-line block in both places.
    /// True only for Tux's own homepage — the sole TuxHTMLWebView
    /// instance allowed to arm the hidden admin tap-gate. Same PageRef
    /// identity loadPreloadedHomeHTML/goHome always use, so this stays
    /// accurate whether the homepage was just preloaded at launch or
    /// navigated back to later via the Home button.
    /// Whether Tux's HTTP/cache/search extras are available at all right
    /// now — everything in this file that gates on relay reads this one
    /// place, so the "clear and concise" requirement (Bryan's words)
    /// only has one source of truth to keep consistent.
    private var isUsingIceNomadRelay: Bool {
        interfaceManager.isUsingIceNomadPublicRelay
    }


    private var isShowingTuxHomepage: Bool {
        browserState.current == BrowserState.PageRef(destinationHashHex: BrowserState.tuxDestinationHashHex, path: "/page/index.mu")
    }


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

            } else if let html = browserState.htmlContent {

                // Tux actually has this page and rendered it as real
                // HTML (see BrowserState.fetchTuxHTML) — shown as-is
                // instead of the native scale-to-fit Micron path below,
                // which only ever sees `browserState.content` (empty
                // while htmlContent is set). The admin tap-gate only
                // ever arms on the one instance actually showing the
                // app's own homepage (see isShowingTuxHomepage) — never
                // on some other node's page that happens to render via
                // Tux's HTML tier too.
                TuxHTMLWebView(
                    html: html,
                    onNavigateToPage: { ref in browserState.navigate(to: ref) },
                    onAdminGateTriggered: isShowingTuxHomepage ? { isShowingTuxAdmin = true } : nil
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

                        // Always both axes now — scale-to-fit narrows
                        // most content correctly, but real pages still
                        // sometimes exceed the scaled width (Bryan's
                        // call: "this is something we will have to live
                        // with, let's enable horizontal scrolling"),
                        // so panning right stays available as a fallback
                        // instead of clipping unreachable content.
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
                                .onPreferenceChange(MicronBackgroundKey.self) { pageBackground = $0 }
                                // Rounded "card" framing, matching Tux's
                                // own HTTP renderer — only applied when
                                // the page actually declares a background
                                // (see pageBackground's doc comment); a
                                // plain page is left exactly as before,
                                // clipped to its own natural bounds (a
                                // no-op — nothing in it extends past
                                // that) rather than square-cornered.
                                .clipShape(RoundedRectangle(cornerRadius: pageBackground != nil ? 12 : 0, style: .continuous))
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
                                    // Falling back to virtualTerminalWidth
                                    // (not 0) here is the actual fix for a
                                    // real, confirmed-live bug: before any
                                    // measurement lands, micronNaturalSize
                                    // is .zero, and a literal
                                    // .frame(width: 0, height: 0) doesn't
                                    // just misreport this view's size
                                    // upward — it genuinely constrains
                                    // everything inside it (including the
                                    // background GeometryReader below) to
                                    // zero space on that render pass. With
                                    // nothing there to measure, the
                                    // preference fires exactly once with
                                    // (0, 0) and never gets a second
                                    // chance to self-correct — permanently
                                    // stuck unscaled at full width
                                    // (visually overflowing, unclipped,
                                    // past its own collapsed frame) with a
                                    // ScrollView that thinks it has ~0
                                    // content to scroll. Using a sane,
                                    // known-nonzero width up front (we
                                    // already know MicronView renders at
                                    // exactly virtualTerminalWidth before
                                    // scaling — no measurement needed for
                                    // that part) lets the real content
                                    // render and get measured correctly on
                                    // the very first pass; height is left
                                    // nil (natural sizing) until measured,
                                    // since nil never collapses anything
                                    // to zero the way an explicit 0 does.
                                    width: needsScaling ? (micronNaturalSize.width > 0 ? micronNaturalSize.width : Self.virtualTerminalWidth) * scale : nil,
                                    height: needsScaling && micronNaturalSize.height > 0 ? micronNaturalSize.height * scale : nil,
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
        // Which of BrowserState's three tiers actually resolved the
        // page on screen — nil (so nothing shows) on the home screen,
        // while loading, or on an error page; see pageSourceBadge.
        .overlay(alignment: .top) {
            if let source = browserState.pageSource {
                pageSourceBadge(source)
            }
        }
    }


    private func pageSourceBadge(_ source: BrowserState.PageSource) -> some View {

        HStack(spacing: 6) {
            Circle()
                .fill(source.color)
                .frame(width: 7, height: 7)
            Text(source.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(source.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
        .padding(.top, 6)
    }


    #if targetEnvironment(macCatalyst)
    /// One consolidated row instead of the old address-row-then-
    /// controls-row stack — Bryan's reference was Mac Safari's own
    /// toolbar (back/forward, then a single address field with icons
    /// nested inside it, then Home, then the remaining controls) sent
    /// as a screenshot, not a resized version of the old two-row bar.
    /// Same "our own equivalents in Safari's slots" approach as the iOS
    /// bottomBar: no sidebar toggle (nothing in IceNomad maps to it),
    /// Announce/Favorites/Downloads live in Safari's share/+/tabs slot
    /// on the right instead.
    private var topBar: some View {

        VStack(spacing: 8) {
            HStack(spacing: 10) {

                Button {
                    browserState.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!browserState.canGoBack)
                .help("Back")

                Button {
                    browserState.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!browserState.canGoForward)
                .help("Forward")

                addressField

                Button {
                    browserState.goToTuxHomepage()
                } label: {
                    Image(systemName: "house")
                }
                .help("Go to Tux")

                // Back after being removed earlier the same day — that
                // removal assumed the app's real Announce tab still
                // covered NomadNet-node discovery, but that whole tab
                // was deleted shortly after, leaving Browser with no way
                // to see what's out there. Mac-only per Bryan's ask;
                // opens from the right, same edge and same icon as the
                // app's normal announce concept, matching Favorites.
                Button {
                    isShowingAnnounceDrawer.toggle()
                    if isShowingAnnounceDrawer { isShowingFavoritesDrawer = false }
                } label: {
                    Image(systemName: "shareplay")
                }
                .help("Browse the Reticulum Net")

                Button {
                    isShowingFavoritesDrawer.toggle()
                    if isShowingFavoritesDrawer { isShowingAnnounceDrawer = false }
                } label: {
                    Image(systemName: isCurrentFavorited ? "star.fill" : "star")
                }
                .help("Favorites")

                DownloadsButton(progress: downloadManager.activeProgress) {
                    isShowingDownloads = true
                }
                .help("Downloads")
            }

            if !browserState.addressSuggestions.isEmpty {
                AddressSuggestionsList(suggestions: browserState.addressSuggestions) { suggestion in
                    browserState.selectSuggestion(suggestion)
                    addressDraft = browserState.addressText
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }


    /// The address text field plus its two Safari-style nested icons —
    /// cache toggle leading (Bryan's mapping, same as the iOS bar's
    /// equivalent slot), reload/stop trailing. The trailing icon swaps
    /// to Stop while loading rather than sitting disabled next to a
    /// separate always-visible Stop button, matching Safari's own
    /// reload-icon-becomes-stop-icon behavior.
    private var addressField: some View {

        HStack(spacing: 8) {

            Button {
                browserSettings.preferCachedContent.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: browserSettings.preferCachedContent ? "opticaldiscdrive.fill" : "opticaldiscdrive")
                    Text(isUsingIceNomadRelay ? (browserSettings.preferCachedContent ? "Tux Cache On" : "Tux Cache Off") : "Tux Cache Unavailable")
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .disabled(!isUsingIceNomadRelay)
            .foregroundStyle(isUsingIceNomadRelay ? Theme.textSecondary : Theme.textSecondary.opacity(0.5))
            .help(
                isUsingIceNomadRelay
                    ? (browserSettings.preferCachedContent ? "Prefer Cached Pages (tap for Live)" : "Live Mode (tap for Cached)")
                    : "Tux's cache is only available via the IceNomad Public Relay."
            )

            TextField("Search or hash:/path", text: $addressDraft)
                .font(.system(.footnote, design: .monospaced))
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onAppear {
                    addressDraft = browserState.addressText
                }
                .onChange(of: browserState.addressText) { _, newValue in
                    // Keep the field in sync when navigation happens
                    // some other way (a tapped link, Back/Forward, a
                    // favorite) — don't leave it showing a stale address.
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

            Button {
                if browserState.isLoading {
                    browserState.cancelLoad()
                } else {
                    browserState.refresh()
                }
            } label: {
                Image(systemName: browserState.isLoading ? "xmark" : "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .disabled(browserState.current == nil && !browserState.isLoading)
            .help(browserState.isLoading ? "Stop Loading" : "Reload")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity)
    }
    #else
    /// Bottom-anchored, Safari-style — see BrowserView's header comment
    /// for the full reasoning. Compact state: back/forward, a
    /// cache-toggle icon (only once a page is loaded, matching Safari's
    /// own conditional icon in that same slot), a tap-to-expand
    /// address/search pill, and a trailing "..." menu. Expanded state
    /// (isEditingAddress): the pill becomes a full-width field with live
    /// suggestions above it and a circular cancel button, in place —
    /// no modal sheet, matching Safari's own expand-in-place behavior.
    private var bottomBar: some View {

        VStack(spacing: 8) {

            if isEditingAddress, !browserState.addressSuggestions.isEmpty {
                AddressSuggestionsList(suggestions: browserState.addressSuggestions) { suggestion in
                    browserState.selectSuggestion(suggestion)
                    addressDraft = browserState.addressText
                    browserState.clearAddressSuggestions()
                    isEditingAddress = false
                }
            }

            HStack(spacing: 10) {

                if isEditingAddress {

                    // Two rounds of layout patches on a custom
                    // UIViewRepresentable text field (for select-all-on-
                    // focus) didn't fix a sizing bug live — a UIKit-
                    // backed view's own intrinsic-size/priority behavior
                    // kept overriding whatever explicit SwiftUI frame it
                    // was given, pushing a separate sibling Cancel
                    // button off-screen regardless. Dropped that
                    // approach entirely: a plain SwiftUI TextField
                    // behaves correctly here, starts *empty* rather than
                    // pre-filled-and-selected (nothing to select or
                    // clear, just type the new address), and — per
                    // Bryan's follow-up — the Cancel "x" now lives
                    // *inside* the field as a trailing overlay instead
                    // of a separate button beside it, so the field
                    // itself can genuinely fill the row edge to edge
                    // instead of sharing width with a sibling.
                    TextField("Search or enter address", text: $addressDraft)
                        .font(.system(.subheadline, design: .monospaced))
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isAddressFieldFocused)
                        .submitLabel(.go)
                        .onChange(of: addressDraft) { _, newValue in
                            browserState.updateAddressSuggestions(for: newValue)
                        }
                        .onSubmit {
                            browserState.addressText = addressDraft
                            browserState.navigateFromAddressBar()
                            browserState.clearAddressSuggestions()
                            isEditingAddress = false
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 36)
                        .padding(.vertical, 8)
                        .background(Theme.surface, in: Capsule())
                        .overlay(alignment: .trailing) {

                            Button {
                                isEditingAddress = false
                                addressDraft = ""
                                browserState.clearAddressSuggestions()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 10)
                        }
                        .onAppear {
                            isAddressFieldFocused = true
                        }

                } else {

                    HStack(spacing: 2) {

                        Button {
                            browserState.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 40, height: 40)
                        }
                        .disabled(!browserState.canGoBack)

                        Button {
                            browserState.goForward()
                        } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 32, height: 32)
                        }
                        .disabled(!browserState.canGoForward)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)

                    // Only once a page is active — matching Safari's own
                    // conditional icon in this slot (absent on a blank/
                    // idle bar, present once there's something to act
                    // on). Bryan's explicit mapping: this position is
                    // our cache toggle, a direct tap-to-toggle button
                    // like the Mac controlsRow one, not a submenu.
                    if browserState.current != nil {
                        Button {
                            browserSettings.preferCachedContent.toggle()
                        } label: {
                            VStack(spacing: 0) {
                                Image(systemName: browserSettings.preferCachedContent ? "opticaldiscdrive.fill" : "opticaldiscdrive")
                                Text("Tux Cache")
                                    .font(.system(size: 7))
                                Text(isUsingIceNomadRelay ? (browserSettings.preferCachedContent ? "On" : "Off") : "N/A")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .frame(width: 50, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isUsingIceNomadRelay)
                        .foregroundStyle(isUsingIceNomadRelay ? Theme.accent : Theme.accent.opacity(0.4))
                        .help(
                            isUsingIceNomadRelay
                                ? (browserSettings.preferCachedContent ? "Prefer Cached Pages (tap for Live)" : "Live Mode (tap for Cached)")
                                : "Tux's cache is only available via the IceNomad Public Relay."
                        )
                    }

                    Button {
                        // Starts empty on purpose — see the TextField's
                        // own comment above for why (no more select-all,
                        // nothing to clear, just type the new address).
                        addressDraft = ""
                        browserState.clearAddressSuggestions()
                        isEditingAddress = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                            Text(browserState.current == nil ? "Search or enter address" : pageDisplayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    // Everything Safari tucks in here (tabs, extensions,
                    // bookmarks) is a concept IceNomad doesn't share, so
                    // this holds IceNomad's own equivalents instead —
                    // Home, Browse the Reticulum Net, and Favorites.
                    // Announce briefly lived here, was removed for
                    // duplicating the app's real Announce tab, then that
                    // whole tab was deleted — "Browse the Reticulum Net"
                    // came back on Mac's toolbar directly, and here on
                    // iOS (Bryan's ask), since Browser otherwise has no
                    // way left to discover NomadNet nodes.
                    Menu {

                        Button {
                            browserState.goToTuxHomepage()
                        } label: {
                            Label("Home", systemImage: "house")
                        }

                        Button {
                            isShowingAnnounceDrawer = true
                            isShowingFavoritesDrawer = false
                        } label: {
                            Label("Browse the Reticulum Net", systemImage: "shareplay")
                        }

                        Button {
                            isShowingFavoritesDrawer = true
                            isShowingAnnounceDrawer = false
                        } label: {
                            Label(isCurrentFavorited ? "Favorites (Page Saved)" : "Favorites", systemImage: isCurrentFavorited ? "star.fill" : "star")
                        }

                        Divider()

                        Button {
                            browserState.refresh()
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        .disabled(browserState.current == nil)

                        Button {
                            browserState.cancelLoad()
                        } label: {
                            Label("Stop", systemImage: "xmark")
                        }
                        .disabled(!browserState.isLoading)

                        Divider()

                        Button {
                            isShowingDownloads = true
                        } label: {
                            Label("Downloads", systemImage: "arrow.down.circle")
                        }

                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 36, height: 36)
                            .background(Circle().stroke(Theme.textSecondary.opacity(0.35)))
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
    #endif


    /// NomadNet nodes the app currently knows about from live announces
    /// — most recently heard first, so the drawer leads with what's
    /// actually reachable right now rather than something heard once a
    /// long time ago.
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

                        // Bracketed label — Tux groups results per node
                        // now (real AI summary when one exists, an FTS
                        // snippet otherwise), matching Bryan's spec:
                        // "[friendly name] short summary".
                        Text("[\(suggestion.label)]")
                            .font(.system(.footnote, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)

                        if !suggestion.snippet.isEmpty {
                            Text(suggestion.snippet)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Other matching pages on this same node — "* any
                // subpages and relevant summaries if present" (Bryan's
                // spec). Each navigates on its own tap, reusing onSelect
                // with a synthetic Suggestion built from the subpage's
                // own path/label/snippet but the parent's node hash.
                ForEach(suggestion.subpages) { subpage in

                    Button {
                        onSelect(
                            BrowserState.Suggestion(
                                label: subpage.label,
                                snippet: subpage.snippet,
                                destinationHashHex: suggestion.destinationHashHex,
                                path: subpage.path
                            )
                        )
                    } label: {
                        HStack(alignment: .top, spacing: 4) {

                            Text("*")
                                .foregroundStyle(Theme.textSecondary)

                            VStack(alignment: .leading, spacing: 1) {

                                Text(subpage.label)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)

                                if !subpage.snippet.isEmpty {
                                    Text(subpage.snippet)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                        .padding(.trailing, 10)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if index < suggestions.count - 1 {
                    Divider()
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
