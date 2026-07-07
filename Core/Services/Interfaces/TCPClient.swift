//
//  TCPClient.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation


class TCPClient: ReticulumInterface {


    let name: String

    let address: String

    let port: String


    private(set) var isConnected: Bool = false


    init(name: String,
         address: String,
         port: String) {

        self.name = name
        self.address = address
        self.port = port
    }



    func start() {

        print("Starting TCP Client")
        print("Address:", address)
        print("Port:", port)


        // Socket connection will go here later

        isConnected = true
    }



    func stop() {

        print("Stopping TCP Client")

        isConnected = false
    }



    func send(data: Data) {

        print("Sending TCP data:",
              data.count,
              "bytes")
    }
}
