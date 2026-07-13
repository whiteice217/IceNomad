//
//  PacketBuilder.swift
//  IceNomad
//
//  Builds outbound raw Reticulum packets (ANNOUNCE and DATA) and HDLC-frames
//  them for transmission. Mirrors PacketParser's parsing exactly, in reverse.
//

import Foundation
import Security

enum PacketBuilder {

    // MARK: - Flags byte
    // packed_flags = (header_type<<6)|(context_flag<<5)|(transport_type<<4)|(destination_type<<2)|packet_type

    private static let headerType1: UInt8 = 0   // single address — we're the origin, not relaying
    private static let contextFlagUnset: UInt8 = 0
    private static let transportBroadcast: UInt8 = 0
    private static let destinationSingle: UInt8 = 0

    private static let packetTypeData: UInt8 = 0
    private static let packetTypeAnnounce: UInt8 = 1

    private static func flagsByte(packetType: UInt8) -> UInt8 {
        (headerType1 << 6) | (contextFlagUnset << 5) | (transportBroadcast << 4) | (destinationSingle << 2) | packetType
    }


    // MARK: - Announce

    /// Builds a signed ANNOUNCE packet for your own identity, matching
    /// RNS.Destination.announce()'s payload layout (no ratchet):
    /// public_key + name_hash + random_hash + signature + app_data.
    static func buildAnnouncePacket(appData: Data) -> Data? {

        let identity = IdentityStore.shared.myIdentity

        guard identity.hasPrivateKey else {
            return nil
        }

        let destinationHash = ReticulumDestination.myDestinationHash
        let nameHash = ReticulumDestination.nameHash

        guard let randomHash = randomHashField() else {
            return nil
        }

        let publicKey = identity.publicKeyBytes // 64 bytes

        let signedData = destinationHash + publicKey + nameHash + randomHash + appData

        guard let signature = identity.sign(signedData) else {
            return nil
        }

        let announceData = publicKey + nameHash + randomHash + signature + appData

        var packet = Data()
        packet.append(flagsByte(packetType: packetTypeAnnounce))
        packet.append(0) // hops
        packet.append(destinationHash)
        packet.append(0) // context byte: NONE
        packet.append(announceData)

        return packet
    }


    /// 5 random bytes + 5-byte big-endian timestamp — matches RNS's
    /// `get_random_hash()[0:5] + int(time.time()).to_bytes(5, "big")`.
    private static func randomHashField() -> Data? {

        var randomBytes = Data(count: 5)

        let result = randomBytes.withUnsafeMutableBytes { ptr -> Int32 in
            SecRandomCopyBytes(kSecRandomDefault, 5, ptr.baseAddress!)
        }

        guard result == errSecSuccess else {
            return nil
        }

        var timestamp = UInt64(Date().timeIntervalSince1970)
        var timestampBytes = Data(count: 5)

        for i in stride(from: 4, through: 0, by: -1) {
            timestampBytes[i] = UInt8(timestamp & 0xFF)
            timestamp >>= 8
        }

        return randomBytes + timestampBytes
    }


    // MARK: - Data (chat message)

    /// Builds a DATA packet addressed to `destinationHash`, carrying
    /// `ciphertext` as the already-encrypted payload.
    static func buildDataPacket(destinationHash: Data, ciphertext: Data) -> Data {

        var packet = Data()
        packet.append(flagsByte(packetType: packetTypeData))
        packet.append(0) // hops
        packet.append(destinationHash)
        packet.append(0) // context byte: NONE
        packet.append(ciphertext)

        return packet
    }


    // MARK: - HDLC framing (outbound)

    /// Wraps a raw packet for transmission: leading + trailing 0x7E
    /// markers, with embedded 0x7E/0x7D bytes escaped via 0x7D — the
    /// exact inverse of PacketParser's unescape step.
    static func hdlcFrame(_ raw: Data) -> Data {

        var framed = Data()
        framed.append(0x7E)

        for byte in raw {

            switch byte {

            case 0x7E:
                framed.append(0x7D)
                framed.append(0x7E ^ 0x20)

            case 0x7D:
                framed.append(0x7D)
                framed.append(0x7D ^ 0x20)

            default:
                framed.append(byte)
            }
        }

        framed.append(0x7E)

        return framed
    }
}
