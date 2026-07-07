//
//  TCPClient.swift
//  IceNomad
//

import Foundation
import Network


class TCPClient: ReticulumInterface {


    let name: String
    let address: String
    let port: String


    private(set) var isConnected: Bool = false


    private var connection: NWConnection?
    
    var onStatusChanged: ((Bool) -> Void)?


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


        guard let tcpPort = NWEndpoint.Port(port) else {

            print("Invalid TCP port")
            return
        }


        connection = NWConnection(
            host: NWEndpoint.Host(address),
            port: tcpPort,
            using: .tcp
        )


        connection?.stateUpdateHandler = { [weak self] state in

            switch state {

            case .ready:

                print("TCP connection established")

                self?.isConnected = true
                self?.onStatusChanged?(true)
                
            case .failed(let error):

                print("TCP connection failed:")
                print(error)

                self?.isConnected = false
                self?.onStatusChanged?(false)
                
            case .waiting(let error):

                print("TCP waiting:")
                print(error)


            case .cancelled:

                print("TCP cancelled")

                self?.isConnected = false
                self?.onStatusChanged?(false)
                
            default:
                break
            }

        }


        connection?.start(
            queue: .global()
        )

    }



    func stop() {

        print("Stopping TCP Client")

        connection?.cancel()

        isConnected = false
    }



    func send(data: Data) {

        guard let connection else {

            print("No TCP connection")
            return
        }


        connection.send(
            content: data,
            completion: .contentProcessed { error in

                if let error {

                    print("TCP send error:")
                    print(error)

                }
                else {

                    print("TCP data sent:",
                          data.count,
                          "bytes")

                }
            }
        )
    }

}
