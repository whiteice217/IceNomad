//
//  SplashView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

struct SplashView: View {

    @State private var progress: Double = 0
    @State private var message: String = ""

    var body: some View {

        VStack(spacing: 30) {

            Image("IceNomadSplash")
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 180 * 0.2237, style: .continuous))
            
            VStack(spacing: 12) {

                ProgressView(value: progress)
                    .frame(width: 220)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 20)
            }
        }
        .onAppear {
            
            // Pick a random loading message
            message = LoadingMessages.random()

            // Animate loading bar
            withAnimation(.easeInOut(duration: 2.5)) {
                progress = 1.0
            }
        }
    }
}
