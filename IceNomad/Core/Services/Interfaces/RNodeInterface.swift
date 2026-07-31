//
//  RNodeInterface.swift
//  IceNomad
//
//  A real RNode connection over Bluetooth LE: connects to the paired
//  peripheral, pushes the configured radio parameters over KISS command
//  frames, brings the radio up, then passes CMD_DATA frames through as
//  plain Reticulum packets — same shape InterfaceManager already
//  expects from TCPClient.
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
    private let kiss = RNodeKISS.FrameParser()
    private var radioConfigured = false


    init(config: RNodeConfig) {

        self.name = config.name
        self.config = config
    }



    func start() {

        Log.network.info("Starting RNode interface \(self.name, privacy: .public), frequency \(self.config.frequencyHzString, privacy: .public)")

        guard let identifier = UUID(uuidString: config.peripheralIdentifier) else {
            Log.network.error("RNode \(self.name, privacy: .public) has no paired device — pair one from the connection's settings first")
            return
        }

        radioConfigured = false

        kiss.onFrame = { [weak self] command, payload in
            self?.handleFrame(command: command, payload: payload)
        }

        ble.onReceive = { [weak self] data in
            self?.bytesReceived += data.count
            self?.kiss.receive(data)
        }

        ble.onConnectionStateChanged = { [weak self] connected in

            guard let self else {
                return
            }

            if connected {
                self.configureRadio()
            } else {
                self.isConnected = false
                self.radioConfigured = false
                self.onStatusChanged?(false)
            }
        }

        ble.connect(identifier: identifier)
    }



    func stop() {

        Log.network.info("Stopping RNode interface \(self.name, privacy: .public)")

        ble.disconnect()

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
        ble.send(frame)
    }


    // MARK: - Radio bring-up

    /// Pushes the configured radio parameters, then brings the radio
    /// online — matches the sequence real RNode clients (rnodeconf,
    /// Sideband) use: set the physical-layer parameters first, then
    /// CMD_RADIO_STATE=on last.
    private func configureRadio() {

        ble.send(RNodeKISS.frame(.frequency, uint32: config.frequencyHz))
        ble.send(RNodeKISS.frame(.bandwidth, uint32: config.bandwidthHz))
        ble.send(RNodeKISS.frame(.txPower, byte: config.transmitPowerByte))
        ble.send(RNodeKISS.frame(.spreadingFactor, byte: config.spreadingFactorByte))
        ble.send(RNodeKISS.frame(.codingRate, byte: config.codingRateByte))
        ble.send(RNodeKISS.frame(.radioState, byte: RNodeKISS.radioStateOn))

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
