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

import Foundation
import Combine

struct DownloadItem: Identifiable {

    let id: UUID = UUID()
    var filename: String
    var progress: Double
    var failed: Bool = false

    var isComplete: Bool { progress >= 1.0 && !failed }
}


/// A completed download ready to be saved — presented via the system
/// document picker (see DocumentExporterView) so the user can rename it
/// and choose where it lands, same as any other iOS download flow.
struct PendingExport: Identifiable {
    let id = UUID()
    let url: URL
}


final class DownloadManager: ObservableObject {

    static let shared = DownloadManager()

    private init() {}


    @Published private(set) var downloads: [DownloadItem] = []
    @Published var pendingExport: PendingExport?

    /// Destinations with a download currently in flight — checked by
    /// BrowserState before tearing down a Link on navigation, so browsing
    /// to a different node mid-download doesn't kill the transfer.
    private var activeDownloadDestinations: Set<String> = []

    func isDownloading(from destinationHashHex: String) -> Bool {
        activeDownloadDestinations.contains(destinationHashHex.lowercased())
    }


    /// Progress of the most recent in-flight download, for the toolbar
    /// button's ring. Nil when nothing is currently downloading.
    var activeProgress: Double? {

        downloads.last(where: { !$0.isComplete && !$0.failed })?.progress
    }


    func download(path: String, from destinationHashHex: String) {

        let hex = destinationHashHex.lowercased()
        let filename = suggestedFilename(from: path)

        let item = DownloadItem(filename: filename, progress: 0)
        let id = item.id

        downloads.append(item)
        activeDownloadDestinations.insert(hex)

        LinkManager.shared.connect(to: hex) { [weak self] connectResult in

            guard let self else { return }

            switch connectResult {

            case .failure:
                self.markFailed(id, destination: hex)

            case .success(let link):

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
                                self.finish(id, data: data, filename: filename, destination: hex)

                            case .failure:
                                self.markFailed(id, destination: hex)
                            }
                        }
                    }
                )
            }
        }
    }


    private func suggestedFilename(from path: String) -> String {

        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "download" : name
    }


    private func updateProgress(_ id: UUID, progress: Double) {

        guard let index = downloads.firstIndex(where: { $0.id == id }) else {
            return
        }

        downloads[index].progress = progress
    }


    private func markFailed(_ id: UUID, destination: String) {

        activeDownloadDestinations.remove(destination)

        guard let index = downloads.firstIndex(where: { $0.id == id }) else {
            return
        }

        downloads[index].failed = true
    }


    private func finish(_ id: UUID, data: Data, filename: String, destination: String) {

        activeDownloadDestinations.remove(destination)

        guard let index = downloads.firstIndex(where: { $0.id == id }) else {
            return
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            // Overwrite any stale temp file from a previous download of
            // the same name — the export sheet is what actually decides
            // the final saved filename/location, this is just a handoff.
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }

            try data.write(to: tempURL)

            downloads[index].progress = 1.0
            pendingExport = PendingExport(url: tempURL)

        } catch {
            downloads[index].failed = true
        }
    }
}
