//
//  ReticulumManager.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation
import Combine

@MainActor
class ReticulumManager: ObservableObject {

    static let shared = ReticulumManager()

    @Published var interfaces: [String] = []
    @Published var isRunning = false

    private init() {}


    func start() {

        print("Starting Reticulum")

        loadInterfaces()

        isRunning = true
    }


    func stop() {

        print("Stopping Reticulum")

        isRunning = false
    }


    private func loadInterfaces() {

        let connections = ConnectionStorage.shared.load()

        for connection in connections {

            switch connection.type {

            case .tcpClient:

                print("Starting TCP:",
                      connection.address,
                      connection.port)


            case .rNode:

                print("Starting RNode:",
                      connection.name)

            }
        }
    }
}
