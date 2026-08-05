//
//  TuxPreloadStore.swift
//  IceNomad
//
//  Holds Tux's homepage content fetched during app startup (see
//  StartupManager.runPreloadingTux), so the Browser tab's first load —
//  Tux is its home page — can show content instantly instead of a
//  network round-trip the user has to sit through. A plain singleton
//  rather than tied to BrowserState: StartupManager runs before any
//  BrowserView (and its per-instance BrowserState) exists.
//

import Foundation
import Combine

final class TuxPreloadStore: ObservableObject {

    static let shared = TuxPreloadStore()
    private init() {}

    /// The native `.mu` reconstruction, fetched over Reticulum — kept
    /// as a fallback for whenever the real website isn't reachable
    /// (mesh-only device, no internet route) but Tux itself still is.
    @Published private(set) var content: String?

    /// Tux's real website homepage (tux.icenomad.net/) — plain HTTPS,
    /// nothing to do with Reticulum at all. Preferred over `content`
    /// whenever both are available: Bryan's explicit call (2026-08-05)
    /// that the app's own homepage, its first impression, should
    /// always be "the full version," not the plainer native
    /// reconstruction, whenever it's reachable at all.
    @Published private(set) var htmlContent: String?

    @Published private(set) var failed = false

    private var isLoading = false

    /// Fetches both the native `.mu` and real HTML homepage in
    /// parallel and caches them. Safe to call more than once — a
    /// second call while already loading, or after a successful fetch,
    /// is a no-op.
    func preload(completion: (() -> Void)? = nil) {

        guard content == nil, htmlContent == nil, !isLoading else {
            completion?()
            return
        }

        isLoading = true

        let group = DispatchGroup()

        // Only attempt the real HTML homepage when actually connected
        // through IceNomad's own relay — same gate the per-page Tux-
        // HTTP/cache tiers already use (BrowserState.loadPage). This is
        // a relay-specific feature, not a general "try it whenever the
        // internet happens to work" fallback — Bryan's explicit
        // correction, 2026-08-05, after first building this ungated.
        // Anyone on a different relay or RNode-only just gets the
        // native `.mu` homepage below, exactly as before this existed.
        if InterfaceManager.shared.isUsingIceNomadPublicRelay {
            group.enter()
            fetchHTML { group.leave() }
        }

        group.enter()
        fetchNativeMu { group.leave() }

        group.notify(queue: .main) { [weak self] in
            guard let self else {
                completion?()
                return
            }
            self.isLoading = false
            self.failed = self.content == nil && self.htmlContent == nil
            completion?()
        }
    }


    /// Plain HTTPS GET, not a Reticulum round-trip — independent of
    /// whatever relay/interface is configured, same reasoning as
    /// BrowserState's own Tux-HTTP tier for individual pages.
    private func fetchHTML(completion: @escaping () -> Void) {

        let request = URLRequest(url: BrowserState.tuxWebBaseURL, timeoutInterval: 5)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in

            DispatchQueue.main.async {

                guard let self else {
                    completion()
                    return
                }

                if let data, let html = String(data: data, encoding: .utf8),
                   let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.htmlContent = html
                }

                completion()
            }
        }.resume()
    }


    private func fetchNativeMu(completion: @escaping () -> Void) {

        LinkManager.shared.connect(to: BrowserState.tuxDestinationHashHex) { [weak self] connectResult in

            DispatchQueue.main.async {

                guard let self else {
                    completion()
                    return
                }

                switch connectResult {

                case .failure:
                    completion()

                case .success(let link):

                    link.request(path: "/page/index.mu") { [weak self] requestResult in

                        DispatchQueue.main.async {

                            guard let self else {
                                completion()
                                return
                            }

                            if case .success(let data) = requestResult {
                                self.content = String(data: data, encoding: .utf8)
                            }

                            completion()
                        }
                    }
                }
            }
        }
    }
}
