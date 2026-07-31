//
//  ReticulumManager.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation
import Combine
import OSLog


@MainActor
class ReticulumManager: ObservableObject {


    static let shared = ReticulumManager()


    @Published var interfaces: [String] = []

    @Published var isRunning = false


    private let interfaceManager = InterfaceManager()


    private init() {}



    func start() {

        guard !isRunning else {
            return
        }


        Log.reticulum.notice("Starting Reticulum")


        interfaceManager.loadInterfaces()


        interfaceManager.startAll()


        interfaces = interfaceManager.interfaces.map {
            $0.name
        }


        isRunning = true
    }



    func stop() {


        Log.reticulum.notice("Stopping Reticulum")


        interfaceManager.stopAll()


        interfaces.removeAll()


        isRunning = false
    }
}
