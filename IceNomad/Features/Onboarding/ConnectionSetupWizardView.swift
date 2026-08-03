//
//  ConnectionSetupWizardView.swift
//  IceNomad
//
//  A real multi-step wizard, not a single scrolling screen — Bryan
//  wanted it to "feel like reading a book": each step slides in from
//  the trailing edge going forward, from the leading edge going back,
//  with Next/Back pinned to the bottom of the window throughout.
//
//  Shown two ways: by SplashView in place of the normal progress bar
//  when StartupManager finds zero configured connections (the genuine
//  first-run case), and again from Settings' "Reset Connections" action
//  — both just supply their own onFinished closure, the wizard itself
//  doesn't know or care which context it's running in.
//
//  Step 1 (identity) reuses the exact same UserProfile.shared /
//  PenguinNameGenerator naming system the old standalone WelcomeView
//  used — that view is retired now that naming lives here instead (see
//  ContentView, which no longer presents it).
//

import SwiftUI

private enum WizardStep: Int, CaseIterable {
    case identity
    case connectionType
    case connectionDetails
}


struct ConnectionSetupWizardView: View {

    /// Fires once a connection was actually added and saved — the
    /// caller should treat this as "setup is done, proceed."
    let onAddedConnection: () -> Void
    /// Fires on an explicit skip, optionally naming a tab the caller
    /// should land on instead of the default (e.g. routing to Settings
    /// isn't used by this wizard currently, but the hook stays generic).
    let onSkip: (AppTab?) -> Void

    @State private var step: WizardStep = .identity
    @State private var goingForward = true
    @State private var chosenType: ConnectionType?

    @ObservedObject private var userProfile = UserProfile.shared

    private static let maxWidth: CGFloat = {
        #if targetEnvironment(macCatalyst)
        520
        #else
        420
        #endif
    }()

    var body: some View {

        VStack(spacing: 0) {

            ZStack {
                currentStepView
                    .id(step)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
                        )
                    )
            }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .frame(maxWidth: Self.maxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear {

            if userProfile.displayName.isEmpty || userProfile.displayName == "Anonymous Nomad" {
                userProfile.displayName = PenguinNameGenerator.random()
            }
        }
    }


    @ViewBuilder
    private var currentStepView: some View {

        switch step {

        case .identity:
            identityStep

        case .connectionType:
            connectionTypeStep

        case .connectionDetails:

            switch chosenType {

            case .tcpClient:
                TCPRelayStepView(onAdded: onAddedConnection)

            case .rNode:
                RNodeSetupStepView(onSaved: onAddedConnection)

            case nil:
                // Shouldn't be reachable — Next on .connectionType is
                // disabled until chosenType is set — but fall back to
                // the type picker rather than showing nothing.
                connectionTypeStep
            }
        }
    }


    // MARK: - Step 1: Identity

    private var identityStep: some View {

        ScrollView {

            VStack(spacing: 24) {

                Spacer(minLength: 20)

                Image("IceNomadSplash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 88 * 0.2237, style: .continuous))

                VStack(spacing: 8) {

                    Text("Welcome to IceNomad")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Pick a name — this is what other peers see when you announce yourself on the mesh.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 10) {

                    HStack(spacing: 10) {

                        TextField("Display name", text: $userProfile.displayName)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.words)

                        Button {
                            withAnimation {
                                userProfile.displayName = PenguinNameGenerator.random()
                            }
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text("Change this anytime later in Settings → Your Identity.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer(minLength: 20)
            }
        }
    }


    // MARK: - Step 2: Connection type

    private var connectionTypeStep: some View {

        ScrollView {

            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 6) {

                    Text("Let's get you connected")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)

                    Text("IceNomad needs a way to reach the Reticulum mesh. How are you connecting?")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                connectionTypeCard(
                    type: .tcpClient,
                    title: "TCP Client",
                    subtitle: "The easy way — connect to a public relay over the internet. Recommended if you're not sure.",
                    icon: "network"
                )

                connectionTypeCard(
                    type: .rNode,
                    title: "RNode",
                    subtitle: "Your own LoRa radio hardware — Bluetooth, USB, or WiFi.",
                    icon: "antenna.radiowaves.left.and.right"
                )
            }
            .padding(.horizontal, 4)
        }
    }


    private func connectionTypeCard(type: ConnectionType, title: String, subtitle: String, icon: String) -> some View {

        let isSelected = chosenType == type

        return Button {
            chosenType = type
        } label: {

            HStack(spacing: 14) {

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }


    // MARK: - Bottom navigation

    private var bottomBar: some View {

        HStack {

            if step != .identity {

                Button {
                    goBack()
                } label: {
                    Text("Back")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)

            } else {

                Button {
                    onSkip(nil)
                } label: {
                    Text("Skip Setup")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            // The two connectionDetails sub-steps finish themselves via
            // their own "Add & Continue" / "Save & Continue" actions —
            // there's nowhere further for a shared Next to go from there.
            if step != .connectionDetails {

                Button {
                    goNext()
                } label: {
                    Text("Next")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .disabled(step == .connectionType && chosenType == nil)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        #if targetEnvironment(macCatalyst)
        .background(.bar)
        #else
        .background(.ultraThinMaterial)
        #endif
    }


    private func goNext() {

        guard let nextStep = WizardStep(rawValue: step.rawValue + 1) else {
            return
        }

        goingForward = true

        withAnimation(.easeInOut(duration: 0.35)) {
            step = nextStep
        }
    }


    private func goBack() {

        guard let previousStep = WizardStep(rawValue: step.rawValue - 1) else {
            return
        }

        goingForward = false

        withAnimation(.easeInOut(duration: 0.35)) {
            step = previousStep
        }
    }
}
