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


        let type = headerByte & 0b00000111


        switch type {

        case 0:
            return "DATA"

        case 1:
            return "ANNOUNCE"

        case 2:
            return "LINKREQUEST"

        case 3:
            return "LINKPROOF"

        default:
            return "UNKNOWN \(type)"
        }
    }



    // MARK: - Addresses


    var destinationHash: Data? {

        let start = packetOffset + 2


        guard data.count >= start + 16 else {
            return nil
        }


        return Data(
            data[start..<start+16]
        )
    }



    var sourceHash: Data? {

        guard headerType == "2 addresses" else {
            return nil
        }


        let start = packetOffset + 18


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
