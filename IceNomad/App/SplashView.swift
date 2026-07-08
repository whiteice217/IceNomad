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

        VStack(spacing: 30) {

            Image("IceNomadSplash")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 180 * 0.2237,
                        style: .continuous
                    )
                )


            VStack(spacing: 12) {

                ProgressView(value: startup.progress)
                    .frame(width: 220)

                Text(startup.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 20)
            }
        }
        .onChange(of: startup.playCompletionSound) { oldValue, newValue in

            if newValue {
                print("NOOT EVENT RECEIVED")
                SoundManager.shared.playNoot()
            }

        }
    }
}
