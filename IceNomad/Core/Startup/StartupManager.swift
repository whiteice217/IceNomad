//
//  StartupManager.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/8/26.
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


    private let steps: [StartupStep] = [

        StartupStep(progress: 0.05),
        StartupStep(progress: 0.15),
        StartupStep(progress: 0.25),
        StartupStep(progress: 0.40),
        StartupStep(progress: 0.55),
        StartupStep(progress: 0.70),
        StartupStep(progress: 0.85),
        StartupStep(progress: 1.00)

    ]


    func begin() {

        Task {

            for step in steps {

                await runStep(step)

            }


            withAnimation {

                progress = 1.0
                message = "The penguin has found the signal!"

            }


            // Trigger NOOT NOOT
            playCompletionSound = true


            try? await Task.sleep(
                nanoseconds: 1_000_000_000
            )


            finished = true

        }
    }


    private func runStep(_ step: StartupStep) async {


        withAnimation(.easeInOut(duration: 0.5)) {

            progress = step.progress
            message = LoadingMessages.random()

        }


        // Time user has to read message
        try? await Task.sleep(
            nanoseconds: 1_800_000_000
        )

    }

}
