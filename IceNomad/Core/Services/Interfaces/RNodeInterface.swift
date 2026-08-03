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


/// A snapshot of the device's last CMD_STAT_BAT push — see
/// InterfaceManager.rnodeBatteryStatus for how the UI observes this.
struct RNodeBatteryStatus {
    var state: RNodeKISS.BatteryState
    var percent: UInt8
}


class RNodeInterface: ReticulumInterface {


    let name: String

    let config: RNodeConfig


    var isConnected: Bool = false

    var bytesReceived: Int = 0

    var bytesSent: Int = 0

    var onReceive: ((Data) -> Void)?

    var onStatusChanged: ((Bool) -> Void)?

    /// Fires on every unsolicited CMD_STAT_BAT push — the firmware sends
    /// this on its own roughly every few seconds once it has enough ADC
    /// samples, not something we poll for.
    var onBatteryUpdate: ((RNodeKISS.BatteryState, UInt8) -> Void)?


    private let ble = RNodeBLEManager.shared
    private var wifi: TCPClient?
    #if targetEnvironment(macCatalyst)
    private var usbSerial: RNodeSerialTransport?
    #endif
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

        case .usb:

            #if targetEnvironment(macCatalyst)
            guard !config.usbSerialPath.isEmpty else {
                Log.network.error("RNode \(self.name, privacy: .public) has no USB serial port configured")
                return
            }

            let transport = RNodeSerialTransport(path: config.usbSerialPath)

            transport.onReceive = { [weak self] data in
                self?.bytesReceived += data.count
                self?.kiss.receive(data)
            }

            transport.onStatusChanged = { [weak self] connected in
                self?.handleTransportStateChanged(connected)
            }

            usbSerial = transport
            transport.start()
            #else
            Log.network.error("RNode \(self.name, privacy: .public): USB serial isn't available on iOS")
            #endif

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
        case .usb:
            #if targetEnvironment(macCatalyst)
            usbSerial?.stop(); usbSerial = nil
            #endif
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
        case .usb:
            #if targetEnvironment(macCatalyst)
            usbSerial?.send(data: data)
            #endif
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

        case .statBattery:

            guard payload.count >= 2,
                  let state = RNodeKISS.BatteryState(rawValue: payload[payload.startIndex])
            else {
                return
            }

            let percent = payload[payload.index(after: payload.startIndex)]
            onBatteryUpdate?(state, percent)

        case .error:
            let code = payload.first ?? 0
            Log.network.error("RNode \(self.name, privacy: .public) reported hardware error, code \(String(format: "0x%02X", code), privacy: .public)")

        default:
            break
        }
    }


    // MARK: - Device controls

    /// Reboots the physical board — same CMD_RESET + confirmation-byte
    /// sequence real RNode clients use. The device doesn't ack this; the
    /// transport will simply report disconnected a moment later as the
    /// board goes down, then (for USB/WiFi) reconnect on its own once
    /// it's back up.
    func reboot() {

        sendRaw(RNodeKISS.frame(.reset, byte: RNodeKISS.resetConfirm))
    }


    /// 0 turns the display off; any other value sets brightness and
    /// turns it back on immediately if it was blanked.
    func setDisplayIntensity(_ value: UInt8) {

        sendRaw(RNodeKISS.frame(.dispIntensity, byte: value))
    }


    /// Seconds of inactivity before the display auto-blanks; 0 disables
    /// blanking entirely (always on).
    func setDisplayBlankTimeout(seconds: UInt8) {

        sendRaw(RNodeKISS.frame(.dispBlank, byte: seconds))
    }


    func setWiFiMode(_ mode: UInt8) {

        sendRaw(RNodeKISS.frame(.wifiMode, byte: mode))
    }


    func setWiFiSSID(_ ssid: String) {

        sendRaw(RNodeKISS.frame(.wifiSSID, nulTerminatedString: ssid))
    }


    func setWiFiPassword(_ psk: String) {

        sendRaw(RNodeKISS.frame(.wifiPSK, nulTerminatedString: psk))
    }


    /// Static IP for **station** mode only — access-point mode's IP is
    /// hardcoded to 10.0.0.1 by the firmware itself and isn't
    /// configurable (confirmed in Remote.h's wifi_remote_start_ap()).
    func setWiFiStaticIP(_ ip: (UInt8, UInt8, UInt8, UInt8), netmask: (UInt8, UInt8, UInt8, UInt8)) {

        sendRaw(RNodeKISS.frame(.wifiIP, ipv4Bytes: ip))
        sendRaw(RNodeKISS.frame(.wifiNM, ipv4Bytes: netmask))
    }
}
