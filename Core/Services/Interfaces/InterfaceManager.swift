//
//  InterfaceManager.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation


class InterfaceManager {


    private(set) var interfaces: [ReticulumInterface] = []



    func loadInterfaces() {

        // Clear old interfaces
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
    }



    func startAll() {


        for interface in interfaces {

            print("Starting interface:", interface.name)

            interface.start()
        }
    }



    func stopAll() {


        for interface in interfaces {

            print("Stopping interface:", interface.name)

            interface.stop()
        }
    }
}
