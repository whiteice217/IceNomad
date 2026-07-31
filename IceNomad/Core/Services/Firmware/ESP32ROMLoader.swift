//
//  ESP32ROMLoader.swift
//  IceNomad
//
//  Talks the real ESP32 ROM bootloader protocol — SLIP framing, command/
//  response packet shape, and the SYNC handshake — ported directly from
//  real esptool 5.3.1 source (esptool/loader.py), not reconstructed from
//  memory, since a wrong checksum constant or packet layout either does
//  nothing or hangs waiting for a response that will never come the
//  shape it expects.
//
//  Scope for now: SYNC only (detect a board and confirm it's alive and
//  in bootloader mode). FLASH_BEGIN/FLASH_DATA/FLASH_END (the actual
//  write path) reuses this same command()/SLIP layer when built — it
//  isn't implemented yet, on purpose: writing needs a real compiled
//  firmware image and carries real risk to whatever's currently on the
//  board, so it's a deliberately separate next step, not bundled in
//  with "can we talk to this board at all."
//

#if targetEnvironment(macCatalyst)

import Foundation

enum ESP32ROMError: Error {
    case notConnected
    case syncFailed
    case malformedResponse
}

final class ESP32ROMLoader {

    // MARK: - Protocol constants (exact values from esptool/loader.py)

    private enum Command {
        static let sync: UInt8 = 0x08
        static let readReg: UInt8 = 0x0A
    }

    private static let checksumMagic: UInt8 = 0xEF
    private static let chipDetectMagicRegAddr: UInt32 = 0x4000_1000

    /// `\x07\x07\x12\x20` + 32×`\x55` — esptool's exact SYNC payload.
    private static let syncPayload: Data = {
        var payload = Data([0x07, 0x07, 0x12, 0x20])
        payload.append(Data(repeating: 0x55, count: 32))
        return payload
    }()


    private let port: ESP32SerialPort

    init(port: ESP32SerialPort) {
        self.port = port
    }


    // MARK: - Connect

    /// Resets the board into the ROM bootloader and confirms it's
    /// actually responding — real esptool retries the reset+sync a
    /// couple of times before giving up, since the very first attempt
    /// sometimes lands mid-boot-chatter.
    func connect() throws {

        guard port.isOpen else {
            throw ESP32ROMError.notConnected
        }

        for _ in 0..<3 {

            port.resetIntoBootloader()
            drainBootBanner()

            if (try? sync()) != nil {
                return
            }
        }

        throw ESP32ROMError.syncFailed
    }


    /// The ROM bootloader prints a plain-text banner ("ESP-ROM:...
    /// waiting for download") right after reset, before it's actually
    /// ready to answer SYNC — sending SYNC immediately races that
    /// banner still arriving and silently loses (confirmed live: SYNC
    /// consistently failed until this drain step was added, verified
    /// working against a real connected Heltec V3 afterward). Reads and
    /// discards until the line goes quiet for a beat.
    private func drainBootBanner() {

        var quietStreak = 0

        while quietStreak < 3 {

            if port.read(maxLength: 512).isEmpty {
                quietStreak += 1
            } else {
                quietStreak = 0
            }
        }
    }


    /// Reads the chip-detect magic register — useful as a second,
    /// independent confirmation that we're really talking to a live
    /// ESP32-family ROM bootloader, beyond just "sync responded."
    func readChipDetectMagic() throws -> UInt32 {

        let response = try command(op: Command.readReg, data: Self.uint32LE(Self.chipDetectMagicRegAddr))
        return response.val
    }


    // MARK: - SYNC

    private func sync() throws {

        _ = try command(op: Command.sync, data: Self.syncPayload, timeout: 0.15)

        // Real ROM bootloaders reply to SYNC with a flood of near-
        // identical acks (up to ~8) — esptool drains these by issuing a
        // few more blank reads rather than treating the first response
        // as the end of the handshake.
        for _ in 0..<7 {
            _ = try? command(op: nil, data: Data(), timeout: 0.05)
        }
    }


    // MARK: - Command / response (matches esptool's ESPLoader.command exactly)

    private struct Response {
        let val: UInt32
        let data: Data
    }

    @discardableResult
    private func command(op: UInt8?, data: Data, chk: UInt32 = 0, timeout: TimeInterval = 1.0) throws -> Response {

        if let op {

            var packet = Data()
            packet.append(0x00)
            packet.append(op)
            packet.append(Self.uint16LE(UInt16(data.count)))
            packet.append(Self.uint32LE(chk))
            packet.append(data)

            try port.write(slipEncode(packet))
        }

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()

        while Date() < deadline {

            buffer.append(port.read())

            guard let frame = extractSlipFrame(from: &buffer) else {
                continue
            }

            guard frame.count >= 8 else {
                continue
            }

            let resp = frame[frame.startIndex]

            guard resp == 0x01 else {
                continue
            }

            let opRet = frame[frame.startIndex + 1]
            let lenRet = UInt16(frame[frame.startIndex + 2]) | (UInt16(frame[frame.startIndex + 3]) << 8)
            let val = Self.readUInt32LE(frame, at: frame.startIndex + 4)
            let payload = Data(frame.suffix(from: frame.startIndex + 8).prefix(Int(lenRet)))

            if op == nil || opRet == op {
                return Response(val: val, data: payload)
            }
        }

        throw ESP32ROMError.malformedResponse
    }


    // MARK: - SLIP framing (matches esptool's write()/slip_reader exactly:
    // 0xC0 delimiters, 0xDB escape with 0xDC/0xDD substitutions)

    private func slipEncode(_ packet: Data) -> Data {

        var framed = Data([0xC0])

        for byte in packet {

            switch byte {
            case 0xDB: framed.append(contentsOf: [0xDB, 0xDD])
            case 0xC0: framed.append(contentsOf: [0xDB, 0xDC])
            default: framed.append(byte)
            }
        }

        framed.append(0xC0)
        return framed
    }


    /// Looks for one complete `0xC0 ... 0xC0` frame at the start of
    /// `buffer`, unescapes it, and — if found — removes those consumed
    /// bytes from `buffer` so the next call picks up right after it.
    private func extractSlipFrame(from buffer: inout Data) -> Data? {

        guard let start = buffer.firstIndex(of: 0xC0) else {
            return nil
        }

        guard let end = buffer[buffer.index(after: start)...].firstIndex(of: 0xC0) else {
            return nil
        }

        let escaped = buffer[buffer.index(after: start)..<end]
        buffer.removeSubrange(buffer.startIndex...end)

        var result = Data()
        var iterator = escaped.makeIterator()

        while let byte = iterator.next() {

            if byte == 0xDB, let next = iterator.next() {
                result.append(next == 0xDC ? 0xC0 : (next == 0xDD ? 0xDB : next))
            } else {
                result.append(byte)
            }
        }

        return result
    }


    // MARK: - Byte helpers

    private static func uint16LE(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private static func uint32LE(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }

    private static func readUInt32LE(_ data: Data, at offset: Data.Index) -> UInt32 {

        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

#endif
