//
//  TCPClient.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/8/26.
//

import Foundation
import Network
import OSLog


class TCPClient: ReticulumInterface {


    let name: String
    let address: String
    let port: String


    var isConnected: Bool = false

    var bytesReceived: Int = 0
    var bytesSent: Int = 0


    private var connection: NWConnection?

    private var shouldReconnect = true
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?


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

        Log.network.info("Starting TCP client \(self.name, privacy: .public) — \(self.address, privacy: .public):\(self.port, privacy: .public)")

        shouldReconnect = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil


        guard let tcpPort = NWEndpoint.Port(port) else {

            Log.network.error("TCP client \(self.name, privacy: .public): invalid port \(self.port, privacy: .public)")
            return
        }


        // Explicit TCP options with Nagle's algorithm disabled — the
        // default NWParameters.tcp leaves it on, which can buffer and
        // coalesce small packets (like our control packets: path
        // requests, link requests) before they hit the wire. Reticulum's
        // own reference clients don't wait around for that; every packet
        // should go out immediately.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)

        connection = NWConnection(
            host: NWEndpoint.Host(address),
            port: tcpPort,
            using: parameters
        )


        connection?.stateUpdateHandler = { [weak self] state in

            guard let self else {
                return
            }


            switch state {


            case .ready:

                Log.network.info("TCP client \(self.name, privacy: .public) connected")

                self.reconnectAttempt = 0
                self.isConnected = true
                self.onStatusChanged?(true)

                self.receiveLoop()


            case .failed(let error):

                Log.network.error("TCP client \(self.name, privacy: .public) failed: \(error)")

                self.isConnected = false
                self.onStatusChanged?(false)
                self.scheduleReconnect()


            case .cancelled:

                Log.network.notice("TCP client \(self.name, privacy: .public) cancelled")

                self.isConnected = false
                self.onStatusChanged?(false)


            default:

                break
            }
        }


        connection?.start(
            queue: .global()
        )
    }



    func stop() {

        Log.network.info("Stopping TCP client \(self.name, privacy: .public)")

        shouldReconnect = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        connection?.cancel()
        connection = nil

        isConnected = false
        onStatusChanged?(false)
    }


    /// Reconnects after a dropped connection with a capped exponential
    /// backoff — Network.framework doesn't retry TCP for us, and without
    /// this a single hiccup (idle timeout, network switch, server-side
    /// close) would silently kill the interface for the rest of the app's
    /// lifetime, with no further announces or messages ever arriving.
    private func scheduleReconnect() {

        guard shouldReconnect else {
            return
        }

        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)

        Log.network.notice("TCP client \(self.name, privacy: .public) reconnecting in \(delay)s (attempt \(self.reconnectAttempt))")

        let workItem = DispatchWorkItem { [weak self] in
            self?.start()
        }

        reconnectWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: workItem)
    }



    func send(data: Data) {

        guard let connection else {

            Log.network.error("TCP client \(self.name, privacy: .public): send attempted with no live connection — packet dropped")
            return
        }


        bytesSent += data.count


        connection.send(
            content: data,
            completion: .contentProcessed { [weak self] error in

                if let error, let self {
                    Log.network.error("TCP client \(self.name, privacy: .public) send error: \(error)")
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
                self.onReceive?(data)
            }


            if let error {

                Log.network.error("TCP client \(self.name, privacy: .public) receive error: \(error)")
                return
            }


            if !complete {

                self.receiveLoop()
            }
        }
    }
}
