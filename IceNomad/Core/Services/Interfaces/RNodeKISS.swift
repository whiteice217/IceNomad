//
//  RNodeKISS.swift
//  IceNomad
//
//  KISS framing for talking to a real RNode device (over BLE or, later,
//  USB serial) — confirmed byte-for-byte against the actual RNode
//  firmware source (github.com/markqvist/RNode_Firmware, Framing.h +
//  RNode_Firmware.ino's serial_callback()), not approximated.
//
//  This is a DIFFERENT framing layer than PacketBuilder/PacketParser's
//  HDLC (0x7E) framing used for TCP — KISS interfaces carry the raw,
//  unframed Reticulum packet bytes directly inside a FEND(0xC0)-
//  delimited, FESC(0xDB)-escaped envelope prefixed with a one-byte
//  command. CMD_DATA(0x00) frames are packet data; the CMD_* config
//  commands set the radio's frequency/bandwidth/power/etc.
//

import Foundation


enum RNodeKISS {

    // MARK: - Framing bytes (Framing.h)

    static let fend: UInt8 = 0xC0
    static let fesc: UInt8 = 0xDB
    static let tfend: UInt8 = 0xDC
    static let tfesc: UInt8 = 0xDD


    // MARK: - Commands (Framing.h)

    enum Command: UInt8 {
        case data = 0x00
        case frequency = 0x01
        case bandwidth = 0x02
        case txPower = 0x03
        case spreadingFactor = 0x04
        case codingRate = 0x05
        case radioState = 0x06
        case radioLock = 0x07
        case detect = 0x08
        case ready = 0x0F
        case statRSSI = 0x23
        case statSNR = 0x24
        case statBattery = 0x27
        case dispIntensity = 0x45
        case dispBlank = 0x64
        case wifiMode = 0x6A
        case wifiSSID = 0x6B
        case wifiPSK = 0x6C
        case wifiIP = 0x84
        case wifiNM = 0x85
        case reset = 0x55
        case error = 0x90
    }

    static let radioStateOff: UInt8 = 0x00
    static let radioStateOn: UInt8 = 0x01
    static let radioStateQuery: UInt8 = 0xFF

    static let detectRequest: UInt8 = 0x73
    static let detectResponse: UInt8 = 0x46

    static let wifiModeOff: UInt8 = 0x00
    static let wifiModeStation: UInt8 = 0x01
    static let wifiModeAccessPoint: UInt8 = 0x02

    /// The confirmation byte CMD_RESET requires as its payload — a bare
    /// reset command with no payload (or the wrong byte) is ignored by
    /// the firmware on purpose, so a stray/malformed frame can't
    /// accidentally reboot the radio.
    static let resetConfirm: UInt8 = 0xF8

    /// Firmware's BATTERY_STATE_* values (Config.h) — sent unprompted in
    /// the CMD_STAT_BAT payload's first byte roughly every few seconds
    /// once the device's battery ADC has enough samples; not something
    /// the host has to poll for.
    enum BatteryState: UInt8 {
        case unknown = 0x00
        case discharging = 0x01
        case charging = 0x02
        case charged = 0x03
    }


    // MARK: - Encoding

    /// Escapes FEND/FESC bytes within a payload — every multi-byte KISS
    /// frame (CMD_DATA and the 4-byte frequency/bandwidth commands) needs
    /// this; single-byte commands (txpower, SF, CR, radio state) don't
    /// carry anything that could collide with a frame marker.
    private static func escape(_ payload: Data) -> Data {

        var result = Data()
        result.reserveCapacity(payload.count)

        for byte in payload {

            switch byte {
            case fend:
                result.append(fesc)
                result.append(tfend)
            case fesc:
                result.append(fesc)
                result.append(tfesc)
            default:
                result.append(byte)
            }
        }

        return result
    }


    /// Builds a complete KISS frame: FEND + command + escaped payload + FEND.
    static func frame(_ command: Command, payload: Data = Data()) -> Data {

        var frame = Data()
        frame.append(fend)
        frame.append(command.rawValue)
        frame.append(escape(payload))
        frame.append(fend)
        return frame
    }


    /// A raw outbound Reticulum packet, wrapped as a CMD_DATA frame.
    static func dataFrame(_ packet: Data) -> Data {
        frame(.data, payload: packet)
    }


    /// 4-byte big-endian value, for CMD_FREQUENCY / CMD_BANDWIDTH.
    static func frame(_ command: Command, uint32 value: UInt32) -> Data {

        let payload = Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])

        return frame(command, payload: payload)
    }


    /// Single-byte value, for CMD_TXPOWER / CMD_SF / CMD_CR / CMD_RADIO_STATE.
    static func frame(_ command: Command, byte value: UInt8) -> Data {
        frame(command, payload: Data([value]))
    }


    /// Raw 4 bytes in order, for CMD_WIFI_IP / CMD_WIFI_NM (an IPv4
    /// address/netmask, not a numeric value to byte-swap like uint32:).
    static func frame(_ command: Command, ipv4Bytes value: (UInt8, UInt8, UInt8, UInt8)) -> Data {
        frame(command, payload: Data([value.0, value.1, value.2, value.3]))
    }


    /// For CMD_WIFI_SSID / CMD_WIFI_PSK — confirmed against real firmware
    /// source (RNode_Firmware.ino): the handler watches for a trailing
    /// 0x00 byte *within* the payload itself as the "end of string"
    /// marker (it writes each byte to EEPROM as it streams in, then does
    /// a final pass on seeing 0x00), not just the closing KISS FEND. An
    /// empty string still needs the trailing 0x00 to actually clear/save.
    static func frame(_ command: Command, nulTerminatedString value: String) -> Data {
        frame(command, payload: Data(value.utf8) + Data([0x00]))
    }


    // MARK: - Decoding

    /// Accumulates raw bytes from the BLE TX characteristic's
    /// notifications (which arrive in arbitrary-sized chunks with no
    /// relation to KISS frame boundaries) and extracts complete frames.
    final class FrameParser {

        private var buffer = Data()

        /// Fires once per complete frame: (command, unescaped payload).
        var onFrame: ((UInt8, Data) -> Void)?

        func receive(_ data: Data) {

            buffer.append(data)
            extractFrames()
        }

        private func extractFrames() {

            while true {

                guard let start = buffer.firstIndex(of: RNodeKISS.fend) else {
                    buffer.removeAll()
                    return
                }

                let leading = buffer.distance(from: buffer.startIndex, to: start)
                if leading > 0 {
                    buffer.removeFirst(leading)
                }

                // Skip past consecutive/empty FENDs (KISS frames are
                // opened AND closed by FEND, so an idle line looks like
                // a run of them).
                while buffer.count > 1, buffer[buffer.index(after: buffer.startIndex)] == RNodeKISS.fend {
                    buffer.removeFirst()
                }

                guard buffer.count >= 2 else {
                    return
                }

                var scan = buffer.index(buffer.startIndex, offsetBy: 1)
                var end: Data.Index?

                while scan < buffer.endIndex {

                    if buffer[scan] == RNodeKISS.fend {
                        end = scan
                        break
                    }

                    scan = buffer.index(after: scan)
                }

                guard let frameEnd = end else {
                    // Wait for more data.
                    return
                }

                let commandAndPayload = buffer[buffer.index(after: buffer.startIndex)..<frameEnd]
                let consumed = buffer.distance(from: buffer.startIndex, to: frameEnd) + 1
                buffer.removeFirst(consumed)

                guard let command = commandAndPayload.first else {
                    continue
                }

                let escapedPayload = Data(commandAndPayload.dropFirst())
                let payload = RNodeKISS.unescape(escapedPayload)

                onFrame?(command, payload)
            }
        }
    }


    fileprivate static func unescape(_ data: Data) -> Data {

        var result = Data()
        result.reserveCapacity(data.count)

        var i = data.startIndex

        while i < data.endIndex {

            let byte = data[i]

            if byte == fesc {

                let next = data.index(after: i)

                guard next < data.endIndex else {
                    break
                }

                switch data[next] {
                case tfend: result.append(fend)
                case tfesc: result.append(fesc)
                default: result.append(data[next])
                }

                i = data.index(after: next)

            } else {

                result.append(byte)
                i = data.index(after: i)
            }
        }

        return result
    }
}
