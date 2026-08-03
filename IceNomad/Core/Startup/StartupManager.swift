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
    /// True only when the user has genuinely never configured any
    /// connection at all (interfaceManager.interfaces.isEmpty right
    /// after loadInterfaces()) — the real first-run case. Startup pauses
    /// for real here (not an auto-continuing note) and shows the setup
    /// wizard. Deliberately does NOT trigger just because Tux specifically
    /// couldn't be reached this launch, or because an already-configured
    /// interface didn't connect this time — per Bryan, someone who
    /// already has a connection or RNode set up should never see this,
    /// regardless of whether it happened to work this particular launch.
    @Published var awaitingSetup = false
    /// Set by the setup wizard when it routes the user to a specific tab
    /// instead of adding a relay directly (e.g. "Set Up an RNode" or
    /// "Firmware Tools") — ContentView consumes this once, after startup
    /// finishes, to land on the right tab instead of the default.
    @Published var pendingPostSetupTab: AppTab?


    private let interfaceManager = InterfaceManager.shared


    func begin() {

        Task {

            await runSoftwareLaunching()
            await runFoundConnections()

            if interfaceManager.interfaces.isEmpty {
                awaitingSetup = true
                return
            }

            await runConnectingAndPreloadingTux()
            await finishStartup()
        }
    }


    /// After the wizard adds a relay: unlike the plain "skip" path, this
    /// actually retries connecting and preloading Tux with the connection
    /// that just got added, so a fresh IceNomad Public Relay setup still
    /// gets the instant-Tux-homepage experience on the very first launch
    /// instead of only from the second launch onward.
    func continueAfterAddingConnection() {

        awaitingSetup = false

        Task {
            await runConnectingAndPreloadingTux()
            await finishStartup()
        }
    }


    /// The wizard's plain "skip for now" / "I'll set this up myself" —
    /// no connection was added, so there's nothing to retry.
    func continueWithoutSetup(landingOn tab: AppTab? = nil) {

        awaitingSetup = false
        pendingPostSetupTab = tab

        Task {
            await finishStartup()
        }
    }


    private func runConnectingAndPreloadingTux() async {

        await runConnectingToNetwork()

        if interfaceManager.connectionStates.values.contains(true) {

            await runConnectionEstablished()
            await runReceivingAnnounces()
            await runPreloadingTux()
        }

        // If nothing connected, or Tux specifically didn't respond, this
        // just proceeds silently — Browser already falls back to its
        // original screen without a preload (see BrowserView.onAppear),
        // and the user already has some connection configured, so
        // there's nothing new to interrupt startup over here.
    }


    private func finishStartup() async {

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


    /// Fetches Tux's index page now (see TuxPreloadStore) so the Browser
    /// tab — Tux is its home page — shows content instantly on first
    /// visit instead of a network round-trip the user has to watch. A
    /// live connection got this far already (this stage only runs when
    /// one exists), so a failure here just means Tux specifically didn't
    /// respond this launch — Browser's own fallback (its original
    /// screen, see BrowserView.onAppear) already handles that silently,
    /// nothing to surface here.
    private func runPreloadingTux() async {

        TuxPreloadStore.shared.preload()

        await cycle(
            LoadingMessages.preloadingTux,
            to: 0.98,
            maxDuration: 12,
            until: { TuxPreloadStore.shared.content != nil || TuxPreloadStore.shared.failed }
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
