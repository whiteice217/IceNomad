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


    private let interfaceManager = InterfaceManager()


    private init() {}



    func start() {

        guard !isRunning else {
            return
        }


        print("Starting Reticulum")


        interfaceManager.loadInterfaces()


        interfaceManager.startAll()


        interfaces = interfaceManager.interfaces.map {
            $0.name
        }


        isRunning = true
    }



    func stop() {


        print("Stopping Reticulum")


        interfaceManager.stopAll()


        interfaces.removeAll()


        isRunning = false
    }
}
