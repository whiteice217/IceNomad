//
//  UserProfile.swift
//  IceNomad
//
//  Your own display name — sent as app_data in your announces, so
//  other peers see something better than a bare hash.
//

import Foundation
import Combine

final class UserProfile: ObservableObject {

    static let shared = UserProfile()

    private let key = "user_display_name"
    private let lastAnnouncedKey = "user_display_name_last_announced"

    @Published var displayName: String {
        didSet {
            UserDefaults.standard.set(displayName, forKey: key)
        }
    }

    /// Whatever name was actually in the most recent outgoing announce —
    /// distinct from `displayName` itself, which can be edited at any
    /// time without anyone else on the network finding out until the
    /// next announce actually goes out. Lets Settings show a "you
    /// changed this, go announce" cue instead of silently doing nothing.
    @Published private(set) var lastAnnouncedDisplayName: String?

    var hasUnannouncedNameChange: Bool {
        displayName != lastAnnouncedDisplayName
    }

    private init() {
        displayName = UserDefaults.standard.string(forKey: key) ?? "Anonymous Nomad"
        lastAnnouncedDisplayName = UserDefaults.standard.string(forKey: lastAnnouncedKey)
    }

    func markAnnounced() {
        lastAnnouncedDisplayName = displayName
        UserDefaults.standard.set(displayName, forKey: lastAnnouncedKey)
    }
}
