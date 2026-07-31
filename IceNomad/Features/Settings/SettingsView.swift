//
//  SettingsView.swift
//  IceNomad
//

import SwiftUI

struct SettingsView: View {

    @ObservedObject private var userProfile = UserProfile.shared
    @ObservedObject private var interfaceManager = InterfaceManager.shared
    @ObservedObject private var peerStore = PeerStore.shared

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
                            .foregroundStyle(Theme.textSecondary)
                    }

                } footer: {
                    Text("Announces let other peers learn your name and public key, so they can message you and see you as a contact suggestion.")
                }

                Section {

                    Picker("Keep Announces", selection: $peerStore.maxAnnounces) {

                        ForEach(PeerStore.announceLimitOptions, id: \.self) { limit in
                            Text("\(limit)").tag(limit)
                        }
                    }

                } header: {
                    Text("Announce History")
                } footer: {
                    Text("The most recent \(peerStore.maxAnnounces) announced peers are kept. Older ones are dropped as new announces come in — saved contacts aren't affected.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
        }
    }
}
