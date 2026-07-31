//
//  StartupManager.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/8/26.
//
//  Drives the splash screen through six real startup stages — each
//  one's messages cycle only while that stage's actual condition
//  (interfaces loaded, a connection is up, an announce has arrived...)
//  hasn't been met yet, capped by a timeout so a slow or unreachable
//  network can't hang the splash screen forever. This is the same
//  InterfaceManager.shared instance the rest of the app uses, so this
//  IS the app's real startup, not a simulation of one.
//
import Foundation
import Combine
import SwiftUI


@MainActor
class StartupManager: ObservableObject {


    @Published var progress: Double = 0
    @Published var message: String = ""
    @Published var finished = false
    @Published var failed = false
    @Published var playCompletionSound = false


    private let interfaceManager = InterfaceManager.shared


    func begin() {

        Task {

            await runSoftwareLaunching()
            await runFoundConnections()

            if !interfaceManager.interfaces.isEmpty {

                await runConnectingToNetwork()

                if interfaceManager.connectionStates.values.contains(true) {

                    await runConnectionEstablished()
                    await runReceivingAnnounces()
                }
            }

            withAnimation {

                progress = 1.0
                message = LoadingMessages.random(from: LoadingMessages.appReady)

            }

            // Trigger NOOT NOOT
            playCompletionSound = true


            try? await Task.sleep(
                nanoseconds: 1_000_000_000
            )


            finished = true
        }
    }


    // MARK: - Stages

    private func runSoftwareLaunching() async {

        await cycle(LoadingMessages.softwareLaunching, to: 0.10, duration: 1.4)
    }


    private func runFoundConnections() async {

        interfaceManager.loadInterfaces()

        await cycle(LoadingMessages.foundConnections, to: 0.25, duration: 1.2)
    }


    private func runConnectingToNetwork() async {

        interfaceManager.startAll()

        await cycle(
            LoadingMessages.connectingToNetwork,
            to: 0.60,
            maxDuration: 10,
            until: { [interfaceManager] in interfaceManager.connectionStates.values.contains(true) }
        )
    }


    private func runConnectionEstablished() async {

        await cycle(LoadingMessages.connectionEstablished, to: 0.75, duration: 1.6)
    }


    private func runReceivingAnnounces() async {

        await cycle(
            LoadingMessages.receivingAnnounces,
            to: 0.95,
            maxDuration: 6,
            until: { !PeerStore.shared.peers.isEmpty }
        )
    }


    // MARK: - Message cycling

    /// Shows messages from `pool` for a fixed duration, one at a time.
    private func cycle(_ pool: [String], to targetProgress: Double, duration: Double) async {

        await cycle(pool, to: targetProgress, maxDuration: duration, until: { false })
    }


    /// Shows messages from `pool`, switching every ~1.6s, until either
    /// `condition` becomes true or `maxDuration` elapses — whichever
    /// comes first. A stage whose condition never resolves (offline,
    /// unreachable network) still lets the splash screen move on.
    private func cycle(_ pool: [String], to targetProgress: Double, maxDuration: Double, until condition: () -> Bool) async {

        withAnimation(.easeInOut(duration: 0.5)) {
            progress = targetProgress
        }

        let deadline = Date().addingTimeInterval(maxDuration)

        while !condition(), Date() < deadline {

            withAnimation(.easeInOut(duration: 0.3)) {
                message = LoadingMessages.random(from: pool)
            }

            try? await Task.sleep(nanoseconds: 1_600_000_000)
        }
    }
}
