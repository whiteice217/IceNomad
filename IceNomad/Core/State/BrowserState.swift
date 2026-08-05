//
//  BrowserState.swift
//  IceNomad
//
//  Navigation state for the browser: current page, back/forward
//  history, and the address bar. Page content is fetched for real over
//  a Reticulum Link (LinkManager) — an established, encrypted session to
//  the node, reused across pages on the same node and torn down when
//  navigating to a different one.
//

import Foundation
import Combine

final class BrowserState: ObservableObject {

    struct PageRef: Equatable {
        var destinationHashHex: String
        var path: String

        /// Parses a typed "hash:/path" address — the same validation
        /// `navigateFromAddressBar()` has always applied (32 hex-digit
        /// hash, empty path defaults to the index page), pulled out here
        /// so a second real caller (the Settings homepage field) doesn't
        /// need its own copy of the same rules.
        static func parse(_ raw: String) -> PageRef? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = trimmed.firstIndex(of: ":") else { return nil }

            let hash = String(trimmed[trimmed.startIndex..<colonIndex]).lowercased()
            let path = String(trimmed[trimmed.index(after: colonIndex)...])

            guard hash.count == 32, hash.allSatisfy({ $0.isHexDigit }) else { return nil }

            return PageRef(destinationHashHex: hash, path: path.isEmpty ? "/page/index.mu" : path)
        }
    }

    /// Tux's real, live Reticulum destination hash — IceNomad's built-in
    /// search engine, and (see BrowserView) the Browser tab's default
    /// home page for a session's first load.
    static let tuxDestinationHashHex = "3e844dc99cfd7548d1b25d5b6a4a8172"

    struct Suggestion: Identifiable {
        let id = UUID()
        var label: String
        var snippet: String
        var destinationHashHex: String
        var path: String
        /// Other matching pages on this same node, each with its own
        /// snippet — Tux's /suggest now consolidates per node (real AI
        /// summary when one exists, an FTS snippet otherwise) instead of
        /// every matching page showing up as its own separate, easy-to-
        /// confuse-with-a-different-site result. Selecting a subpage
        /// navigates straight to it, same as the parent suggestion.
        var subpages: [Subpage] = []

        struct Subpage: Identifiable {
            let id = UUID()
            var label: String
            var snippet: String
            var path: String
        }
    }

    @Published private(set) var current: PageRef?
    @Published var addressText: String = ""
    @Published private(set) var content: String = BrowserState.welcomeContent
    /// Non-nil when the current page is being shown via Tux's real HTML
    /// renderer (main.py's /view/ route + micron.py — see fetchTuxHTML)
    /// instead of the native Micron parser. Only ever populated when
    /// Tux actually has the page; BrowserView switches to a WKWebView
    /// for this case and falls back to `content`/native MicronView for
    /// every other page, same as before this existed.
    @Published private(set) var htmlContent: String? = nil

    /// Which tier actually resolved the page currently on screen — nil
    /// while loading or on an error page. BrowserView shows this as a
    /// small color-coded badge (Theme.pageSourceTuxHTTP/TuxCache/Live)
    /// so it's obvious at a glance whether what's showing is Tux's real
    /// HTTP render, its Reticulum-cached .mu, or a genuine live fetch.
    @Published private(set) var pageSource: PageSource? = nil

    enum PageSource {
        case tuxHTTP
        case tuxCache
        case live
    }
    /// Live values for whatever `<...>` form fields the current page
    /// declares — reseeded fresh (see setContent) every time content
    /// changes, since a new page's fields have nothing to do with the
    /// last one's.
    @Published private(set) var formState = MicronFormState()
    @Published private(set) var isLoading: Bool = false
    /// Live, database-backed autocomplete — driven by Tux's own search
    /// index over Reticulum, not local text prediction. Kept as two
    /// separate published lists, not one shared list, even though both
    /// are fetched the same way: the native address bar and an on-page
    /// Micron search field can be visible at the same time (e.g. Mac's
    /// inline address field alongside the page content), and a single
    /// shared list meant typing in one showed a dropdown under *both* —
    /// a real bug caught by Bryan testing live.
    @Published private(set) var addressSuggestions: [Suggestion] = []
    @Published private(set) var pageSuggestions: [Suggestion] = []

    private var backStack: [PageRef] = []
    private var forwardStack: [PageRef] = []

    /// What actually rendered for a page this session, keyed by
    /// "hash:path" — goBack()/goForward() check this first so
    /// returning to an already-visited page is instant and shows
    /// exactly what was there before, instead of a fresh re-fetch that
    /// can legitimately land on a different tier than the first visit
    /// did (confirmed live, 2026-08-05: Tux's HTTP tier's tight 0.5s
    /// timeout — see fetchTuxHTML — missing on a retry where it
    /// succeeded moments earlier is normal network jitter, not a bug in
    /// itself, but showing a *different* render — the plain .mu
    /// fallback — for the exact same page on "back" reads as one).
    /// Fresh navigation (a link tap, the address bar) is unaffected —
    /// it always fetches live, same as before this existed.
    private struct CachedPage {
        let pageSource: PageSource
        let content: String
        let htmlContent: String?
    }
    private var sessionPageCache: [String: CachedPage] = [:]

    private func cacheKey(_ ref: PageRef) -> String {
        "\(ref.destinationHashHex):\(ref.path)"
    }

    /// Called right after each tier's success path finishes updating
    /// `content`/`htmlContent`/`pageSource` — never for the transient
    /// loading placeholder or an error page, so those never get cached
    /// as if they were real content.
    private func cachePage(for ref: PageRef) {
        guard let pageSource else { return }
        sessionPageCache[cacheKey(ref)] = CachedPage(pageSource: pageSource, content: content, htmlContent: htmlContent)
    }

    /// Restores a cached render in place, with no network activity at
    /// all — mirrors setContent/setHTMLContent's own effects exactly,
    /// just from the cache instead of a fresh fetch. Deliberately
    /// doesn't touch connectedDestinationHashHex/LinkManager bookkeeping
    /// the way loadPage does: nothing here opens a new connection, so
    /// there's nothing to tear down or reuse — if the page's own links
    /// need a live fetch later, that goes through the normal tiers then.
    @discardableResult
    private func restoreFromCache(_ ref: PageRef) -> Bool {

        guard let cached = sessionPageCache[cacheKey(ref)] else { return false }

        isLoading = false
        pageSource = cached.pageSource

        if let html = cached.htmlContent {
            htmlContent = html
            content = ""
            formState = MicronFormState()
        } else {
            htmlContent = nil
            content = cached.content
            formState = MicronFormState(document: MicronParser.parse(cached.content))
        }

        return true
    }

    /// Guards a suggestions fetch the same way loadToken guards a page
    /// fetch — a stale response (the user kept typing) must not clobber
    /// a newer one. One token per list, so an address-bar fetch and a
    /// page-search fetch in flight at the same time can't cancel each
    /// other out either.
    private var addressSuggestionsToken = UUID()
    private var pageSuggestionsToken = UUID()

    /// Which node we currently hold a Link open to — used to tear it
    /// down when navigating to a different node.
    private var connectedDestinationHashHex: String?

    /// Guards against a stale request's response clobbering a newer
    /// navigation's content if the user navigates again before the
    /// first fetch finishes.
    private var loadToken = UUID()

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }


    // MARK: - Navigation

    /// Shows Tux's index page instantly from StartupManager's preload
    /// (TuxPreloadStore) instead of a live fetch — no loading state to
    /// sit through, since the network round-trip already happened during
    /// the splash screen. `connectedDestinationHashHex` is set the same
    /// as a real connect() would: TuxPreloadStore fetched through
    /// LinkManager too, so that Link is very likely still alive and
    /// cached, ready for the next request (e.g. tapping Search) to reuse.
    func loadPreloadedHome(content: String) {

        let ref = PageRef(destinationHashHex: Self.tuxDestinationHashHex, path: "/page/index.mu")

        current = ref
        addressText = "\(ref.destinationHashHex):\(ref.path)"
        connectedDestinationHashHex = ref.destinationHashHex
        setContent(content)
    }


    /// HTML counterpart to loadPreloadedHome — shows Tux's real website
    /// homepage (TuxPreloadStore's parallel HTML fetch) instead of the
    /// native `.mu` reconstruction. Preferred whenever available — see
    /// TuxPreloadStore.htmlContent's doc comment. No
    /// connectedDestinationHashHex here (unlike the native version):
    /// this content came over plain HTTPS, not a Reticulum Link, so
    /// there's genuinely nothing to reuse or tear down later.
    func loadPreloadedHomeHTML(html: String) {

        let ref = PageRef(destinationHashHex: Self.tuxDestinationHashHex, path: "/page/index.mu")

        current = ref
        addressText = "\(ref.destinationHashHex):\(ref.path)"
        pageSource = .tuxHTTP
        setHTMLContent(html)
        cachePage(for: ref)
    }


    /// The Browser toolbar's Tux/house button's action — not the same
    /// as goHome() below (that returns to whatever *current node's*
    /// own home page is; this always means Tux specifically). Always
    /// attempts Tux's real website homepage fresh (not the possibly-
    /// stale startup preload), same tiered shape as loadPage but
    /// hardcoded to Tux's own homepage. Bryan's explicit call
    /// (2026-08-05): the app's homepage should always be "the full
    /// version," as good-looking as it can be, so this deliberately
    /// skips the "browsing Tux's own destination" carve-out loadPage
    /// uses elsewhere (that exists to avoid a redundant cached-copy-
    /// of-yourself hop while browsing Tux through Tux; there's no such
    /// redundancy here, this *is* the direct source). IS gated behind
    /// isUsingIceNomadPublicRelay, though — same as every other Tux-
    /// HTTP/cache tier (corrected 2026-08-05 after first shipping this
    /// ungated: HTTP-mode is a relay-specific feature here, not a
    /// general "try it whenever the internet happens to work"
    /// fallback). Off the relay, this behaves exactly like it always
    /// did before any of this existed — straight to a live fetch of
    /// Tux's own `/page/index.mu`.
    func goToTuxHomepage() {

        let ref = PageRef(destinationHashHex: Self.tuxDestinationHashHex, path: "/page/index.mu")

        let token = UUID()
        loadToken = token

        isLoading = true
        pageSource = nil
        current = ref
        addressText = "\(ref.destinationHashHex):\(ref.path)"
        setContent(BrowserState.loadingContent(for: ref))

        guard BrowserSettings.shared.preferCachedContent, InterfaceManager.shared.isUsingIceNomadPublicRelay else {
            loadDirectFromNode(ref, token: token)
            return
        }

        fetchTuxWebHomeHTML(token: token) { [weak self] html in

            guard let self, self.loadToken == token else { return }

            if let html {
                self.isLoading = false
                self.pageSource = .tuxHTTP
                self.setHTMLContent(html)
                self.cachePage(for: ref)
                return
            }

            self.fetchTuxCachedMu(for: ref, token: token) { [weak self] found in

                guard let self, self.loadToken == token, !found else { return }

                self.loadDirectFromNode(ref, token: token)
            }
        }
    }


    private func fetchTuxWebHomeHTML(token: UUID, completion: @escaping (String?) -> Void) {

        let request = URLRequest(url: Self.tuxWebBaseURL, timeoutInterval: 0.5)

        URLSession.shared.dataTask(with: request) { data, response, _ in

            DispatchQueue.main.async {

                guard let data, let html = String(data: data, encoding: .utf8),
                      let http = response as? HTTPURLResponse, http.statusCode == 200
                else {
                    completion(nil)
                    return
                }

                completion(html)
            }
        }.resume()
    }


    func connect(to destinationHashHex: String) {

        navigate(to: PageRef(destinationHashHex: destinationHashHex, path: "/page/index.mu"))
    }


    /// Retries the current page from scratch — tears down whatever link
    /// state exists (active, stuck mid-handshake, whatever) and starts a
    /// fresh connection attempt, rather than potentially waiting on an
    /// already-doomed pending handshake.
    func refresh() {

        guard let ref = current else { return }

        if let connectedDestinationHashHex {
            LinkManager.shared.disconnect(from: connectedDestinationHashHex)
        }

        loadPage(for: ref)
    }


    /// Cancels an in-flight page load without navigating anywhere — the
    /// underlying request may still complete on the wire, but its result
    /// is ignored (a fresh loadToken makes it stale) and the UI stops
    /// showing a loading state.
    func cancelLoad() {

        guard isLoading, let current else { return }

        loadToken = UUID()
        isLoading = false
        setContent(BrowserState.stoppedContent(for: current))
    }


    func goHome() {

        guard let hex = current?.destinationHashHex else { return }
        navigate(to: PageRef(destinationHashHex: hex, path: "/page/index.mu"))
    }


    func goBack() {

        guard let previous = backStack.popLast() else { return }

        if let current {
            forwardStack.append(current)
        }

        setCurrent(previous, preferCache: true)
    }


    func goForward() {

        guard let next = forwardStack.popLast() else { return }

        if let current {
            backStack.append(current)
        }

        setCurrent(next, preferCache: true)
    }


    func navigate(to ref: PageRef) {

        if let current {
            backStack.append(current)
        }

        forwardStack.removeAll()
        setCurrent(ref)
    }


    func followLink(_ link: MicronLink) {

        guard let currentHex = current?.destinationHashHex else { return }

        let hex = link.destinationHashHex ?? currentHex

        if link.isFormSubmit {
            submitForm(link, destinationHashHex: hex)
            return
        }

        navigate(to: PageRef(destinationHashHex: hex, path: link.path))
    }


    /// A form-submit link (real NomadNet's third link-target segment,
    /// e.g. `` `[Submit`/page/claim.mu`*]` ``) — sends the page's current
    /// field values along with the request instead of just navigating.
    /// Identifies to the remote node first (ReticulumLink.identify()):
    /// submitting a form already hands that node whatever the user typed
    /// into it, so proving cryptographic identity at the same moment is
    /// consistent with that, and it's exactly what a form like Tux's
    /// claim.mu needs to verify who's submitting — plain page navigation
    /// never triggers this, preserving the initiator anonymity a normal
    /// browse should have.
    private func submitForm(_ link: MicronLink, destinationHashHex hex: String) {

        let ref = PageRef(destinationHashHex: hex, path: link.path)
        let fieldNames = link.submitsAllFields ? nil : link.submittedFieldNames
        // Field values from live page controls, plus any literal var_
        // pairs baked into the link itself (real NomadNet's mechanism for
        // passing fixed parameters with a tap — e.g. a search result
        // link naming which crawled page to view — independent of
        // whether the page has any form fields at all).
        let payload = formState.fieldPayload(includingOnly: fieldNames)
            + link.submittedVarPairs.map { (MsgpackValue.string("var_" + $0.name), MsgpackValue.string($0.value)) }

        if let current {
            backStack.append(current)
        }
        forwardStack.removeAll()
        current = ref
        addressText = "\(ref.destinationHashHex):\(ref.path)"

        let token = UUID()
        loadToken = token

        isLoading = true
        setContent(BrowserState.loadingContent(for: ref))

        LinkManager.shared.connect(to: hex) { [weak self] connectResult in

            DispatchQueue.main.async {

                guard let self, self.loadToken == token else {
                    return
                }

                switch connectResult {

                case .failure(let error):
                    self.isLoading = false
                    self.setContent(BrowserState.errorContent(for: ref, reason: BrowserState.describe(error)))

                case .success(let reticulumLink):

                    reticulumLink.identify(as: IdentityStore.shared.myIdentity)

                    reticulumLink.request(path: ref.path, data: .map(payload)) { [weak self] requestResult in

                        DispatchQueue.main.async {

                            guard let self, self.loadToken == token else {
                                return
                            }

                            self.isLoading = false

                            switch requestResult {

                            case .success(let data):
                                self.setContent(String(data: data, encoding: .utf8) ?? BrowserState.binaryContent(byteCount: data.count))

                            case .failure(let error):
                                self.setContent(BrowserState.errorContent(for: ref, reason: BrowserState.describe(error)))
                            }
                        }
                    }
                }
            }
        }
    }


    /// Accepts either "hash:/path" (jump anywhere) or, if already on a
    /// node, a bare "/path" relative to that node.
    func navigateFromAddressBar() {

        let raw = addressText.trimmingCharacters(in: .whitespacesAndNewlines)

        if raw.contains(":") {

            guard let ref = PageRef.parse(raw) else { return }
            navigate(to: ref)

        } else if let hex = current?.destinationHashHex {

            navigate(to: PageRef(destinationHashHex: hex, path: raw.isEmpty ? "/page/index.mu" : raw))
        }
    }


    // MARK: - Autocomplete (Tux-backed)

    /// Live, database-backed suggestions for the native address bar —
    /// queries Tux's own search index over Reticulum (its `/suggest`
    /// request path), not local text prediction. Skips the round-trip
    /// entirely for text that already looks like a real "hash:/path"
    /// address, since that's direct navigation, not a search.
    func updateAddressSuggestions(for text: String) {
        fetchSuggestions(for: text, tokenKeyPath: \.addressSuggestionsToken) { [weak self] in self?.addressSuggestions = $0 }
    }


    func clearAddressSuggestions() {
        addressSuggestionsToken = UUID()
        addressSuggestions = []
    }


    /// Same live Tux-backed suggestions, for an on-page Micron search
    /// field instead of the address bar — kept as an entirely separate
    /// published list + token (see the doc comment on pageSuggestions)
    /// so the two dropdowns can never show each other's results.
    func updatePageSuggestions(for text: String) {
        fetchSuggestions(for: text, tokenKeyPath: \.pageSuggestionsToken) { [weak self] in self?.pageSuggestions = $0 }
    }


    func clearPageSuggestions() {
        pageSuggestionsToken = UUID()
        pageSuggestions = []
    }


    /// `tokenKeyPath` picks which of the two staleness tokens this fetch
    /// belongs to — a `ReferenceWritableKeyPath` rather than an `inout`
    /// parameter since the check has to happen inside an escaping
    /// completion closure, after this function has already returned.
    private func fetchSuggestions(for text: String, tokenKeyPath: ReferenceWritableKeyPath<BrowserState, UUID>, assign: @escaping ([Suggestion]) -> Void) {

        // Tux search is a relay-specific feature, same as the HTTP/
        // cache tiers — off the IceNomad Public Relay (or with the
        // Settings toggle off), the address bar just behaves like
        // plain "hash:/path" addressing, no live suggestions at all.
        guard BrowserSettings.shared.tuxSearchEnabled, InterfaceManager.shared.isUsingIceNomadPublicRelay else {
            self[keyPath: tokenKeyPath] = UUID()
            assign([])
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let looksLikeAddress = trimmed.firstIndex(of: ":").map { colonIndex in
            trimmed.distance(from: trimmed.startIndex, to: colonIndex) == 32
                && trimmed[trimmed.startIndex..<colonIndex].allSatisfy { $0.isHexDigit }
        } ?? false

        guard !looksLikeAddress, trimmed.count >= 2 else {
            self[keyPath: tokenKeyPath] = UUID()
            assign([])
            return
        }

        let token = UUID()
        self[keyPath: tokenKeyPath] = token

        LinkManager.shared.connect(to: Self.tuxDestinationHashHex) { [weak self] connectResult in

            guard case .success(let link) = connectResult else {
                return
            }

            let payload: [(MsgpackValue, MsgpackValue)] = [(.string("q"), .string(trimmed))]

            link.request(path: "/suggest", data: .map(payload)) { [weak self] requestResult in

                DispatchQueue.main.async {

                    guard let self, self[keyPath: tokenKeyPath] == token,
                          case .success(let data) = requestResult,
                          let decoded = try? MsgpackValue.decode(data),
                          case .array(let items) = decoded
                    else {
                        return
                    }

                    let suggestions: [Suggestion] = items.compactMap { item in

                        guard case .map(let pairs) = item else {
                            return nil
                        }

                        var fields: [String: String] = [:]
                        var subpagesValue: [MsgpackValue] = []

                        for (key, value) in pairs {
                            guard case .string(let keyString) = key else {
                                continue
                            }
                            if case .string(let valueString) = value {
                                fields[keyString] = valueString
                            } else if keyString == "subpages", case .array(let subpageItems) = value {
                                subpagesValue = subpageItems
                            }
                        }

                        guard let label = fields["label"], let node = fields["node"], let path = fields["path"] else {
                            return nil
                        }

                        let subpages: [Suggestion.Subpage] = subpagesValue.compactMap { subpageItem in

                            guard case .map(let subpagePairs) = subpageItem else {
                                return nil
                            }

                            var subpageFields: [String: String] = [:]
                            for (key, value) in subpagePairs {
                                guard case .string(let keyString) = key, case .string(let valueString) = value else {
                                    continue
                                }
                                subpageFields[keyString] = valueString
                            }

                            guard let subLabel = subpageFields["label"], let subPath = subpageFields["path"] else {
                                return nil
                            }

                            return Suggestion.Subpage(label: subLabel, snippet: subpageFields["snippet"] ?? "", path: subPath)
                        }

                        return Suggestion(label: label, snippet: fields["snippet"] ?? "", destinationHashHex: node, path: path, subpages: subpages)
                    }

                    assign(suggestions)
                }
            }
        }
    }


    /// Navigates straight to a tapped suggestion — it already carries the
    /// exact destination hash and path, so there's no reason to make the
    /// user hit Go again the way a plain typed address would need to.
    func selectSuggestion(_ suggestion: Suggestion) {
        clearAddressSuggestions()
        clearPageSuggestions()
        navigate(to: PageRef(destinationHashHex: suggestion.destinationHashHex, path: suggestion.path))
    }


    /// The only place `content` is ever assigned — reseeds `formState`
    /// from the newly-set page in the same step, so a stale page's field
    /// values (or worse, a stale text field silently carrying over onto
    /// an unrelated page) can never linger past a navigation.
    private func setContent(_ text: String) {
        content = text
        formState = MicronFormState(document: MicronParser.parse(text))
        htmlContent = nil
    }


    /// Counterpart to setContent for the Tux-HTML tier (see
    /// fetchTuxHTML) — no Micron parsing, no live form state, since the
    /// page is rendered as real HTML in a WKWebView instead.
    private func setHTMLContent(_ html: String) {
        htmlContent = html
        content = ""
        formState = MicronFormState()
    }


    private func setCurrent(_ ref: PageRef, preferCache: Bool = false) {

        current = ref
        addressText = "\(ref.destinationHashHex):\(ref.path)"

        if preferCache, restoreFromCache(ref) {
            return
        }

        loadPage(for: ref)
    }


    // MARK: - Fetching (real Link + Request/Response, over Resource for larger pages)

    /// Three tiers, in order: Tux's real HTTP-rendered page (real CSS,
    /// proper links/colors via main.py's /view/ route + micron.py —
    /// Bryan's own side-by-side comparison found this noticeably better
    /// looking than native Micron rendering for anything Tux has
    /// actually crawled, 2026-08-04); if Tux doesn't have it reachable
    /// over the open internet, its cached-.mu view over Reticulum (a
    /// real cached copy if Tux has crawled this page, or Tux fetching it
    /// live on the client's behalf if not — already built, previously
    /// only reached via search-result links, now also tried directly);
    /// if Tux doesn't know the page at all, fall back to genuine live
    /// NomadNet browsing — connecting straight to the target node, this
    /// app's original and default behavior.
    ///
    /// An AI-assisted "Reader" tier (Tux rewriting a page's prose for
    /// mobile via Ollama) was built and real-device-tested 2026-08-04,
    /// then removed after live testing found the model fabricating
    /// entire sentences with no relation to the source page — passed
    /// every guardrail added (URL/hash exclusion, protected-terms
    /// allowlist, preamble detection) because it wasn't wrong in any of
    /// *those* specific ways, just wholesale invented. See Roadmap &
    /// Ideas.md, "AI Reader Mode disabled..." for the full story — the
    /// real lesson was that a small model rewriting arbitrary open text
    /// doesn't converge to safe no matter how many narrow guardrails
    /// get added, and the fix isn't another guardrail. Ollama/the AI
    /// side of Tux is being reframed toward its original purpose
    /// instead — extraction, categorization, and search-ranking
    /// weight — not generating anything a user reads as page content.
    private func loadPage(for ref: PageRef) {

        if let connectedDestinationHashHex, connectedDestinationHashHex != ref.destinationHashHex,
           !DownloadManager.shared.isDownloading(from: connectedDestinationHashHex) {
            // A download in flight against the node we're leaving keeps
            // its Link alive — tearing it down here would kill a transfer
            // the user can no longer see but still expects to finish in
            // the background. The link is simply left open in that case;
            // it'll close on its own once the download completes and
            // something else navigates away from that node again.
            LinkManager.shared.disconnect(from: connectedDestinationHashHex)
            PeerStore.shared.unpin(connectedDestinationHashHex)
        }
        connectedDestinationHashHex = ref.destinationHashHex

        // Protect this peer from PeerStore's announce-count eviction for
        // as long as we're trying to reach it — a busy network can churn
        // through announces fast enough to evict it out from under a
        // slow handshake otherwise.
        PeerStore.shared.pin(ref.destinationHashHex)

        let token = UUID()
        loadToken = token

        isLoading = true
        pageSource = nil
        setContent(BrowserState.loadingContent(for: ref))

        // Tux's cached tiers only make sense to try when Tux is
        // actually reachable at all — otherwise this is a wasted
        // connect-then-timeout delay on *every* page load for anyone
        // not using the IceNomad Public Relay. TuxPreloadStore.content
        // being non-nil is the same signal StartupManager already uses
        // for "Tux is up." The relay check is the authoritative gate,
        // though — Bryan's explicit call: this whole system (both cache
        // tiers, and the fast fail-fast timeouts below) only applies
        // when actually connected through IceNomad's own relay; anyone
        // on a different relay/bridge goes straight to live, same as if
        // Tux were unreachable at all. Browsing Tux's own pages skips
        // straight to live too. A user can also force this
        // unconditionally via Settings > Browsing ("Prefer Cached
        // Pages" off) — checked first so it short-circuits before any
        // of the other checks.
        guard BrowserSettings.shared.preferCachedContent,
              InterfaceManager.shared.isUsingIceNomadPublicRelay,
              TuxPreloadStore.shared.content != nil, ref.destinationHashHex != Self.tuxDestinationHashHex else {
            loadDirectFromNode(ref, token: token)
            return
        }

        fetchTuxHTML(for: ref, token: token) { [weak self] html in

            guard let self, self.loadToken == token else { return }

            if let html {
                self.isLoading = false
                self.pageSource = .tuxHTTP
                self.setHTMLContent(html)
                self.cachePage(for: ref)
                return
            }

            self.fetchTuxCachedMu(for: ref, token: token) { [weak self] found in

                guard let self, self.loadToken == token, !found else { return }

                self.loadDirectFromNode(ref, token: token)
            }
        }
    }


    /// Tier 1: Tux's own public web face (tux.icenomad.net, real DNS +
    /// Let's Encrypt cert — see the Tux vault note's "publicly live"
    /// entry) rendering this exact page — a plain HTTPS GET, not a
    /// Reticulum round-trip. Half a second, not longer: a real page
    /// load can fall through up to three tiers now, and Bryan's ask was
    /// for the whole chain to resolve in about 5 seconds total on a
    /// bad/no connection, not stack each tier's own generous default on
    /// top of the others. Matches against the same two literal "not
    /// found" phrases main.py's view_page route uses for a node it's
    /// never heard of or couldn't reach live — same "good enough, it's
    /// Tux's own established convention" reasoning fetchTuxCachedMu
    /// below already relies on, just checked against the HTML body
    /// instead of raw .mu text.
    private func fetchTuxHTML(for ref: PageRef, token: UUID, completion: @escaping (String?) -> Void) {

        guard ref.path.hasPrefix("/page/"), let url = Self.tuxViewURL(for: ref) else {
            completion(nil)
            return
        }

        let request = URLRequest(url: url, timeoutInterval: 0.5)

        URLSession.shared.dataTask(with: request) { data, response, _ in

            DispatchQueue.main.async {

                guard let data, let html = String(data: data, encoding: .utf8),
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      !html.contains("Tux has never seen it announce"),
                      !html.contains("couldn't reach the node")
                else {
                    completion(nil)
                    return
                }

                completion(html)
            }
        }.resume()
    }


    /// Tux's real website — plain HTTPS, nothing to do with Reticulum.
    /// Not private: TuxPreloadStore's own startup HTML preload reuses
    /// this exact URL.
    static let tuxWebBaseURL = URL(string: "https://tux.icenomad.net")!

    /// `ref.path` is always "/page/<subpath>" (see PageRef.parse and
    /// every link normalizer that builds one) — main.py's /view/ route
    /// reconstructs that same "/page/" prefix internally, so the
    /// subpath handed to it here is exactly `path` with that prefix
    /// stripped back off.
    private static func tuxViewURL(for ref: PageRef) -> URL? {
        let subpath = String(ref.path.dropFirst("/page/".count))
        var components = URLComponents(url: tuxWebBaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/view/\(ref.destinationHashHex)/\(subpath)"
        return components?.url
    }


    /// Tier 2: Tux's existing cached-.mu view (/page/view.mu) — a real
    /// cached copy if Tux has already crawled this page, or Tux fetching
    /// it live on the client's behalf if not (see crawler.py's
    /// _serve_view, built earlier this project, previously only reached
    /// via search-result links). Matching against Tux's own "Not found"
    /// heading text isn't perfectly robust — a real page could in theory
    /// contain that exact phrase — but it's Tux's own established
    /// not-found convention, and good enough for this to fall through to
    /// tier 3 rather than show Tux's error page for a node it never knew.
    ///
    /// Budgeted at 2 seconds total (connect + request together, via
    /// withDeadline below) — a real Reticulum handshake plus request can
    /// legitimately take longer than that on a slow relay, but this tier
    /// exists purely as a fast convenience layer in front of tier 3
    /// (genuine live browsing, unbounded); it isn't the only way to
    /// reach the page.
    private func fetchTuxCachedMu(for ref: PageRef, token: UUID, completion: @escaping (Bool) -> Void) {

        withDeadline(2.0, attempt: { [weak self] finish in
            self?.attemptTuxCachedMu(for: ref, token: token, completion: finish)
        }, timeoutValue: false, completion: completion)
    }


    private func attemptTuxCachedMu(for ref: PageRef, token: UUID, completion: @escaping (Bool) -> Void) {

        LinkManager.shared.connect(to: Self.tuxDestinationHashHex) { [weak self] connectResult in

            guard case .success(let link) = connectResult else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let payload: [(MsgpackValue, MsgpackValue)] = [
                (.string("var_node"), .string(ref.destinationHashHex)),
                (.string("var_path"), .string(ref.path)),
            ]

            link.request(path: "/page/view.mu", data: .map(payload)) { [weak self] requestResult in

                DispatchQueue.main.async {

                    guard let self, self.loadToken == token,
                          case .success(let data) = requestResult,
                          let text = String(data: data, encoding: .utf8),
                          !text.contains(">Not found")
                    else {
                        completion(false)
                        return
                    }

                    self.isLoading = false
                    self.pageSource = .tuxCache
                    self.setContent(text)
                    self.cachePage(for: ref)
                    completion(true)
                }
            }
        }
    }


    /// Races `attempt` against a plain wall-clock deadline — if it
    /// hasn't called back by then, `completion` fires early with
    /// `timeoutValue`, and whatever `attempt` eventually returns later
    /// is silently dropped (the `didComplete` guard). Every call site
    /// here runs on the main queue already (loadPage itself, and every
    /// completion `attempt` can invoke — see their own doc comments),
    /// so this needs no locking despite the two competing completions.
    private func withDeadline<T>(
        _ seconds: TimeInterval,
        attempt: (@escaping (T) -> Void) -> Void,
        timeoutValue: T,
        completion: @escaping (T) -> Void
    ) {

        var didComplete = false

        func complete(_ value: T) {
            guard !didComplete else { return }
            didComplete = true
            completion(value)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            complete(timeoutValue)
        }

        attempt { value in
            complete(value)
        }
    }


    /// Tier 3: genuine live NomadNet browsing, connecting straight to
    /// the target node — unchanged from this app's original and only
    /// behavior before tonight.
    private func loadDirectFromNode(_ ref: PageRef, token: UUID) {

        LinkManager.shared.connect(to: ref.destinationHashHex) { [weak self] connectResult in

            // These completions arrive from wherever the underlying
            // transport's own receive callback runs — TCPClient starts
            // its NWConnection on DispatchQueue.global(), and that thread
            // choice propagates all the way up through ReticulumLink/
            // LinkManager unless something along the way explicitly hops
            // back to main. Mutating @Published state off the main thread
            // is undefined behavior for SwiftUI — it can appear to mostly
            // work on Mac Catalyst's more forgiving scheduling while
            // failing outright on real iOS hardware (confirmed: this was
            // exactly the split symptom — address-bar-adjacent fixes were
            // fine on Mac, this one wasn't, until this landed). Hopping
            // here guarantees correctness regardless of which thread the
            // callback actually arrives on, rather than trusting every
            // layer beneath this to already be on main.
            DispatchQueue.main.async {

                guard let self, self.loadToken == token else {
                    return
                }

                switch connectResult {

                case .failure(let error):
                    self.isLoading = false
                    self.setContent(BrowserState.errorContent(for: ref, reason: BrowserState.describe(error)))

                case .success(let link):

                    link.request(path: ref.path) { [weak self] requestResult in

                        DispatchQueue.main.async {

                            guard let self, self.loadToken == token else {
                                return
                            }

                            self.isLoading = false

                            switch requestResult {

                            case .success(let data):
                                self.pageSource = .live
                                self.setContent(String(data: data, encoding: .utf8) ?? BrowserState.binaryContent(byteCount: data.count))
                                self.cachePage(for: ref)

                            case .failure(let error):
                                self.setContent(BrowserState.errorContent(for: ref, reason: BrowserState.describe(error)))
                            }
                        }
                    }
                }
            }
        }
    }


    private static func describe(_ error: LinkManager.ConnectError) -> String {

        switch error {
        case .invalidHash: return "That's not a valid destination hash."
        case .unknownPeer: return "Haven't heard this node announce yet — open the node list and wait for it to appear, or make sure it's actually reachable."
        case .invalidPeerKey: return "This peer's identity key looks malformed."
        case .timeout: return "Link handshake timed out — the node may be offline or unreachable."
        }
    }


    private static func describe(_ error: ReticulumLink.LinkError) -> String {

        switch error {
        case .notActive: return "The connection to this node isn't active (it may have dropped, or the request timed out)."
        }
    }


    // MARK: - Content templates

    private static func loadingContent(for ref: PageRef) -> String {

        """
        >Loading…

        Fetching `!\(ref.path)`! from \(ref.destinationHashHex).
        """
    }


    private static func stoppedContent(for ref: PageRef) -> String {

        """
        >Stopped

        Loading `!\(ref.path)`! was stopped.

        `!Node:`! \(ref.destinationHashHex)
        """
    }


    private static func errorContent(for ref: PageRef, reason: String) -> String {

        """
        >Couldn't Load Page

        \(reason)

        `!Node:`! \(ref.destinationHashHex)
        `!Path:`! \(ref.path)
        """
    }


    private static func binaryContent(byteCount: Int) -> String {

        """
        >Binary Content

        This page returned \(byteCount) bytes that aren't valid text — likely a file, not a Micron page. File downloads aren't wired up yet.
        """
    }


    private static let welcomeContent = """
    >IceNomad Browser

    Open the node list on the left to connect to a NomadNet node.

    Once connected, `!Home`! will jump to that node's `_/page/index.mu`_, and links on the page will navigate normally.
    """
}
