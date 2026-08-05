//
//  DownloadsView.swift
//  IceNomad
//

import SwiftUI
import UIKit

// MARK: - Document export (save-location picker)

/// Wraps UIDocumentPickerViewController's export flow so the user can
/// name/place a download *before* it fetches anything (see
/// DownloadManager's header comment) — SwiftUI's own `.fileExporter`
/// needs a `FileDocument`-conforming type, which is unnecessary ceremony
/// here; this exports a small placeholder file directly, then reports
/// back exactly where the system placed it so the real data can be
/// written there once it arrives.
struct DocumentExporterView: UIViewControllerRepresentable {

    let url: URL
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {

        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {

        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {

            guard let url = urls.first else {
                onCancel()
                return
            }

            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}


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

                    ForEach(downloadManager.downloads.reversed()) { item in

                        HStack {

                            VStack(alignment: .leading, spacing: 4) {

                                Text(item.filename)
                                    .font(.subheadline)

                                if item.failed {

                                    Text("Failed")
                                        .font(.caption)
                                        .foregroundStyle(Theme.danger)

                                } else if item.cancelled {

                                    Text("Cancelled")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)

                                } else if item.isComplete {

                                    Text("Complete")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)

                                } else if item.awaitingDestination {

                                    Text("Choose Save Location…")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)

                                } else {

                                    ProgressView(value: item.progress)
                                }
                            }

                            Spacer()

                            if item.isActive {

                                Button {
                                    downloadManager.cancel(item.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .buttonStyle(.plain)

                            } else if item.failed {

                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.danger)

                            } else if item.cancelled {

                                Image(systemName: "slash.circle")
                                    .foregroundStyle(Theme.textSecondary)

                            } else if item.isComplete {

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.success)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Downloads")
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {

                    Button("Clear") {
                        downloadManager.clearFinished()
                    }
                    .disabled(!downloadManager.downloads.contains { !$0.isActive })
                }
            }
        }
    }
}
