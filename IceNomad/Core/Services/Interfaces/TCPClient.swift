//
//  TCPClient.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/8/26.
//

import Foundation
import Network


class TCPClient: ReticulumInterface {


    let name: String
    let address: String
    let port: String


    var isConnected: Bool = false

    var bytesReceived: Int = 0
    var bytesSent: Int = 0


    private var connection: NWConnection?


    var onReceive: ((Data) -> Void)?

    var onStatusChanged: ((Bool) -> Void)?


    init(
        name: String,
        address: String,
        port: String
    ) {

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

            guard let self else {
                return
            }


            switch state {


            case .ready:

                print("🟢 TCP connected")

                self.isConnected = true

                self.receiveLoop()


            case .failed(let error):

                print("🔴 TCP failed:")
                print(error)

                self.isConnected = false


            case .cancelled:

                print("🔴 TCP cancelled")

                self.isConnected = false


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
        connection = nil

        isConnected = false
    }



    func send(data: Data) {

        guard let connection else {

            print("TCP not available")
            return
        }


        bytesSent += data.count


        connection.send(
            content: data,
            completion: .contentProcessed { error in

                if let error {

                    print("TCP send error:")
                    print(error)

                }
                else {

                    print(
                        "📤 TCP sent:",
                        data.count,
                        "bytes"
                    )
                }
            }
        )
    }




    private func receiveLoop() {

        connection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, complete, error in


            guard let self else {
                return
            }


            if let data, !data.isEmpty {

                self.bytesReceived += data.count


                print(
                    "📥 TCP received:",
                    data.count,
                    "bytes"
                )


                self.onReceive?(data)
            }


            if let error {

                print("TCP receive error:")
                print(error)

                return
            }


            if !complete {

                self.receiveLoop()
            }
        }
    }
}
