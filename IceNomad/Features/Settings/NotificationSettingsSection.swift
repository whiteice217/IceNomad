//
//  NotificationSettingsSection.swift
//  IceNomad
//
//  Settings > Notifications: sound on/off, built-in theme sounds with a
//  preview button, and a custom-sound picker reusing the same
//  UIDocumentPickerViewController pattern DownloadsView already uses for
//  exporting — this is the import-side counterpart.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Wraps UIDocumentPickerViewController's *import* flow so the user can
/// pick any audio file from Files/iCloud Drive/a third-party provider as
/// their custom notification sound.
struct AudioFileImporterView: UIViewControllerRepresentable {

    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {

        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onPick(url)
            }
        }
    }
}


struct NotificationSettingsSection: View {

    @ObservedObject private var notificationSettings = NotificationSettings.shared

    /// Owned by `NotificationSettingsView` (this Section's sole host
    /// now — Settings links to it via NavigationLink instead of
    /// embedding it directly) and presented from there, not from this
    /// `@State` locally — attaching `.sheet` to a `Section` nested
    /// inside a `Form` alongside several unrelated sibling sections
    /// races the section row's own UICollectionView cell lifecycle on
    /// first tap (confirmed live on both iOS and Mac Catalyst: the
    /// picker would flash open then immediately close, only working
    /// reliably on a *second* tap once the cell had settled). Presenting
    /// from the stable host page instead avoids that race entirely —
    /// same fix pattern already used for ContentView's QR-scan-to-chat
    /// sheet.
    @Binding var isPickingCustomSound: Bool

    var body: some View {

        Section {

            Toggle("Play Sound on New Message", isOn: $notificationSettings.soundEnabled)

            if notificationSettings.soundEnabled {

                Picker("Sound", selection: $notificationSettings.selectedSound) {

                    ForEach(NotificationSound.allCases.filter { $0 != .custom }) { sound in
                        Text(sound.displayName).tag(sound)
                    }

                    if let customName = notificationSettings.customSoundFilename {
                        Text(customName).tag(NotificationSound.custom)
                    }
                }

                // Two separate rows, not one shared HStack — Form/List
                // rows are backed by UICollectionView cells on Mac
                // Catalyst, and cramming two independent buttons into one
                // row risked a click near the boundary between them
                // resolving to the wrong action (confirmed live: tapping
                // "Preview" opened the file picker instead). One button
                // per row removes the ambiguity entirely.
                Button {
                    NotificationSoundPlayer.shared.preview(notificationSettings.selectedSound)
                } label: {
                    Label("Preview", systemImage: "speaker.wave.2")
                }
                .disabled(notificationSettings.selectedSound == .none)

                Button {
                    isPickingCustomSound = true
                } label: {
                    Label("Choose File…", systemImage: "folder")
                }
            }

        } header: {
            Text("Notifications")
        } footer: {
            Text("Choose a built-in theme sound, or pick your own audio file to play when a new message arrives.")
        }
    }
}
