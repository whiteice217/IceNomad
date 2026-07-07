//
//  InterfaceManager.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation
import Combine

class InterfaceManager: ObservableObject {

    @Published private(set) var interfaces: [ReticulumInterface] = []
    @Published var connectionStates: [String: Bool] = [:]

    // MARK: - Load Interfaces

    func loadInterfaces() {

        // Remove existing interfaces
        interfaces.removeAll()


        let connections = ConnectionStorage.shared.load()


        for connection in connections {

            switch connection.type {


            case .tcpClient:

                let tcp = TCPClient(
                    name: connection.name,
                    address: connection.address,
                    port: connection.port
                )

                tcp.onStatusChanged = { [weak self, weak tcp] connected in

                    DispatchQueue.main.async {

                        if let name = tcp?.name {

                            self?.connectionStates[name] = connected

                            print(
                                name,
                                "status changed:",
                                connected
                            )
                        }
                    }
                }

                interfaces.append(tcp)



            case .rNode:

                if let config = connection.rnodeConfig {

                    let rnode = RNodeInterface(
                        config: config
                    )

                    interfaces.append(rnode)
                }
            }
        }


        print("Loaded interfaces:", interfaces.count)
    }



    // MARK: - Start Interfaces

    func startAll() {

        for interface in interfaces {

            print("Starting interface:", interface.name)

            interface.start()


            print(
                interface.name,
                "connected:",
                interface.isConnected
            )
        }
    }



    // MARK: - Stop Interfaces

    func stopAll() {

        for interface in interfaces {

            print("Stopping interface:", interface.name)

            interface.stop()
        }
    }
}
