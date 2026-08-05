//
//  IceNomadApp.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//
import SwiftUI


@main
struct IceNomadApp: App {

    @StateObject private var startup = StartupManager()

    init() {
        SystemMonitor.shared.start()

        #if targetEnvironment(macCatalyst)
        // SwiftUI's .help() has no public delay parameter — Mac Catalyst
        // still renders these through AppKit's real tooltip mechanism
        // under the hood, which reads its hover delay (in milliseconds)
        // from this otherwise-undocumented-but-standard default. 200ms
        // instead of the system default (~1500ms) so toolbar tooltips
        // feel responsive rather than sluggish.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 200])
        #endif
    }


    var body: some Scene {

        WindowGroup {

            Group {

                if startup.finished {

                    ContentView(initialTab: startup.pendingPostSetupTab)

                } else {

                    SplashView(startup: startup)
                        .transition(.opacity)

                }

            }
            .onAppear {

                startup.begin()

            }

        }
    }
}
