//
//  BrowserState.swift
//  IceNomad
//
//  Navigation state for the browser: current page, back/forward
//  history, and the address bar. Page CONTENT is a placeholder right
//  now — actually fetching a page needs an established Link, which
//  needs the crypto layer. Navigation, history, and rendering all
//  work for real already; this will show genuine node content the
//  moment fetching is wired up, with no changes needed here.
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

    private var backStack: [PageRef] = []
    private var forwardStack: [PageRef] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }


    // MARK: - Navigation

    func connect(to destinationHashHex: String) {

        navigate(to: PageRef(destinationHashHex: destinationHashHex, path: "/page/index.mu"))
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
        loadPlaceholderContent(for: ref)
    }


    // MARK: - Content (placeholder until Links exist)

    private func loadPlaceholderContent(for ref: PageRef) {

        content = """
        >Not Connected Yet

        This is placeholder content standing in for:

        `!Node:`! \(ref.destinationHashHex)
        `!Path:`! \(ref.path)

        Fetching the real page needs an established Link to this node, which needs the crypto layer (Ed25519 / X25519) to exist first. Navigation, history, and back/forward all work already — this will show the node's actual page the moment fetching is wired up.
        """
    }


    private static let welcomeContent = """
    >IceNomad Browser

    Open the node list on the left to connect to a NomadNet node.

    Once connected, `!Home`! will jump to that node's `_/page/index.mu`_, and links on the page will navigate normally.
    """
}
