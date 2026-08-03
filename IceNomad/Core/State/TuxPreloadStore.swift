//
//  TuxPreloadStore.swift
//  IceNomad
//
//  Holds Tux's index page fetched during app startup (see
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

    @Published private(set) var content: String?
    @Published private(set) var failed = false

    private var isLoading = false

    /// Fetches Tux's index page once and caches it. Safe to call more
    /// than once — a second call while already loading, or after a
    /// successful fetch, is a no-op.
    func preload(completion: (() -> Void)? = nil) {

        guard content == nil, !isLoading else {
            completion?()
            return
        }

        isLoading = true

        LinkManager.shared.connect(to: BrowserState.tuxDestinationHashHex) { [weak self] connectResult in

            DispatchQueue.main.async {

                guard let self else {
                    completion?()
                    return
                }

                switch connectResult {

                case .failure:
                    self.isLoading = false
                    self.failed = true
                    completion?()

                case .success(let link):

                    link.request(path: "/page/index.mu") { [weak self] requestResult in

                        DispatchQueue.main.async {

                            guard let self else {
                                completion?()
                                return
                            }

                            self.isLoading = false

                            switch requestResult {

                            case .success(let data):
                                self.content = String(data: data, encoding: .utf8)
                                self.failed = self.content == nil

                            case .failure:
                                self.failed = true
                            }

                            completion?()
                        }
                    }
                }
            }
        }
    }
}
