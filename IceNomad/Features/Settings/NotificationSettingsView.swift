//
//  NotificationSettingsView.swift
//  IceNomad
//
//  Settings > Notifications — its own pushed page now (Bryan's call,
//  2026-08-05: every settings area with more than one control gets the
//  same "button on the main list, actual settings on their own page"
//  treatment Manage Connections already had), rather than living
//  inline as a Section among several others on the main Settings list.
//  Just a thin Form wrapper around NotificationSettingsSection, which
//  still holds all the actual controls unchanged.
//

import SwiftUI

struct NotificationSettingsView: View {

    /// Owned here now (was SettingsView's) — presenting from this
    /// page's own Form is still "a stable, never-recycled container"
    /// in the same sense the original fix needed (see
    /// NotificationSettingsSection's doc comment on this same
    /// property): this Form isn't one row among several longer
    /// siblings the way the old inline Section was, it's the page's
    /// only content.
    @State private var isPickingCustomSound = false

    var body: some View {

        Form {
            NotificationSettingsSection(isPickingCustomSound: $isPickingCustomSound)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Notifications")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isPickingCustomSound) {
            AudioFileImporterView { url in
                NotificationSettings.shared.setCustomSound(url: url)
            }
        }
    }
}
