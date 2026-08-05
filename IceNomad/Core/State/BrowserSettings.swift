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
    private let tuxSearchEnabledKey = "browser_tux_search_enabled"
    private let customHomepageAddressKey = "browser_custom_homepage_address"

    /// When true (default — this app's existing behavior), page loads
    /// try Tux's cached .mu view first and fall back to a live
    /// connection only if Tux doesn't know the page. When false ("Live
    /// mode" in Settings), every navigation skips straight to a live
    /// connection, same as Tux being unreachable. Both this and
    /// tuxSearchEnabled below are additionally gated behind actually
    /// being connected through the IceNomad Public Relay
    /// (InterfaceManager.isUsingIceNomadPublicRelay) — this toggle only
    /// controls the preference *within* that; someone on a different
    /// relay can't get Tux's cache back just by leaving this on.
    @Published var preferCachedContent: Bool {
        didSet {
            UserDefaults.standard.set(preferCachedContent, forKey: preferCachedContentKey)
        }
    }

    /// Live, Tux-backed address-bar/on-page search suggestions —
    /// default on, same relay-gating caveat as preferCachedContent
    /// above. Off the IceNomad Public Relay, the address bar always
    /// behaves like plain "hash:/path" addressing regardless of this.
    @Published var tuxSearchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(tuxSearchEnabled, forKey: tuxSearchEnabledKey)
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
        tuxSearchEnabled = UserDefaults.standard.object(forKey: tuxSearchEnabledKey) as? Bool ?? true
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
