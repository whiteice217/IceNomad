//
//  SplashView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

struct SplashView: View {

    @ObservedObject var startup: StartupManager

    var body: some View {

        Group {

            if startup.awaitingSetup {

                // A real stop, not a note that might flash by unread —
                // waits for the wizard to actually finish before startup
                // continues. The genuine first-run case only (zero
                // connections configured at all) — see
                // StartupManager.awaitingSetup. Takes the full screen
                // (its own logo lives in its first step) rather than
                // sitting under the plain splash logo below.
                ConnectionSetupWizardView(
                    onAddedConnection: { startup.continueAfterAddingConnection() },
                    onSkip: { tab in startup.continueWithoutSetup(landingOn: tab) }
                )
                .transition(.opacity)

            } else {

                VStack(spacing: 30) {

                    Image("IceNomadSplash")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 180 * 0.2237, style: .continuous))

                    VStack(spacing: 12) {

                        ProgressView(value: startup.progress)
                            .frame(width: 220)

                        Text(startup.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(height: 20)
                    }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: startup.playCompletionSound) { oldValue, newValue in

            if newValue {
                SoundManager.shared.playNoot()
            }

        }
    }
}
