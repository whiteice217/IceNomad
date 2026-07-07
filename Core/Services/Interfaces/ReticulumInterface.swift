//
//  ReticulumInterface.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation


protocol ReticulumInterface {

    var name: String { get }

    var isConnected: Bool { get }

    func start()

    func stop()

    func send(data: Data)

}
