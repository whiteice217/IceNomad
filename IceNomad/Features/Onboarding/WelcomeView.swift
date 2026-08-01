//
//  WelcomeView.swift
//  IceNomad
//
//  Shown once, on first launch. Assigns a random penguin-themed display
//  name (instead of the flat "Anonymous Nomad" default) and explains
//  what it is and where to change it later, rather than silently
//  handing someone a name they never knew was randomly picked.
//

import SwiftUI

struct WelcomeView: View {

    let onFinished: () -> Void

    @ObservedObject private var userProfile = UserProfile.shared

    var body: some View {

        VStack(spacing: 28) {

            Spacer()

            Image("IceNomadSplash")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 96 * 0.2237, style: .continuous))

            VStack(spacing: 10) {

                Text("Welcome to IceNomad")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("We picked you a name to get started.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {

                HStack(spacing: 10) {

                    Text(userProfile.displayName)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)

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

                Text("This is shown to others when you announce yourself on the network. Change it anytime in **Settings → Your Identity**.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                onFinished()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear {

            if userProfile.displayName.isEmpty || userProfile.displayName == "Anonymous Nomad" {
                userProfile.displayName = PenguinNameGenerator.random()
            }
        }
    }
}
