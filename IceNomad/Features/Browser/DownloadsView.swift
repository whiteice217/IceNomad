//
//  DownloadsView.swift
//  IceNomad
//

import SwiftUI

// MARK: - Toolbar Button

struct DownloadsButton: View {

    let progress: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {

            ZStack {

                if let progress {

                    Circle()
                        .stroke(Theme.divider, lineWidth: 3)

                    Circle()
                        .trim(from: 0, to: max(progress, 0.02))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(progress * 100))")
                        .font(.system(size: 9, weight: .semibold))

                } else {

                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                }
            }
            .frame(width: 28, height: 28)
        }
    }
}


// MARK: - Sheet

struct DownloadsView: View {

    @ObservedObject private var downloadManager = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {

                if downloadManager.downloads.isEmpty {

                    ContentUnavailableView(
                        "No Downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Files offered by .mu pages will appear here.")
                    )

                } else {

                    ForEach(downloadManager.downloads) { item in

                        HStack {

                            VStack(alignment: .leading, spacing: 4) {

                                Text(item.filename)
                                    .font(.subheadline)

                                if item.isComplete {

                                    Text("Complete")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)

                                } else {

                                    ProgressView(value: item.progress)
                                }
                            }

                            Spacer()

                            if item.isComplete {

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.success)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {

                    Button("Simulate a Download") {
                        downloadManager.simulateDownload(named: "example-file.txt")
                    }

                } footer: {

                    Text("Real downloads need file transfer over an established Link, same as page fetching — this button lets you test the UI until that exists.")
                }
            }
            .navigationTitle("Downloads")
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
