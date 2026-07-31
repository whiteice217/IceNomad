//
//  RNodeInterface.swift
//  IceNomad
//
//  A real RNode connection over either Bluetooth LE or WiFi: connects
//  via the configured transport, pushes the configured radio parameters
//  over KISS command frames, brings the radio up, then passes CMD_DATA
//  frames through as plain Reticulum packets — same shape
//  InterfaceManager already expects from TCPClient.
//
//  RNode Firmware speaks the exact same KISS command protocol over BLE
//  and WiFi (confirmed in firmware source — same command parser, just a
//  different byte pipe underneath: BLE characteristic notify/write vs. a
//  raw TCP socket on port 7633), so only the transport needs to change
//  between the two — RNodeKISS's framing/parsing is shared as-is.
//

import Foundation
import OSLog


class RNodeInterface: ReticulumInterface {


    let name: String

    let config: RNodeConfig


    var isConnected: Bool = false

    var bytesReceived: Int = 0

    var bytesSent: Int = 0

    var onReceive: ((Data) -> Void)?

    var onStatusChanged: ((Bool) -> Void)?


    private let ble = RNodeBLEManager.shared
    private var wifi: TCPClient?
    private let kiss = RNodeKISS.FrameParser()
    private var radioConfigured = false


    init(config: RNodeConfig) {

        self.name = config.name
        self.config = config
    }



    func start() {

        Log.network.info("Starting RNode interface \(self.name, privacy: .public) over \(self.config.connectionMethod.rawValue, privacy: .public), frequency \(self.config.frequencyHzString, privacy: .public)")

        radioConfigured = false

        kiss.onFrame = { [weak self] command, payload in
            self?.handleFrame(command: command, payload: payload)
        }

        switch config.connectionMethod {

        case .bluetooth:

            guard let identifier = UUID(uuidString: config.peripheralIdentifier) else {
                Log.network.error("RNode \(self.name, privacy: .public) has no paired device — pair one from the connection's settings first")
                return
            }

            ble.onReceive = { [weak self] data in
                self?.bytesReceived += data.count
                self?.kiss.receive(data)
            }

            ble.onConnectionStateChanged = { [weak self] connected in
                self?.handleTransportStateChanged(connected)
            }

            ble.connect(identifier: identifier)

        case .wifi:

            guard !config.wifiHost.isEmpty else {
                Log.network.error("RNode \(self.name, privacy: .public) has no WiFi host configured")
                return
            }

            let client = TCPClient(name: name, address: config.wifiHost, port: config.wifiPort)

            client.onReceive = { [weak self] data in
                self?.bytesReceived += data.count
                self?.kiss.receive(data)
            }

            client.onStatusChanged = { [weak self] connected in
                self?.handleTransportStateChanged(connected)
            }

            wifi = client
            client.start()
        }
    }



    func stop() {

        Log.network.info("Stopping RNode interface \(self.name, privacy: .public)")

        switch config.connectionMethod {
        case .bluetooth: ble.disconnect()
        case .wifi: wifi?.stop(); wifi = nil
        }

        isConnected = false
        radioConfigured = false
        onStatusChanged?(false)
    }



    func send(data: Data) {

        guard isConnected else {
            Log.network.error("RNode \(self.name, privacy: .public) not connected — dropped an outbound packet")
            return
        }

        let frame = RNodeKISS.dataFrame(data)

        bytesSent += data.count
        sendRaw(frame)
    }


    private func sendRaw(_ data: Data) {

        switch config.connectionMethod {
        case .bluetooth: ble.send(data)
        case .wifi: wifi?.send(data: data)
        }
    }


    private func handleTransportStateChanged(_ connected: Bool) {

        if connected {
            configureRadio()
        } else {
            isConnected = false
            radioConfigured = false
            onStatusChanged?(false)
        }
    }


    // MARK: - Radio bring-up

    /// Pushes the configured radio parameters, then brings the radio
    /// online — matches the sequence real RNode clients (rnodeconf,
    /// Sideband) use: set the physical-layer parameters first, then
    /// CMD_RADIO_STATE=on last.
    private func configureRadio() {

        sendRaw(RNodeKISS.frame(.frequency, uint32: config.frequencyHz))
        sendRaw(RNodeKISS.frame(.bandwidth, uint32: config.bandwidthHz))
        sendRaw(RNodeKISS.frame(.txPower, byte: config.transmitPowerByte))
        sendRaw(RNodeKISS.frame(.spreadingFactor, byte: config.spreadingFactorByte))
        sendRaw(RNodeKISS.frame(.codingRate, byte: config.codingRateByte))
        sendRaw(RNodeKISS.frame(.radioState, byte: RNodeKISS.radioStateOn))

        // The device doesn't ACK each config command individually in a
        // way worth blocking on — give it a moment to apply them, then
        // consider the interface up. Real errors surface via CMD_ERROR
        // frames, handled in handleFrame below.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in

            guard let self, !self.radioConfigured else {
                return
            }

            self.radioConfigured = true
            self.isConnected = true
            self.onStatusChanged?(true)
        }
    }


    private func handleFrame(command: UInt8, payload: Data) {

        switch RNodeKISS.Command(rawValue: command) {

        case .data:
            onReceive?(payload)

        case .error:
            let code = payload.first ?? 0
            Log.network.error("RNode \(self.name, privacy: .public) reported hardware error, code \(String(format: "0x%02X", code), privacy: .public)")

        default:
            break
        }
    }
}
