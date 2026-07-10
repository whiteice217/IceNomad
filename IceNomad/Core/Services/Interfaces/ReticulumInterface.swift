//
//  ReticulumInterface.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation


protocol ReticulumInterface {

    // Interface name shown in the app
    var name: String { get }

    // Current interface state
    var isConnected: Bool { get }


    // Traffic statistics
    var bytesReceived: Int { get }
    var bytesSent: Int { get }


    // Called when raw Reticulum data is received
    var onReceive: ((Data) -> Void)? { get set }


    // Start interface
    func start()


    // Stop interface
    func stop()


    // Send raw Reticulum data
    func send(data: Data)

}
