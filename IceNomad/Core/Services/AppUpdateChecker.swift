//
//  AppUpdateChecker.swift
//  IceNomad
//
//  Checks GitHub's own Releases API for a newer tagged version than
//  what's actually running -- IceNomad's real distribution channel
//  (see README's Download section) is GitHub Releases, not the App
//  Store, so there's no built-in update mechanism to piggyback on;
//  this is that mechanism. One check per app launch (see ContentView's
//  onAppear), not polled continuously -- an update landing a few hours
//  later than it could have is a fine tradeoff for not hammering
//  GitHub's API on every foreground. A manual "Check for Updates" in
//  Settings uses the same call.
//

import Foundation
import Combine

final class AppUpdateChecker: ObservableObject {

    static let shared = AppUpdateChecker()
    private init() {}

    struct UpdateInfo {
        let version: String
        let notes: String
        let releaseURL: URL
    }

    @Published private(set) var availableUpdate: UpdateInfo?

    private let dismissedVersionKey = "app_update_dismissed_version"
    private static let releasesURL = URL(string: "https://api.github.com/repos/whiteice217/IceNomad/releases/latest")!

    /// The version actually running -- CFBundleShortVersionString, the
    /// same "1.0"-style marketing version Xcode's own Info.plist
    /// already tracks (MARKETING_VERSION in the project settings), kept
    /// in sync with the git tag at release time as part of the release
    /// process, not enforced by this code.
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// `completion` reports whether a genuinely new, not-yet-dismissed
    /// update was found -- the manual "Check for Updates" button in
    /// Settings uses this to show "You're up to date" when it wasn't,
    /// instead of silently doing nothing either way.
    func checkForUpdate(completion: ((Bool) -> Void)? = nil) {

        var request = URLRequest(url: Self.releasesURL, timeoutInterval: 8)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in

            DispatchQueue.main.async {

                guard let self, let data,
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlURLString = json["html_url"] as? String,
                      let releaseURL = URL(string: htmlURLString)
                else {
                    completion?(false)
                    return
                }

                let remoteVersion = Self.stripLeadingV(tagName)

                guard Self.isNewer(remoteVersion, than: self.currentVersion) else {
                    completion?(false)
                    return
                }

                // Already explicitly acknowledged this exact version --
                // don't nag again until the *next* release ships.
                guard UserDefaults.standard.string(forKey: self.dismissedVersionKey) != remoteVersion else {
                    completion?(false)
                    return
                }

                let rawNotes = (json["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.availableUpdate = UpdateInfo(
                    version: remoteVersion,
                    notes: (rawNotes?.isEmpty == false) ? rawNotes! : "No release notes provided.",
                    releaseURL: releaseURL
                )
                completion?(true)
            }
        }.resume()
    }


    /// The popup's checkbox + Continue -- suppresses *this exact*
    /// version's prompt for good, but a future release still prompts
    /// normally. Bryan's spec: checking the box is how the user accepts
    /// that some features may not match this version's release notes
    /// on their now-behind build, in exchange for continuing to use it
    /// as-is.
    func acknowledge() {
        guard let availableUpdate else { return }
        UserDefaults.standard.set(availableUpdate.version, forKey: dismissedVersionKey)
        self.availableUpdate = nil
    }

    /// A plain close, no checkbox involved -- just hides it for the
    /// rest of this launch; it prompts again next time the app opens.
    func dismissForNow() {
        availableUpdate = nil
    }


    private static func stripLeadingV(_ s: String) -> String {
        (s.hasPrefix("v") || s.hasPrefix("V")) ? String(s.dropFirst()) : s
    }

    /// Plain numeric-component comparison ("1.2" vs "1.10" correctly
    /// treats 10 > 2, unlike a naive string compare). A tag that isn't
    /// numeric at all (e.g. this repo's own pre-existing "mac-test-
    /// build" release, confirmed live) parses to an empty component
    /// list and safely never counts as newer -- no false-positive
    /// prompt from a differently-named release.
    private static func isNewer(_ remote: String, than local: String) -> Bool {

        func components(_ s: String) -> [Int] {
            s.split(separator: ".").compactMap { Int($0) }
        }

        let r = components(remote)
        let l = components(local)
        let count = max(r.count, l.count)

        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
