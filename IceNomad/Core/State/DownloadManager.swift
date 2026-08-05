//
//  DownloadManager.swift
//  IceNomad
//
//  Real file downloads over NomadNet's /file/ convention — same Link +
//  Request/Response/Resource machinery already used for page fetching
//  (see LinkManager/ReticulumLink), just routed to disk instead of the
//  Micron renderer. Runs independently of whatever the Browser is
//  currently showing, so navigating away doesn't interrupt an in-flight
//  download (see BrowserState.loadPage's activeDownloadDestinations check).
//
//  Flow is "ask where to save, then fetch" — not "fetch, then ask." A
//  tapped /file/ link immediately offers the system save picker for an
//  empty placeholder; only once the user actually picks (or creates) a
//  destination does the real network request start, writing the fetched
//  bytes straight to that already-chosen location. This avoids pulling
//  data over the mesh only to throw it away if the save dialog gets
//  cancelled, and matches a real "Save As" flow instead of "download
//  blind, then ask where it should have gone."
//

import Foundation
import Combine
import os

struct DownloadItem: Identifiable {

    let id: UUID = UUID()
    let destinationHashHex: String
    let path: String
    var filename: String
    var progress: Double
    /// True from the moment a link is tapped until the user actually
    /// picks (or creates) a save location — no network activity happens
    /// yet during this window, purely UI state so DownloadsView can show
    /// "Choose Save Location…" instead of an empty progress bar.
    var awaitingDestination: Bool = true
    var failed: Bool = false
    var cancelled: Bool = false

    var isComplete: Bool { progress >= 1.0 && !failed && !cancelled }
    var isActive: Bool { !isComplete && !failed && !cancelled }
}


/// A newly-tapped download's save-location prompt — presented via the
/// system document picker (see DocumentExporterView) *before* any
/// network fetch happens. `placeholderURL` is an empty (0-byte) temp
/// file offered purely so `UIDocumentPickerViewController`'s export flow
/// has something to place — the real content gets written to wherever
/// the user chooses once the actual download completes.
struct PendingExport: Identifiable {
    let id: UUID
    let placeholderURL: URL
}


final class DownloadManager: ObservableObject {

    static let shared = DownloadManager()

    private init() {}


    @Published private(set) var downloads: [DownloadItem] = []
    @Published var pendingExport: PendingExport?

    /// Destinations with a download currently in flight — checked by
    /// BrowserState before tearing down a Link on navigation, so browsing
    /// to a different node mid-download doesn't kill the transfer. Only
    /// populated once a save location has actually been picked and the
    /// real fetch has started (see destinationPicked) — nothing is
    /// "in flight" while a save dialog is still up.
    private var activeDownloadDestinations: Set<String> = []

    /// Security-scoped bookmarks for downloads that have a save location
    /// but haven't finished fetching yet — a bookmark, not a held-open
    /// URL, matching the exact pattern NotificationSettings already uses
    /// for its own security-scoped custom-sound file (bookmark
    /// immediately, resolve fresh + start/stop accessing only at the
    /// moment of actual use). Keeping startAccessingSecurityScopedResource
    /// open across an entire network fetch (which can run for many
    /// seconds) isn't a documented-safe pattern — confirmed live: doing
    /// so produced a write that silently succeeded on disk (the file
    /// really did land correctly) while still throwing on the write call
    /// itself, reported as "Failed" despite the download actually working.
    private var destinationBookmarks: [UUID: Data] = [:]

    func isDownloading(from destinationHashHex: String) -> Bool {
        activeDownloadDestinations.contains(destinationHashHex.lowercased())
    }


    /// Progress of the most recent in-flight download, for the toolbar
    /// button's ring. Nil when nothing is currently downloading.
    var activeProgress: Double? {

        downloads.last(where: { !$0.isComplete && !$0.failed })?.progress
    }


    /// Step 1 of 3 — a /file/ link was tapped. Offers the save picker
    /// immediately, before touching the network at all.
    func download(path: String, from destinationHashHex: String) {

        let hex = destinationHashHex.lowercased()
        let filename = suggestedFilename(from: path)

        let item = DownloadItem(destinationHashHex: hex, path: path, filename: filename, progress: 0)
        let id = item.id

        downloads.append(item)

        // Protect this node's Link from BrowserState tearing it down from
        // the moment the link is tapped, not just once a destination is
        // picked — a real bug found live: the save-location picker is a
        // modal the user can sit on for a while, and the exact same Link
        // BrowserState is using to show the current page can go inactive
        // during that window with nothing yet marking it protected,
        // producing a genuine "notActive" failure on the eventual
        // request even though connect() had just reported success.
        activeDownloadDestinations.insert(hex)

        let placeholderURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: placeholderURL.path) {
            try? FileManager.default.removeItem(at: placeholderURL)
        }

        guard FileManager.default.createFile(atPath: placeholderURL.path, contents: Data()) else {
            markFailed(id, destination: hex)
            return
        }

        pendingExport = PendingExport(id: id, placeholderURL: placeholderURL)
    }


    /// Step 2 of 3 — the user picked (or created) a save location. Bookmarks
    /// it (see destinationBookmarks' doc comment for why a bookmark, not a
    /// held-open URL) and starts the real network request. Called from
    /// ContentView's DocumentExporterView once the picker returns.
    func destinationPicked(id: UUID, url: URL) {

        pendingExport = nil

        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }

        let hex = downloads[index].destinationHashHex
        let path = downloads[index].path
        let filename = downloads[index].filename

        cleanUpPlaceholder(filename: filename)

        guard url.startAccessingSecurityScopedResource() else {
            Log.download.error("startAccessingSecurityScopedResource failed for picked destination \(url.path, privacy: .public)")
            markFailed(id, destination: hex)
            return
        }

        let bookmark: Data
        do {
            bookmark = try url.bookmarkData()
        } catch {
            Log.download.error("bookmarkData() failed for \(url.path, privacy: .public): \(error, privacy: .public)")
            url.stopAccessingSecurityScopedResource()
            markFailed(id, destination: hex)
            return
        }
        url.stopAccessingSecurityScopedResource()

        destinationBookmarks[id] = bookmark
        downloads[index].awaitingDestination = false

        LinkManager.shared.connect(to: hex) { [weak self] connectResult in

            // LinkManager/ReticulumLink completions can arrive off-main
            // (whatever thread the transport uses) — mutating @Published
            // state without hopping to main first is undefined for
            // SwiftUI, same real bug class already found and fixed in
            // BrowserState's own connect completions.
            DispatchQueue.main.async {

                guard let self else { return }

                switch connectResult {

                case .failure(let connectError):
                    Log.download.error("LinkManager.connect failed for \(hex, privacy: .public): \(String(describing: connectError), privacy: .public)")
                    self.markFailed(id, destination: hex)

                case .success(let link):
                    self.beginRequest(id: id, path: path, destination: hex, link: link)
                }
            }
        }
    }


    /// The user dismissed the save dialog without picking anywhere —
    /// nothing was ever fetched, so just drop the pending item rather
    /// than leaving a dead "awaiting destination" entry in the list.
    func destinationPickCancelled(id: UUID) {

        pendingExport = nil

        if let item = downloads.first(where: { $0.id == id }) {
            activeDownloadDestinations.remove(item.destinationHashHex)
        }

        let filename = downloads.first(where: { $0.id == id })?.filename
        downloads.removeAll { $0.id == id }

        if let filename {
            cleanUpPlaceholder(filename: filename)
        }
    }


    private func cleanUpPlaceholder(filename: String) {

        let placeholderURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: placeholderURL)
    }


    /// Step 3 of 3 — the real fetch, now that a destination exists.
    /// `alreadyRetried` guards a single retry-once: LinkManager can hand
    /// back a cached Link that reports .active at the instant of the
    /// connect() check but has since gone inactive by the time the
    /// request actually fires (confirmed live — a real "notActive"
    /// failure on a link connect() had just reported success for,
    /// most likely the same Link BrowserState is using for the current
    /// page going idle/closing during however long the save-location
    /// picker was left open). A fresh connect() call correctly falls
    /// through past a no-longer-active cached entry to establish a real
    /// new Link, so retrying once self-heals this rather than failing a
    /// download that's otherwise perfectly reachable.
    private func beginRequest(id: UUID, path: String, destination hex: String, link: ReticulumLink, alreadyRetried: Bool = false) {

        link.request(
            path: path,
            onProgress: { [weak self] progress in

                DispatchQueue.main.async {
                    self?.updateProgress(id, progress: progress)
                }
            },
            completion: { [weak self] requestResult in

                DispatchQueue.main.async {

                    guard let self else { return }

                    switch requestResult {

                    case .success(let data):
                        self.finish(id, data: data, destination: hex)

                    case .failure(let linkError):

                        if case .notActive = linkError, !alreadyRetried {

                            Log.download.error("link \(hex, privacy: .public) went inactive before request could send — retrying with a fresh connect")

                            LinkManager.shared.connect(to: hex) { [weak self] retryResult in

                                DispatchQueue.main.async {

                                    guard let self else { return }

                                    switch retryResult {

                                    case .failure(let connectError):
                                        Log.download.error("retry connect failed for \(hex, privacy: .public): \(String(describing: connectError), privacy: .public)")
                                        self.markFailed(id, destination: hex)

                                    case .success(let freshLink):
                                        self.beginRequest(id: id, path: path, destination: hex, link: freshLink, alreadyRetried: true)
                                    }
                                }
                            }
                            return
                        }

                        Log.download.error("link.request(path: \(path, privacy: .public)) failed against \(hex, privacy: .public): \(String(describing: linkError), privacy: .public)")
                        self.markFailed(id, destination: hex)
                    }
                }
            }
        )
    }


    /// Stops an in-flight download. Tears down the underlying Link so the
    /// transfer actually stops consuming bandwidth (not just hiding it in
    /// the UI) — same teardown `BrowserState.refresh()` already does when
    /// abandoning a page load. Any progress/completion callback that
    /// still lands after this (bytes already in flight when the Link
    /// closed) is ignored — see the `cancelled` guards below — so it
    /// can't silently resurrect a cancelled item as complete/failed.
    func cancel(_ id: UUID) {

        guard let index = downloads.firstIndex(where: { $0.id == id }), downloads[index].isActive else {
            return
        }

        let hex = downloads[index].destinationHashHex

        downloads[index].cancelled = true
        activeDownloadDestinations.remove(hex)

        if pendingExport?.id == id {
            pendingExport = nil
        }

        destinationBookmarks.removeValue(forKey: id)

        LinkManager.shared.disconnect(from: hex)
    }


    /// Removes every finished (complete/failed/cancelled) entry — active
    /// downloads are left alone, same as a normal browser's download list
    /// only clearing what's actually done.
    func clearFinished() {

        downloads.removeAll { !$0.isActive }
    }


    private func suggestedFilename(from path: String) -> String {

        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "download" : name
    }


    private func updateProgress(_ id: UUID, progress: Double) {

        guard let index = downloads.firstIndex(where: { $0.id == id }), !downloads[index].cancelled else {
            return
        }

        downloads[index].progress = progress
    }


    private func markFailed(_ id: UUID, destination: String) {

        activeDownloadDestinations.remove(destination)
        destinationBookmarks.removeValue(forKey: id)

        guard let index = downloads.firstIndex(where: { $0.id == id }), !downloads[index].cancelled else {
            return
        }

        downloads[index].failed = true
    }


    private func finish(_ id: UUID, data: Data, destination: String) {

        activeDownloadDestinations.remove(destination)

        let bookmark = destinationBookmarks.removeValue(forKey: id)

        guard let index = downloads.firstIndex(where: { $0.id == id }), !downloads[index].cancelled else {
            return
        }

        guard let bookmark else {
            Log.download.error("finish() called for \(id) with no stored bookmark")
            downloads[index].failed = true
            return
        }

        var isStale = false
        let resolvedURL: URL

        do {
            resolvedURL = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
        } catch {
            Log.download.error("URL(resolvingBookmarkData:) failed: \(error, privacy: .public)")
            downloads[index].failed = true
            return
        }

        guard resolvedURL.startAccessingSecurityScopedResource() else {
            Log.download.error("startAccessingSecurityScopedResource failed for resolved destination \(resolvedURL.path, privacy: .public)")
            downloads[index].failed = true
            return
        }

        defer { resolvedURL.stopAccessingSecurityScopedResource() }

        do {
            // Deliberately not .atomic — an atomic write creates a temp
            // file alongside the target and renames it into place, and
            // that rename step can throw against a security-scoped
            // export-picker URL (some providers don't like it) even
            // though the content itself already landed correctly at the
            // real destination. A plain direct write has no such rename
            // step to trip over.
            try data.write(to: resolvedURL)
            downloads[index].progress = 1.0

        } catch {
            Log.download.error("data.write(to:) failed for \(resolvedURL.path, privacy: .public): \(error, privacy: .public)")
            downloads[index].failed = true
        }
    }
}
