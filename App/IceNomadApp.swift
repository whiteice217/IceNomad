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


    var body: some Scene {

        WindowGroup {

            Group {

                if startup.finished {

                    ContentView()

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
