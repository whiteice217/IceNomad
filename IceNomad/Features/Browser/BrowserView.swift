//
//  BrowserView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

struct BrowserView: View {
    @StateObject private var orientation = OrientationObserver()

    var body: some View {
        ZStack {
            
            NavigationStack {
                Text("Browser")
                    .navigationTitle("Browser")
            }

            // Overlay on top
            if !orientation.isLandscape {
                OrientationOverlay()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }
}
