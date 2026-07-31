//
//  NotificationBannerCenter.swift
//  IceNomad
//
//  A themed in-app "new message" toast — the reliable alternative to
//  recoloring/pulsing the Messages tab icon, which isn't achievable
//  through the public TabView `.badge()` API (see Known Issues). This
//  is fully SwiftUI-owned, so it can use theme colors and animate
//  freely, and it actively draws the eye at the moment a message
//  arrives instead of requiring you to notice a static tab indicator.
//

import Foundation
import Combine

struct IncomingMessageBanner: Identifiable, Equatable {

    let id = UUID()
    let peerHashHex: String
    let text: String
}


final class NotificationBannerCenter: ObservableObject {

    static let shared = NotificationBannerCenter()

    private init() {}

    @Published private(set) var current: IncomingMessageBanner?

    private var dismissTask: Task<Void, Never>?

    func show(peerHashHex: String, text: String) {

        dismissTask?.cancel()
        current = IncomingMessageBanner(peerHashHex: peerHashHex, text: text)

        dismissTask = Task { @MainActor in

            try? await Task.sleep(nanoseconds: 4_000_000_000)

            guard !Task.isCancelled else {
                return
            }

            self.current = nil
        }
    }

    func dismiss() {

        dismissTask?.cancel()
        current = nil
    }
}
