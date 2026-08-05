//
//  TuxHTMLWebView.swift
//  IceNomad
//
//  Renders a page's real HTML as fetched from Tux's public web frontend
//  (see BrowserState.fetchTuxHTML) — Tux's own HTTP renderer (main.py's
//  /view/ route + micron.py) produces noticeably better-looking output
//  than this app's native Micron parser for anything it's actually
//  crawled (real CSS, proper link/color handling, none of the
//  terminal-grid constraints the native renderer works under). Only
//  ever shown when BrowserState.htmlContent is non-nil — every other
//  page still renders through the native MicronView path exactly as
//  before this existed.
//

import SwiftUI
import WebKit

struct TuxHTMLWebView: UIViewRepresentable {

    let html: String
    /// Same-node `/view/{hash}/{subpath}` links tapped inside the page
    /// get routed back through BrowserState's own navigation (address
    /// bar, back/forward history, and re-running the cache-vs-live
    /// decision for the new page) instead of navigating the WKWebView
    /// in place — keeps this consistent with how a tapped MicronLink
    /// already behaves in the native renderer. Anything else on the
    /// page (Tux's own search box, category browsing, a claim-name
    /// link, external http/https links) is left to navigate normally —
    /// still real Tux browsing, just not tracked as one of this app's
    /// own PageRefs.
    var onNavigateToPage: (BrowserState.PageRef) -> Void

    /// Only set for the one TuxHTMLWebView instance showing the app's
    /// own homepage — enables a hidden gate to Tux's admin dashboard:
    /// tap the hero logo 7 times, same "tap the build number" pattern
    /// as iOS's own hidden developer menu. Purely a discoverability
    /// gate against stray taps, not the actual security boundary —
    /// /admin is still gated server-side by Tux's own HTTP Basic Auth
    /// (see TuxAdminWebView), same as browsing there directly always
    /// was. Bryan's explicit ask, 2026-08-05.
    var onAdminGateTriggered: (() -> Void)? = nil

    static let baseURL = URL(string: "https://tux.icenomad.net")!

    /// Counts clicks on #tux-hero-logo (main.py's HOME_BODY), resetting
    /// if more than 1.5s passes between taps so this can only ever fire
    /// from a deliberate rapid sequence, not idle stray taps over time.
    /// No-ops harmlessly on any page that doesn't have that element.
    private static let adminGateJS = """
    (function() {
        var logo = document.getElementById('tux-hero-logo');
        if (!logo) { return; }
        var count = 0;
        var lastTap = 0;
        logo.addEventListener('click', function() {
            var now = Date.now();
            if (now - lastTap > 1500) { count = 0; }
            lastTap = now;
            count += 1;
            if (count >= 7) {
                count = 0;
                window.webkit.messageHandlers.tuxAdminGate.postMessage('open');
            }
        });
    })();
    """

    func makeUIView(context: Context) -> WKWebView {

        let configuration = WKWebViewConfiguration()

        if onAdminGateTriggered != nil {
            let script = WKUserScript(source: Self.adminGateJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(script)
            configuration.userContentController.add(context.coordinator, name: "tuxAdminGate")
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {

        // loadHTMLString on every SwiftUI update pass (not just when the
        // content actually changed) would fight the user's own in-page
        // navigation the instant they tap a same-origin Tux link that
        // isn't routed back through onNavigateToPage.
        guard context.coordinator.lastLoadedHTML != html else { return }
        context.coordinator.lastLoadedHTML = html
        webView.loadHTMLString(html, baseURL: Self.baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigateToPage: onNavigateToPage, onAdminGateTriggered: onAdminGateTriggered)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

        var lastLoadedHTML: String?
        let onNavigateToPage: (BrowserState.PageRef) -> Void
        let onAdminGateTriggered: (() -> Void)?

        init(onNavigateToPage: @escaping (BrowserState.PageRef) -> Void, onAdminGateTriggered: (() -> Void)?) {
            self.onNavigateToPage = onNavigateToPage
            self.onAdminGateTriggered = onAdminGateTriggered
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {

            guard message.name == "tuxAdminGate" else { return }
            onAdminGateTriggered?()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {

            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            if url.host == TuxHTMLWebView.baseURL.host,
               url.pathComponents.count >= 3,
               url.pathComponents[1] == "view" {

                let hash = url.pathComponents[2]
                let subpath = url.pathComponents.dropFirst(3).joined(separator: "/")
                onNavigateToPage(BrowserState.PageRef(destinationHashHex: hash, path: "/page/\(subpath)"))
                decisionHandler(.cancel)
                return
            }

            if let scheme = url.scheme, scheme == "http" || scheme == "https",
               url.host != TuxHTMLWebView.baseURL.host {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
