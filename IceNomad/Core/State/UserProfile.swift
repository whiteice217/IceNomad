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

    @Published var displayName: String {
        didSet {
            UserDefaults.standard.set(displayName, forKey: key)
        }
    }

    private init() {
        displayName = UserDefaults.standard.string(forKey: key) ?? "Anonymous Nomad"
    }
}
