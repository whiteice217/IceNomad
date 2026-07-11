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



    var sourceHash: Data? {

        return frame.sourceHash
    }



    var context: UInt8? {

        return frame.context
    }
}
