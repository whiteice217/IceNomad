//
//  ReticulumPacket.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/10/26.
//
import Foundation


struct ReticulumPacket {
    
    let frame: ReticulumFrame
    
    
    var context: UInt8 {
        frame.context ?? 0
    }
    
    
    var payload: Data {
        frame.payload
    }
    
    
    var isAnnounce: Bool {
        frame.packetType == 0x01
    }
    
    
    var payloadString: String? {
        
        String(
            data: payload,
            encoding: .utf8
        )
    }
}
