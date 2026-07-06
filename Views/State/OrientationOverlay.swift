//
//  OrientationOverlay.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

struct OrientationOverlay: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.75)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                
                Image(systemName: "iphone")
                    .font(.system(size: 80))
                    .rotationEffect(.degrees(animate ? 90 : 0))
                    .animation(
                        .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true),
                        value: animate
                    )
                
                Text("Turn your device sideways")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("IceNomad Browser require's Landscape mode")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .onAppear {
            animate = true
        }
    }
}
