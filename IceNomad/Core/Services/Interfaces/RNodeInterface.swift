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


    var isConnected: Bool = false
    
    var bytesReceived: Int=0
    
    var bytesSent: Int=0

    var onReceive: ((Data) -> Void)?

    var onStatusChanged: ((Bool) -> Void)?


    init(config: RNodeConfig) {

        self.name = config.name
        self.config = config
    }



    func start() {

        print("Starting RNode")

        print("Frequency:",
              config.frequencyHzString)


        isConnected = true
        onStatusChanged?(true)
    }



    func stop() {

        print("Stopping RNode")

        isConnected = false
        onStatusChanged?(false)
    }



    func send(data: Data) {

        print("Sending RNode packet:",
              data.count,
              "bytes")
    }
}
