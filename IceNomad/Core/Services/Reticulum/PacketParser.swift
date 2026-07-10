//
//  PacketParser.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation

// MARK: - Raw Reticulum Frame

struct ReticulumFrame {

    let data: Data

    var headerByte: UInt8? {
        data.first
    }

    var hops: UInt8? {
        guard data.count > 1 else { return nil }
        return data[1]
    }

    var packetType: UInt8? {
        guard let header = headerByte else { return nil }
        return (header >> 6) & 0x03
    }

    var destinationHash: Data? {
        guard data.count >= 18 else { return nil }
        return data.subdata(in: 2..<18)
    }

    var context: UInt8? {
        guard data.count > 18 else { return nil }
        return data[18]
    }

    var payload: Data {
        guard data.count > 19 else {
            return Data()
        }

        return data.subdata(in: 19..<data.count)
    }
}

// MARK: - Parser

final class PacketParser {

    private var buffer = Data()

    var onFrameReceived: ((ReticulumFrame) -> Void)?

    func receive(_ data: Data) {
        buffer.append(data)
        parseBuffer()
    }

    private func parseBuffer() {

        while let start = buffer.firstIndex(of: 0x7E) {

            guard let end = buffer[start...]
                .dropFirst()
                .firstIndex(of: 0x7E)
            else {
                return
            }

            // Remove both HDLC delimiters (0x7E)
            let packet = Data(buffer[(start + 1)..<end])

            buffer.removeSubrange(...end)

            onFrameReceived?(
                ReticulumFrame(data: packet)
            )
        }
    }
}
