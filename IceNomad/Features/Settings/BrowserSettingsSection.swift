//
//  BrowserSettingsSection.swift
//  IceNomad
//
//  Settings > Browsing: whether to prefer Tux's cache before falling
//  back to a live connection, and an optional custom homepage
//  overriding the automatic Tux-via-Public-Relay-else-default-screen
//  behavior.
//

import SwiftUI

struct BrowserSettingsSection: View {

    @ObservedObject private var browserSettings = BrowserSettings.shared

    @State private var homepageDraft: String = ""
    @State private var homepageSaveFailed = false

    var body: some View {

        Section {

            Toggle("Prefer Cached Pages", isOn: $browserSettings.preferCachedContent)

        } header: {
            Text("Browsing")
        } footer: {
            Text("When on, pages load from Tux's cache first for speed, falling back to a live connection only if Tux hasn't seen that page. Turn off to always connect live — slower, but guaranteed to reflect the page's current content.")
        }

        Section {

            TextField("hash:/path", text: $homepageDraft)
                .autocorrectionDisabled()
                .onAppear {
                    homepageDraft = browserSettings.customHomepageAddress ?? ""
                }
                .onSubmit {
                    homepageSaveFailed = !browserSettings.setCustomHomepage(homepageDraft)
                }

            if homepageSaveFailed {
                Text("Not a valid address — expected a 32-character hash followed by :/path")
                    .foregroundStyle(Theme.danger)
                    .font(.footnote)
            }

            if browserSettings.customHomepageAddress != nil {

                Button(role: .destructive) {
                    browserSettings.setCustomHomepage(nil)
                    homepageDraft = ""
                    homepageSaveFailed = false
                } label: {
                    Label("Reset to Automatic", systemImage: "arrow.counterclockwise")
                }
            }

        } header: {
            Text("Homepage")
        } footer: {
            Text("Leave blank to use Tux automatically when connected via the IceNomad Public Relay, or the default Browser screen otherwise.")
        }
    }
}
