//
//  RNodeSerialTransport.swift
//  IceNomad
//
//  USB-serial transport for RNodeInterface — Mac Catalyst only, same
//  restriction as Firmware Tools (iOS doesn't allow raw serial device
//  access to third-party apps without MFi certification). Wraps
//  ESP32SerialPort's raw POSIX open/read/write in an always-on read
//  loop, matching the onReceive/onStatusChanged callback shape
//  TCPClient and RNodeBLEManager already use so RNodeInterface can
//  treat all three transports identically.
//

#if targetEnvironment(macCatalyst)

import Foundation
import OSLog

final class RNodeSerialTransport {

    let path: String

    var onReceive: ((Data) -> Void)?
    var onStatusChanged: ((Bool) -> Void)?

    private var serial: ESP32SerialPort?
    private var shouldRun = false
    private let readQueue = DispatchQueue(label: "com.saltycapn.icenomad.rnode-serial-read")


    init(path: String) {
        self.path = path
    }


    func start() {

        let port = ESP32SerialPort(path: path)

        do {
            try port.open()
        } catch {

            Log.network.error("RNode serial \(self.path, privacy: .public) failed to open: \(String(describing: error), privacy: .public)")
            onStatusChanged?(false)
            return
        }

        serial = port
        shouldRun = true

        Log.network.info("RNode serial \(self.path, privacy: .public) opened")

        readQueue.async { [weak self] in
            self?.readLoop()
        }

        // Opening the port pulses DTR, which on the Heltec V3 (and most
        // ESP32 dev boards) is wired to the reset line — confirmed via a
        // live test against real hardware: the board's ROM boot banner
        // came back over the same UART immediately after open(), the
        // same reset esptool relies on for flashing. RNodeInterface
        // sends its radio config commands (frequency/bandwidth/etc.) as
        // soon as onStatusChanged fires true; sending those into the
        // reboot window would just be lost, since the running firmware
        // isn't listening on the UART yet. Give the board a couple
        // seconds to finish rebooting before considering the transport
        // actually up. (The KISS FrameParser already tolerates the ROM
        // boot banner arriving on the read loop meanwhile — it has no
        // real FEND framing, so it's silently discarded as noise.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in

            guard let self, self.shouldRun else {
                return
            }

            self.onStatusChanged?(true)
        }
    }


    func stop() {

        shouldRun = false
        serial?.close()
        serial = nil
        onStatusChanged?(false)
    }


    func send(data: Data) {

        do {
            try serial?.write(data)
        } catch {
            Log.network.error("RNode serial \(self.path, privacy: .public) write failed: \(String(describing: error), privacy: .public)")
        }
    }


    /// ESP32SerialPort.read() blocks per VMIN/VTIME (~1s of silence ends
    /// a read, returning empty Data rather than throwing) — looping it
    /// on a dedicated background queue gives an always-listening byte
    /// stream without polling or a busy-wait.
    private func readLoop() {

        while shouldRun {

            guard let serial else {
                break
            }

            let data = serial.read(maxLength: 1024)

            if !data.isEmpty {
                onReceive?(data)
            }
        }
    }
}

#endif
