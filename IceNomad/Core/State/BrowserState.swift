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

    @Published private(set) var current: PageRef?
    @Published var addressText: String = ""
    @Published private(set) var content: String = BrowserState.welcomeContent
    @Published private(set) var isLoading: Bool = false

    private var backStack: [PageRef] = []
    private var forwardStack: [PageRef] = []

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
        navigate(to: PageRef(destinationHashHex: hex, path: link.path))
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


    private func setCurrent(_ ref: PageRef) {

        current = ref
        addressText = "\(ref.destinationHashHex):\(ref.path)"
        loadPage(for: ref)
    }


    // MARK: - Fetching (real Link + Request/Response, over Resource for larger pages)

    private func loadPage(for ref: PageRef) {

        if let connectedDestinationHashHex, connectedDestinationHashHex != ref.destinationHashHex {
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
        content = BrowserState.loadingContent(for: ref)

        LinkManager.shared.connect(to: ref.destinationHashHex) { [weak self] connectResult in

            guard let self, self.loadToken == token else {
                return
            }

            switch connectResult {

            case .failure(let error):
                self.isLoading = false
                self.content = BrowserState.errorContent(for: ref, reason: BrowserState.describe(error))

            case .success(let link):

                link.request(path: ref.path) { [weak self] requestResult in

                    guard let self, self.loadToken == token else {
                        return
                    }

                    self.isLoading = false

                    switch requestResult {

                    case .success(let data):
                        self.content = String(data: data, encoding: .utf8) ?? BrowserState.binaryContent(byteCount: data.count)

                    case .failure(let error):
                        self.content = BrowserState.errorContent(for: ref, reason: BrowserState.describe(error))
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
