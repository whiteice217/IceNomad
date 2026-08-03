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
    }

    @Published private(set) var current: PageRef?
    @Published var addressText: String = ""
    @Published private(set) var content: String = BrowserState.welcomeContent
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

        setCurrent(previous)
    }


    func goForward() {

        guard let next = forwardStack.popLast() else { return }

        if let current {
            backStack.append(current)
        }

        setCurrent(next)
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

        if let colonIndex = raw.firstIndex(of: ":") {

            let hash = String(raw[raw.startIndex..<colonIndex]).lowercased()
            let path = String(raw[raw.index(after: colonIndex)...])

            guard hash.count == 32, hash.allSatisfy({ $0.isHexDigit }) else {
                return
            }

            navigate(to: PageRef(destinationHashHex: hash, path: path.isEmpty ? "/page/index.mu" : path))

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
                        for (key, value) in pairs {
                            guard case .string(let keyString) = key, case .string(let valueString) = value else {
                                continue
                            }
                            fields[keyString] = valueString
                        }

                        guard let label = fields["label"], let node = fields["node"], let path = fields["path"] else {
                            return nil
                        }

                        return Suggestion(label: label, snippet: fields["snippet"] ?? "", destinationHashHex: node, path: path)
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
    }


    private func setCurrent(_ ref: PageRef) {

        current = ref
        addressText = "\(ref.destinationHashHex):\(ref.path)"
        loadPage(for: ref)
    }


    // MARK: - Fetching (real Link + Request/Response, over Resource for larger pages)

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
        setContent(BrowserState.loadingContent(for: ref))

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
