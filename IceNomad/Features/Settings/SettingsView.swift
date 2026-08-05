//
//  SettingsView.swift
//  IceNomad
//
//  Every settings area with more than one control behind a button
//  pushing to its own page — Bryan's call, 2026-08-05, generalizing
//  the "Manage Connections" pattern this list already used to
//  Browsing and Notifications too — rather than each living inline as
//  its own Section here. What's left inline is genuinely flat: single
//  links/actions with nothing further to configure. Sections below are
//  ordered by importance (Bryan's explicit ask): Getting Started first
//  — a first-time user opening Settings confused about what to do
//  benefits from a signpost before anything else, and it already
//  explains everything below it — then connections (nothing else works
//  without one), then Browsing (Browser is this app's central, day-to-
//  day tab), then Notifications, then the occasional-use reset action,
//  then support/feedback, then donating.
//

import SwiftUI

struct SettingsView: View {

    @Binding var selectedTab: AppTab
    @Binding var pendingChatHex: String?
    /// Threaded through only so it can be handed to ConnectionsView,
    /// which still needs it for QR-scan routing (a scanned NomadNet
    /// page hands off to Browser) now that Connections lives behind a
    /// NavigationLink here instead of its own tab.
    @Binding var pendingBrowseHex: String?
    @Binding var isShowingSetupWizard: Bool

    @State private var isConfirmingConnectionsReset = false

    /// Bryan's own Mac IceNomad LXMF address — lets a user report a bug
    /// straight from the app instead of leaving it for GitHub/email only.
    private static let maintainerLXMFHex = "e3b6916da538c5a7f3db14325fe3b650"

    var body: some View {
        NavigationStack {
            Form {

                Section {

                    NavigationLink {
                        UserGuideView()
                    } label: {
                        Label("Getting Started", systemImage: "book")
                    }

                } footer: {
                    Text("New to Reticulum? A plain-language walkthrough of what it is, messaging, browsing, and where to go if you get stuck.")
                }

                Section {

                    NavigationLink {
                        ConnectionsView(selectedTab: $selectedTab, pendingChatHex: $pendingChatHex, pendingBrowseHex: $pendingBrowseHex)
                    } label: {
                        Label("Manage Connections", systemImage: "network")
                    }

                } footer: {
                    Text("TCP relays and RNode radios — add, edit, or remove how IceNomad reaches the Reticulum network.")
                }

                Section {

                    NavigationLink {
                        BrowserSettingsView()
                    } label: {
                        Label("Browsing", systemImage: "globe")
                    }

                } footer: {
                    Text("Tux's cache and search suggestions, and your Browser home page.")
                }

                Section {

                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell")
                    }

                } footer: {
                    Text("Whether a sound plays on a new message, and which one.")
                }

                Section {

                    Button(role: .destructive) {
                        isConfirmingConnectionsReset = true
                    } label: {
                        Label("Reset Connections & Rerun Setup", systemImage: "arrow.counterclockwise")
                    }
                    .confirmationDialog(
                        "Remove all saved connections?",
                        isPresented: $isConfirmingConnectionsReset,
                        titleVisibility: .visible
                    ) {
                        Button("Reset & Rerun Setup", role: .destructive) {
                            ConnectionStorage.shared.save([])
                            InterfaceManager.shared.restartAll()
                            isShowingSetupWizard = true
                        }
                    } message: {
                        Text("This removes every TCP and RNode connection you've configured, then walks you back through setup. This can't be undone.")
                    }

                } footer: {
                    Text("Also useful if you want to switch to the IceNomad Public Relay for Tux search, or start over with a different RNode.")
                }

                Section {

                    Link(destination: URL(string: "https://github.com/whiteice217/IceNomad/issues")!) {
                        Label("Report a Bug on GitHub", systemImage: "ladybug")
                    }

                    Link(destination: URL(string: "mailto:wanderingpenguin@icenomad.net")!) {
                        Label("Email Support", systemImage: "envelope")
                    }

                    if Self.maintainerLXMFHex.allSatisfy({ $0 == "0" }) == false {

                        Button {
                            pendingChatHex = Self.maintainerLXMFHex
                            selectedTab = .messages
                        } label: {
                            Label("Message the Developer", systemImage: "message")
                        }
                    }

                } header: {
                    Text("Support & Feedback")
                } footer: {
                    Text("Found a bug or have an idea? Any of these reach me directly.")
                }

                Section {

                    // No anchor fragment on purpose — GitHub's heading-ID
                    // slugger handles a leading emoji inconsistently
                    // enough that guessing it risks a silently-broken
                    // scroll-to; the plain README link always works, the
                    // section is just a short scroll from the top.
                    Link(destination: URL(string: "https://github.com/whiteice217/IceNomad")!) {
                        Label("Support IceNomad", systemImage: "heart.fill")
                            .foregroundStyle(Theme.danger)
                    }

                } footer: {
                    Text("IceNomad is a hobby project, built and maintained out of pocket. If it's useful to you, donations are deeply appreciated — every bit goes back into development and upkeep.")
                }

                Section {

                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionString)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Button {
                        isCheckingForUpdate = true
                        AppUpdateChecker.shared.checkForUpdate { found in
                            isCheckingForUpdate = false
                            if !found { isUpToDateAlertPresented = true }
                        }
                    } label: {
                        HStack {
                            Text("Check for Updates")
                            if isCheckingForUpdate {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isCheckingForUpdate)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .alert("You're Up to Date", isPresented: $isUpToDateAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Version \(appVersionString) is the latest available.")
            }
        }
    }

    @State private var isCheckingForUpdate = false
    @State private var isUpToDateAlertPresented = false

    /// "1.0 (3)" — marketing version plus build number, so two builds
    /// sharing a marketing version (e.g. between releases) still read as
    /// distinguishable to anyone reporting a bug.
    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
