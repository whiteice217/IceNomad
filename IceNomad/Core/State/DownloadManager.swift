//
//  DownloadManager.swift
//  IceNomad
//
//  IMPORTANT: Downloads are SIMULATED right now. Real file transfer over
//  Reticulum uses Resource transfer over an established Link — same
//  crypto dependency as messaging and page fetching. This lets the
//  downloads UI (button, progress ring, list) be built and tested now;
//  swap simulateDownload() for a real Resource-backed transfer later.
//

import Foundation
import Combine

struct DownloadItem: Identifiable {

    let id: UUID = UUID()
    var filename: String
    var progress: Double

    var isComplete: Bool { progress >= 1.0 }
}


final class DownloadManager: ObservableObject {

    static let shared = DownloadManager()

    private init() {}


    @Published private(set) var downloads: [DownloadItem] = []


    /// Progress of the most recent in-flight download, for the toolbar
    /// button's ring. Nil when nothing is currently downloading.
    var activeProgress: Double? {

        downloads.last(where: { !$0.isComplete })?.progress
    }


    func simulateDownload(named filename: String) {

        let item = DownloadItem(filename: filename, progress: 0)
        let id = item.id

        downloads.append(item)

        Task { @MainActor in

            for step in 1...20 {

                try? await Task.sleep(nanoseconds: 150_000_000)

                guard let index = downloads.firstIndex(where: { $0.id == id }) else {
                    return
                }

                downloads[index].progress = Double(step) / 20.0
            }
        }
    }
}
