//
//  BrowserSettingsView.swift
//  IceNomad
//
//  Settings > Browsing — its own pushed page now (Bryan's call,
//  2026-08-05: every settings area with more than one control gets the
//  same "button on the main list, actual settings on their own page"
//  treatment Manage Connections already had), rather than living
//  inline among several other sections on the main Settings list. Just
//  a thin Form wrapper around BrowserSettingsSection, which still
//  holds all the actual controls (cache, search, homepage) unchanged.
//

import SwiftUI

struct BrowserSettingsView: View {

    var body: some View {

        Form {
            BrowserSettingsSection()
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Browsing")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
