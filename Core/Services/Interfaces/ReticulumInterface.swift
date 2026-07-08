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

    // Current connection status
    var isConnected: Bool { get }


    // Called when raw Reticulum data is received
    // Optional because not every interface may need a listener immediately
    var onReceive: ((Data) -> Void)? { get set }


    // Start interface
    func start()


    // Stop interface
    func stop()


    // Send raw data
    func send(data: Data)

}
