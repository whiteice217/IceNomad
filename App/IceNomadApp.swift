//
//  IceNomadApp.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

@main
struct IceNomadApp: App {

    @State private var showSplash = true

    init() {
        ReticulumManager.shared.start()
    }

    var body: some Scene {

        WindowGroup {

            if showSplash {

                SplashView()
                    .transition(.opacity)
                    .onAppear {

                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {

                            withAnimation(.easeInOut(duration: 0.5)) {
                                showSplash = false
                            }

                        }
                    }

            } else {

                ContentView()

            }
        }
    }
}
