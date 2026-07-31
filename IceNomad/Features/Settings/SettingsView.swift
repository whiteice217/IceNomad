//
//  SettingsView.swift
//  IceNomad
//

import SwiftUI

struct SettingsView: View {

    @Binding var selectedTab: AppTab
    @Binding var pendingChatHex: String?

    @ObservedObject private var userProfile = UserProfile.shared

    @State private var isPickingCustomNotificationSound = false

    /// Bryan's own Mac IceNomad LXMF address — lets a user report a bug
    /// straight from the app instead of leaving it for GitHub/email only.
    private static let maintainerLXMFHex = "e3b6916da538c5a7f3db14325fe3b650"

    var body: some View {
        NavigationStack {
            Form {

                Section {

                    TextField("Display Name", text: $userProfile.displayName)

                } header: {
                    Text("Your Identity")
                } footer: {
                    Text("Shown to others as your name when you announce.")
                }

                NotificationSettingsSection(isPickingCustomSound: $isPickingCustomNotificationSound)

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
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .sheet(isPresented: $isPickingCustomNotificationSound) {
                AudioFileImporterView { url in
                    NotificationSettings.shared.setCustomSound(url: url)
                }
            }
        }
    }
}
