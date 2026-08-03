//
//  BrowserSettings.swift
//  IceNomad
//
//  Persisted Browser-tab preferences: whether page loads prefer Tux's
//  cache before falling back to a live connection (see
//  BrowserState.loadPage), and an optional user-chosen homepage that
//  overrides the automatic default (Tux when the IceNomad Public Relay
//  preloaded it, the normal favorites/welcome screen otherwise).
//

import Foundation
import Combine

final class BrowserSettings: ObservableObject {

    static let shared = BrowserSettings()

    private let preferCachedContentKey = "browser_prefer_cached_content"
    private let customHomepageAddressKey = "browser_custom_homepage_address"

    /// When true (default — this app's existing behavior), page loads
    /// try Tux's cached .mu view first and fall back to a live
    /// connection only if Tux doesn't know the page. When false ("Live
    /// mode" in Settings), every navigation skips straight to a live
    /// connection, same as Tux being unreachable.
    @Published var preferCachedContent: Bool {
        didSet {
            UserDefaults.standard.set(preferCachedContent, forKey: preferCachedContentKey)
        }
    }

    /// Raw "hash:/path" text as the user typed it in Settings — nil
    /// means "automatic" (Tux via the Public Relay, else the default
    /// Browser screen). Kept as the raw string (not a parsed PageRef)
    /// so an invalid edit never silently reverts to automatic; use
    /// `customHomepage` to read the parsed, navigable value.
    @Published var customHomepageAddress: String? {
        didSet {
            UserDefaults.standard.set(customHomepageAddress, forKey: customHomepageAddressKey)
        }
    }

    private init() {

        preferCachedContent = UserDefaults.standard.object(forKey: preferCachedContentKey) as? Bool ?? true
        customHomepageAddress = UserDefaults.standard.string(forKey: customHomepageAddressKey)
    }


    var customHomepage: BrowserState.PageRef? {
        customHomepageAddress.flatMap { BrowserState.PageRef.parse($0) }
    }

    /// Returns false (leaving the stored value unchanged) if `raw` isn't
    /// a valid "hash:/path" address, so the Settings UI can show an
    /// error instead of persisting something `PageRef.parse` will just
    /// reject again next launch. Passing nil or an empty string always
    /// succeeds and clears back to automatic.
    @discardableResult
    func setCustomHomepage(_ raw: String?) -> Bool {

        guard let raw, !raw.isEmpty else {
            customHomepageAddress = nil
            return true
        }

        guard BrowserState.PageRef.parse(raw) != nil else { return false }

        customHomepageAddress = raw
        return true
    }
}
