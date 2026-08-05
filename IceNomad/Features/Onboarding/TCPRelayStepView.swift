//
//  TCPRelayStepView.swift
//  IceNomad
//
//  The setup wizard's TCP relay step. Adding a relay goes through the
//  same ConnectionStorage.addTCPClient() the Connections tab's own Save
//  button uses.
//
//  Deliberately just two choices — "Use IceNomad" and "Other" — not the
//  full public-relay list ConnectionsView's own Quick Start section
//  shows (SuggestedConnection.all still has those, unchanged, for that
//  screen). Per Bryan: Tux now bridges to all the other relays IceNomad
//  used to list here individually, so a new user picking one of those
//  by hand in the wizard doesn't buy them anything — "Other" covers
//  anyone who already knows a specific relay they want instead.
//

import SwiftUI

struct TCPRelayStepView: View {

    let onAdded: () -> Void

    @State private var addedConnectionName: String?
    @State private var showingOtherForm = false
    @State private var otherName = ""
    @State private var otherAddress = ""
    @State private var otherPort = "4242"

    private var isOtherReadyToSave: Bool {
        !otherAddress.trimmingCharacters(in: .whitespaces).isEmpty
            && !otherPort.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {

        ScrollView {

            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 6) {

                    Text("Pick a Relay")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)

                    Text("You can add more later in Connections.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                recommendedRelayCard

                otherRelayCard
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

            Text("Our own always-on relay — bridges you to the wider mesh, and it's what powers Tux, IceNomad's built-in search engine: your Browser home page, cached pages for speed, and live search suggestions as you type.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            addButton(name: relay?.name ?? "IceNomad Public Relay") {
                if let relay {
                    add(name: relay.name, address: relay.address, port: relay.port)
                }
            }

        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
        )
    }


    private var otherRelayCard: some View {

        VStack(alignment: .leading, spacing: 10) {

            Text("Other")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            // Per Bryan: be explicit that Tux-as-homepage (and its
            // cache/search conveniences) is specific to IceNomad's own
            // relay — a relay entered here still reaches the real mesh
            // (and Tux itself is still reachable by browsing to it
            // directly), just without those extras, same as an RNode-
            // only setup or any other future connection type.
            Text("Already know a relay you want to use instead? Tux's homepage, cache, and search suggestions are specific to the IceNomad relay above. Any other relay — or an RNode — still reaches the real mesh with plain live browsing; you can still visit Tux directly once you're connected, just without those extras.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            if showingOtherForm {

                VStack(spacing: 10) {

                    TextField("Name", text: $otherName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Address (host or IP)", text: $otherAddress)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Port", text: $otherPort)
                        .textFieldStyle(.roundedBorder)
                        #if !targetEnvironment(macCatalyst)
                        .keyboardType(.numberPad)
                        #endif
                }

                addButton(name: otherName.isEmpty ? "Other" : otherName, disabled: !isOtherReadyToSave) {
                    let name = otherName.trimmingCharacters(in: .whitespaces)
                    add(
                        name: name.isEmpty ? "Custom Relay" : name,
                        address: otherAddress.trimmingCharacters(in: .whitespaces),
                        port: otherPort.trimmingCharacters(in: .whitespaces)
                    )
                }

            } else {

                Button {
                    withAnimation { showingOtherForm = true }
                } label: {
                    Text("Enter a Relay Manually")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(addedConnectionName != nil)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }


    private func addButton(name: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {

        Button(action: action) {

            if addedConnectionName == name {
                Label("Added", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            } else {
                Text("Add & Continue")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(addedConnectionName != nil || disabled)
    }


    private func add(name: String, address: String, port: String) {

        guard addedConnectionName == nil else {
            return
        }

        ConnectionStorage.shared.addTCPClient(name: name, address: address, port: port)
        InterfaceManager.shared.restartAll()
        addedConnectionName = name

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onAdded()
        }
    }
}
