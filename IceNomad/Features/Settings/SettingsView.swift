//
//  SettingsView.swift
//  IceNomad
//

import SwiftUI

struct SettingsView: View {

    @ObservedObject private var userProfile = UserProfile.shared
    @ObservedObject private var interfaceManager = InterfaceManager.shared

    @State private var didSendAnnounce = false

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

                Section("Your Address") {

                    Text(ReticulumDestination.myDestinationHashHex)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Section {

                    Button {
                        interfaceManager.sendAnnounce()
                        didSendAnnounce = true
                    } label: {
                        Label("Send Announce Now", systemImage: "megaphone")
                    }

                    if didSendAnnounce {
                        Text("Announce sent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                } footer: {
                    Text("Announces let other peers learn your name and public key, so they can message you and see you as a contact suggestion.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
