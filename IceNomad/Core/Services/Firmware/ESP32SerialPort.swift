//
//  ESP32SerialPort.swift
//  IceNomad
//
//  Raw POSIX serial port access — Mac only (Mac Catalyst isn't
//  sandboxed here, so plain open()/termios on /dev/cu.* just works, the
//  same as any command-line tool). This is deliberately a thin, direct
//  port of exactly what real esptool does at the POSIX layer (see
//  esptool/reset.py's UnixTightReset and esptool/loader.py's
//  ESPLoader._connect_attempt) — confirmed against esptool 5.3.1's
//  actual source, not guessed, since a wrong DTR/RTS sequence or baud
//  setup either does nothing or (rarely, briefly) glitches the board's
//  boot pins.
//

#if targetEnvironment(macCatalyst)

import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum ESP32SerialPortError: Error {
    case openFailed(String)
    case configurationFailed
    case notOpen
}

final class ESP32SerialPort {

    let path: String
    private var fileDescriptor: Int32 = -1

    init(path: String) {
        self.path = path
    }


    var isOpen: Bool { fileDescriptor >= 0 }


    /// Opens the device and configures it as a raw, 8N1 serial line at
    /// the given baud — mirrors pySerial's posix backend defaults, which
    /// is what real esptool actually talks over.
    func open(baud: speed_t = speed_t(115200)) throws {

        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)

        guard fd >= 0 else {
            throw ESP32SerialPortError.openFailed(String(cString: strerror(errno)))
        }

        // Drop O_NONBLOCK now that the port is open — we want blocking
        // reads with our own timeout handling below, matching pySerial.
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)

        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            Darwin.close(fd)
            throw ESP32SerialPortError.configurationFailed
        }

        cfmakeraw(&options)
        cfsetispeed(&options, baud)
        cfsetospeed(&options, baud)

        // 8N1, no flow control — standard for an ESP32 bootloader link.
        options.c_cflag &= ~tcflag_t(PARENB)
        options.c_cflag &= ~tcflag_t(CSTOPB)
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= tcflag_t(CS8)
        options.c_cflag &= ~tcflag_t(CRTSCTS)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)

        // VMIN/VTIME: return as soon as 1 byte is available, or after
        // 1.0s of silence — read(_:) below layers its own longer
        // timeout on top by looping.
        withUnsafeMutableBytes(of: &options.c_cc) { raw in
            raw[Int(VMIN)] = 0
            raw[Int(VTIME)] = 10
        }

        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            Darwin.close(fd)
            throw ESP32SerialPortError.configurationFailed
        }

        tcflush(fd, TCIOFLUSH)

        fileDescriptor = fd
    }


    func close() {

        guard fileDescriptor >= 0 else { return }
        Darwin.close(fileDescriptor)
        fileDescriptor = -1
    }


    func write(_ data: Data) throws {

        guard fileDescriptor >= 0 else {
            throw ESP32SerialPortError.notOpen
        }

        _ = data.withUnsafeBytes { raw in
            Darwin.write(fileDescriptor, raw.baseAddress, raw.count)
        }
    }


    /// Reads whatever is available up to `maxLength`, blocking per the
    /// VMIN/VTIME configured in `open` (~1s of silence ends a read) —
    /// returns empty Data on a pure timeout, never throws for that case,
    /// since "nothing arrived yet" is routine while polling for a sync
    /// response.
    func read(maxLength: Int = 256) -> Data {

        guard fileDescriptor >= 0 else { return Data() }

        var buffer = [UInt8](repeating: 0, count: maxLength)

        let count = buffer.withUnsafeMutableBytes { raw in
            Darwin.read(fileDescriptor, raw.baseAddress, maxLength)
        }

        guard count > 0 else { return Data() }

        return Data(buffer[0..<count])
    }


    /// Real esptool's UnixTightReset — sets DTR/RTS together in one
    /// ioctl call per step (TIOCMGET/TIOCMSET), not two separate calls,
    /// which is specifically what avoids a brief glitch some USB-serial
    /// adapters show if the lines are toggled one at a time. Confirmed
    /// this exact sequence against a real connected Heltec V3 via
    /// esptool itself before porting it here.
    func resetIntoBootloader() {

        guard fileDescriptor >= 0 else { return }

        setDTRAndRTS(dtr: false, rts: false)
        setDTRAndRTS(dtr: true, rts: true)
        setDTRAndRTS(dtr: false, rts: true) // IO0=HIGH, EN=LOW (reset)
        usleep(100_000)
        setDTRAndRTS(dtr: true, rts: false) // IO0=LOW, EN=HIGH (out of reset, into bootloader)
        usleep(50_000)
        setDTRAndRTS(dtr: false, rts: false) // IO0=HIGH, done
    }


    private func setDTRAndRTS(dtr: Bool, rts: Bool) {

        guard fileDescriptor >= 0 else { return }

        var status: Int32 = 0
        ioctl(fileDescriptor, UInt(TIOCMGET), &status)

        if dtr { status |= TIOCM_DTR } else { status &= ~TIOCM_DTR }
        if rts { status |= TIOCM_RTS } else { status &= ~TIOCM_RTS }

        ioctl(fileDescriptor, UInt(TIOCMSET), &status)
    }
}

#endif
