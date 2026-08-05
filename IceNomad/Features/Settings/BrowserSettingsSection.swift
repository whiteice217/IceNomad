//
//  BrowserSettingsSection.swift
//  IceNomad
//
//  Settings > Browsing: whether to prefer Tux's cache before falling
//  back to a live connection, whether the address bar shows Tux's live
//  search suggestions, and an optional custom homepage overriding the
//  automatic Tux-via-Public-Relay-else-default-screen behavior.
//
//  The first two are relay-specific features (Bryan's explicit spec,
//  2026-08-05) — both toggles are disabled, and their footers say so,
//  whenever InterfaceManager isn't actually reporting a connected
//  IceNomad Public Relay. Turning them "on" here only sets the
//  preference for *when* that relay is in use; it can't force the
//  feature on over a different relay or RNode.
//

import SwiftUI

struct BrowserSettingsSection: View {

    @ObservedObject private var browserSettings = BrowserSettings.shared
    @ObservedObject private var interfaceManager = InterfaceManager.shared

    @State private var homepageDraft: String = ""
    @State private var homepageSaveFailed = false

    private var isUsingIceNomadRelay: Bool {
        interfaceManager.isUsingIceNomadPublicRelay
    }

    var body: some View {

        Section {

            Toggle("Prefer Cached Pages", isOn: $browserSettings.preferCachedContent)
                .disabled(!isUsingIceNomadRelay)

            Toggle("Tux Search Suggestions", isOn: $browserSettings.tuxSearchEnabled)
                .disabled(!isUsingIceNomadRelay)

        } header: {
            Text("Browsing")
        } footer: {
            if isUsingIceNomadRelay {
                Text("Prefer Cached Pages loads from Tux's cache first for speed, falling back to a live connection only if Tux hasn't seen that page. Tux Search Suggestions shows live results as you type in the address bar. Turn either off to always connect live.")
            } else {
                Text("Both require the IceNomad Public Relay, which isn't currently connected — Browser is using plain live NomadNet addressing instead. Connect via that relay in Connections to enable Tux's cache and search.")
                    .foregroundStyle(Theme.warning)
            }
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
