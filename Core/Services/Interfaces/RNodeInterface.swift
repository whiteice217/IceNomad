//
//  RNodeInterface.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation


class RNodeInterface: ReticulumInterface {


    let name: String

    let config: RNodeConfig


    private(set) var isConnected: Bool = false



    init(config: RNodeConfig) {

        self.name = config.name
        self.config = config
    }



    func start() {

        print("Starting RNode")

        print("Frequency:",
              config.frequencyHzString)


        isConnected = true
    }



    func stop() {

        print("Stopping RNode")

        isConnected = false
    }



    func send(data: Data) {

        print("Sending RNode packet:",
              data.count,
              "bytes")
    }
}
