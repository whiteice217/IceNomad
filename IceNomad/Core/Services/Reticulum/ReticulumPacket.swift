//
//  ReticulumPacket.swift
//  IceNomad
//

import Foundation


struct ReticulumPacket {


    let frame: ReticulumFrame



    init(frame: ReticulumFrame) {

        self.frame = frame
    }



    var payload: Data {

        return frame.payload
    }



    var isAnnounce: Bool {

        return frame.packetType == "ANNOUNCE"
    }



    var packetType: String {

        return frame.packetType
    }



    var destinationHash: Data? {

        return frame.destinationHash
    }



    var transportId: Data? {

        return frame.transportId
    }



    var contextFlagSet: Bool {

        return frame.contextFlagSet
    }



    var context: UInt8? {

        return frame.context
    }
}
