//
//  DownloadsView.swift
//  IceNomad
//

import SwiftUI
import UIKit

// MARK: - Document export (save-location picker)

/// Wraps UIDocumentPickerViewController's export flow so a finished
/// download can be renamed and saved anywhere the user picks (Files,
/// iCloud Drive, a third-party provider) — SwiftUI's own `.fileExporter`
/// needs a `FileDocument`-conforming type, which is unnecessary ceremony
/// for a file that already exists on disk as raw bytes; this exports the
/// existing temp file directly, same as Safari's download-complete flow.
struct DocumentExporterView: UIViewControllerRepresentable {

    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {

        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {

        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish()
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
