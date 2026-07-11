//
//  ReticulumFrame.swift
//  IceNomad
//

import Foundation


struct ReticulumFrame {

    let data: Data


    // MARK: - TCP Frame Marker

    var marker: UInt8? {

        guard data.count > 0 else {
            return nil
        }

        return data[0]
    }



    // MARK: - Reticulum Header

    private var packetOffset: Int {

        // Skip TCP framing byte
        return 1
    }



    var headerByte: UInt8? {

        guard data.count > packetOffset else {
            return nil
        }

        return data[packetOffset]
    }



    var hopCount: UInt8? {

        guard data.count > packetOffset + 1 else {
            return nil
        }

        return data[packetOffset + 1]
    }



    // MARK: - Header Interpretation


    var headerType: String {

        guard let headerByte else {
            return "Unknown"
        }


        // bit 6
        let type = (headerByte & 0b01000000) >> 6


        switch type {

        case 0:
            return "1 address"

        case 1:
            return "2 addresses"

        default:
            return "Unknown"
        }
    }



    var packetType: String {

        guard let headerByte else {
            return "Unknown"
        }


        // Packet type is only bits 0-1 of the header byte.
        // (Bit 2 belongs to the destination type field next to it —
        // masking with 0b111 would accidentally pull that bit in too.)
        let type = headerByte & 0b00000011


        switch type {

        case 0:
            return "DATA"

        case 1:
            return "ANNOUNCE"

        case 2:
            return "LINKREQUEST"

        case 3:
            return "PROOF"

        default:
            return "UNKNOWN \(type)"
        }
    }



    /// Whether the context flag bit (bit 5) is set. For ANNOUNCE packets,
    /// this indicates a ratchet public key is included in the payload.
    var contextFlagSet: Bool {

        guard let headerByte else {
            return false
        }

        return (headerByte & 0b00100000) != 0
    }



    // MARK: - Addresses

    /// Present only when the header has two address fields (i.e. this
    /// packet has already been forwarded by at least one transport node).
    /// This is the hash of the node that relayed the packet to us — not
    /// the announcer.
    var transportId: Data? {

        guard headerType == "2 addresses" else {
            return nil
        }

        let start = packetOffset + 2

        guard data.count >= start + 16 else {
            return nil
        }

        return Data(
            data[start..<start+16]
        )
    }



    /// The actual destination hash of the packet. For a single-address
    /// header this is the only address field; for a two-address header
    /// (already-forwarded packet) it's the *second* field — the first
    /// is the relaying transport node's ID, not the destination.
    var destinationHash: Data? {

        var start = packetOffset + 2

        if headerType == "2 addresses" {
            start += 16
        }

        guard data.count >= start + 16 else {
            return nil
        }

        return Data(
            data[start..<start+16]
        )
    }



    // MARK: - Context


    var context: UInt8? {


        var offset = packetOffset + 18


        if headerType == "2 addresses" {

            offset += 16
        }


        guard data.count > offset else {
            return nil
        }


        return data[offset]
    }



    // MARK: - Payload


    var payload: Data {


        var offset = packetOffset + 19


        if headerType == "2 addresses" {

            offset += 16
        }


        guard data.count > offset else {
            return Data()
        }


        return Data(
            data[offset..<data.count]
        )
    }
}
