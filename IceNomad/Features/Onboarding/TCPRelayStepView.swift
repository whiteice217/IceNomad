//
//  TCPRelayStepView.swift
//  IceNomad
//
//  The setup wizard's TCP relay step. Adding a relay goes through the
//  same ConnectionStorage.addTCPClient() the Connections tab's own Save
//  button uses.
//

import SwiftUI

struct TCPRelayStepView: View {

    let onAdded: () -> Void

    @State private var addedConnectionName: String?

    private var otherRelays: [SuggestedConnection] {
        SuggestedConnection.all.filter { !$0.isRecommended }
    }

    var body: some View {

        ScrollView {

            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 6) {

                    Text("Pick a Relay")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)

                    Text("Pick one to get started — you can add more later in Connections.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                recommendedRelayCard

                if !otherRelays.isEmpty {
                    otherRelaysSection
                }
            }
            .padding(.horizontal, 4)
        }
    }


    private var recommendedRelayCard: some View {

        let relay = SuggestedConnection.all.first { $0.isRecommended }

        return VStack(alignment: .leading, spacing: 10) {

            Label("Recommended", systemImage: "star.fill")
                .font(.caption.bold())
                .foregroundStyle(.yellow)

            Text(relay?.name ?? "IceNomad Public Relay")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("Our own always-on relay — the fastest way onto the mesh, and it's what powers Tux, IceNomad's built-in search engine, as your Browser home page.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            addButton(for: relay)

        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
        )
    }


    private var otherRelaysSection: some View {

        VStack(alignment: .leading, spacing: 8) {

            Text("Other public relays")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.textPrimary)

            // Per Bryan: be explicit that Tux-as-homepage is specific to
            // IceNomad's own relay — these still reach the real mesh
            // (and Tux itself is still reachable by browsing to it
            // directly), just not as the automatic Browser home page.
            Text("Tux's search homepage is only available on the IceNomad Public Relay above — on these, you can still browse to Tux directly once you're connected.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            ForEach(otherRelays) { relay in

                Button {
                    add(relay)
                } label: {

                    HStack {

                        VStack(alignment: .leading, spacing: 2) {
                            Text(relay.name)
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(relay.address):\(relay.port)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()

                        if addedConnectionName == relay.name {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(addedConnectionName != nil)
            }
        }
    }


    private func addButton(for relay: SuggestedConnection?) -> some View {

        Button {
            if let relay {
                add(relay)
            }
        } label: {

            if addedConnectionName == relay?.name {
                Label("Added", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            } else {
                Text("Add & Continue")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(addedConnectionName != nil)
    }


    private func add(_ relay: SuggestedConnection) {

        guard addedConnectionName == nil else {
            return
        }

        ConnectionStorage.shared.addTCPClient(name: relay.name, address: relay.address, port: relay.port)
        InterfaceManager.shared.restartAll()
        addedConnectionName = relay.name

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onAdded()
        }
    }
}
