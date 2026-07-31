//
//  NotificationSettings.swift
//  IceNomad
//
//  Persisted preferences for the incoming-message sound: on/off, which
//  built-in theme sound to use, and (if picked) a bookmark to a
//  user-supplied custom sound file. Same UIDocumentPickerViewController
//  bookmark pattern as DownloadsView's export flow, just import-side.
//

import Foundation
import Combine
import OSLog

enum NotificationSound: String, CaseIterable, Identifiable, Codable {

    case none
    case iceChime
    case glacierBlip
    case nootNoot
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .iceChime: return "Ice Chime"
        case .glacierBlip: return "Glacier Blip"
        case .nootNoot: return "Noot Noot"
        case .custom: return "Custom Sound"
        }
    }
}


final class NotificationSettings: ObservableObject {

    static let shared = NotificationSettings()

    private let soundEnabledKey = "notif_sound_enabled"
    private let selectedSoundKey = "notif_selected_sound"
    private let customBookmarkKey = "notif_custom_sound_bookmark"
    private let customFilenameKey = "notif_custom_sound_filename"

    @Published var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: soundEnabledKey)
        }
    }

    @Published var selectedSound: NotificationSound {
        didSet {
            UserDefaults.standard.set(selectedSound.rawValue, forKey: selectedSoundKey)
        }
    }

    @Published private(set) var customSoundFilename: String?

    private init() {

        soundEnabled = UserDefaults.standard.object(forKey: soundEnabledKey) as? Bool ?? true

        selectedSound = NotificationSound(
            rawValue: UserDefaults.standard.string(forKey: selectedSoundKey) ?? ""
        ) ?? .nootNoot

        customSoundFilename = UserDefaults.standard.string(forKey: customFilenameKey)
    }


    /// Bookmarks a document-picker-selected file so it can be resolved
    /// (and played) again on future launches, not just this session.
    func setCustomSound(url: URL) {

        guard url.startAccessingSecurityScopedResource() else {
            Log.audio.error("Couldn't access security-scoped resource for custom notification sound")
            return
        }

        defer { url.stopAccessingSecurityScopedResource() }

        do {

            let bookmark = try url.bookmarkData()

            UserDefaults.standard.set(bookmark, forKey: customBookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: customFilenameKey)

            customSoundFilename = url.lastPathComponent
            selectedSound = .custom

        } catch {
            Log.audio.error("Failed to bookmark custom notification sound: \(error)")
        }
    }


    func resolveCustomSoundURL() -> URL? {

        guard let bookmark = UserDefaults.standard.data(forKey: customBookmarkKey) else {
            return nil
        }

        var isStale = false

        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            return nil
        }

        return url
    }
}
