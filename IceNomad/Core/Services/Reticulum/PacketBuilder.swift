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
    private static let headerType2: UInt8 = 1   // two addresses — transport_id prepended, asks a relay to forward this
    private static let contextFlagUnset: UInt8 = 0
    private static let transportBroadcast: UInt8 = 0
    private static let transportTransport: UInt8 = 1
    private static let destinationSingle: UInt8 = 0
    private static let destinationPlain: UInt8 = 2
    static let destinationLink: UInt8 = 3

    private static let packetTypeData: UInt8 = 0
    private static let packetTypeAnnounce: UInt8 = 1
    static let packetTypeLinkRequest: UInt8 = 2
    static let packetTypeProof: UInt8 = 3


    // MARK: - Context bytes (RNS.Packet.NONE...LRPROOF)

    enum Context {
        static let none: UInt8 = 0x00
        static let resource: UInt8 = 0x01
        static let resourceAdv: UInt8 = 0x02
        static let resourceReq: UInt8 = 0x03
        static let resourceHmu: UInt8 = 0x04
        static let resourcePrf: UInt8 = 0x05
        static let resourceIcl: UInt8 = 0x06
        static let resourceRcl: UInt8 = 0x07
        static let request: UInt8 = 0x09
        static let response: UInt8 = 0x0A
        static let keepalive: UInt8 = 0xFA
        static let linkClose: UInt8 = 0xFC
        static let linkProof: UInt8 = 0xFD
        static let lrrtt: UInt8 = 0xFE
        static let lrProof: UInt8 = 0xFF
    }

    private static func flagsByte(packetType: UInt8, destinationType: UInt8 = destinationSingle) -> UInt8 {
        (headerType1 << 6) | (contextFlagUnset << 5) | (transportBroadcast << 4) | (destinationType << 2) | packetType
    }

    /// HEADER_2 variant — used whenever we're addressing a unicast packet
    /// to a destination that isn't on our own physical interface (i.e.
    /// almost always, once off a LAN segment). See buildDataPacket's doc
    /// comment for why this exists.
    private static func flagsByteRelayed(packetType: UInt8, destinationType: UInt8 = destinationSingle) -> UInt8 {
        (headerType2 << 6) | (contextFlagUnset << 5) | (transportTransport << 4) | (destinationType << 2) | packetType
    }


    /// The 3-byte MTU+mode signalling suffix real RNS responders always
    /// append to an LRPROOF (RNS.Link.signalling_bytes(mtu, mode), with
    /// mtu=Reticulum.MTU=500 and mode=MODE_AES256_CBC=1 — the values we
    /// always use). `(500 & 0x1FFFFF) | ((1<<5 & 0xE0)<<16)` packed
    /// big-endian as a 4-byte value, low 3 bytes.
    static let linkSignallingBytes = Data([0x20, 0x01, 0xF4])


    // MARK: - Hashable part / truncated hash
    //
    // Matches RNS.Packet.get_hashable_part()+getTruncatedHash(): the low
    // nibble of the flags byte (header_type + context_flag + transport_type
    // bits masked off, destination_type + packet_type kept) followed by
    // everything after the hops byte (address(es) + context + ciphertext).
    // This is used for TWO distinct purposes that happen to be the exact
    // same computation: deriving a link_id from our own outgoing
    // LINKREQUEST packet, and deriving a request_id from our own outgoing
    // REQUEST packet (which the server independently computes the same way
    // over the bytes it receives, and echoes back in its RESPONSE).

    static func truncatedHash(ofRawPacket raw: Data) -> Data {

        guard raw.count >= 2 else {
            return Data()
        }

        let maskedFlags = raw[raw.startIndex] & 0b00001111
        let rest = raw.dropFirst(2) // skip flags + hops

        return Hash.truncated(Data([maskedFlags]) + rest)
    }


    /// Derives link_id from a received LINKREQUEST frame. Reconstructs
    /// the hashable part from parsed fields (rather than slicing raw
    /// offsets), which sidesteps the header_type_1 vs header_type_2
    /// (transport-relayed, transport_id prepended) difference for free —
    /// RNS's own get_hashable_part() excludes the transport_id either way.
    ///
    /// Real clients (current RNS) always append a 3-byte MTU+mode
    /// signalling suffix to the LR payload (64 bytes of ephemeral keys ->
    /// 67), but that suffix must be EXCLUDED from the hash — matches
    /// RNS.Link.link_id_from_lr_packet(): `if len(packet.data) >
    /// ECPUBSIZE(64): hashable_part = hashable_part[:-diff]`. Miss this
    /// and we compute a different link_id than the initiator did, so
    /// every packet they send afterward looks addressed to a stranger.
    static func linkId(fromReceivedLinkRequest frame: ReticulumFrame) -> Data? {

        guard let headerByte = frame.headerByte,
              let destinationHash = frame.destinationHash,
              let context = frame.context
        else {
            return nil
        }

        let maskedFlags = headerByte & 0b00001111
        let truncatedPayload = Data(frame.payload.prefix(64))
        let hashable = Data([maskedFlags]) + destinationHash + Data([context]) + truncatedPayload

        return Hash.truncated(hashable)
    }


    // MARK: - Announce

    /// Builds a signed ANNOUNCE packet for your own identity, matching
    /// RNS.Destination.announce()'s payload layout (no ratchet):
    /// public_key + name_hash + random_hash + signature + app_data.
    /// Takes destinationHash/nameHash explicitly so it can announce for
    /// any destination your identity holds (IceNomad's own, LXMF's, etc.)
    static func buildAnnouncePacket(destinationHash: Data, nameHash: Data, appData: Data) -> Data? {

        let identity = IdentityStore.shared.myIdentity

        guard identity.hasPrivateKey else {
            return nil
        }

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
    ///
    /// `transportId`, when known, produces a HEADER_2 packet — the
    /// destination's identity hash prefixed with the 16-byte transport
    /// instance ID of whoever we should hand this off to for relaying.
    /// This is required for *any* destination not on our own physical
    /// interface (i.e. essentially always over the real network): a bare
    /// HEADER_1 packet addressed to someone else's hash gives a transport
    /// node no signal that it should forward it anywhere, so it's just
    /// silently dropped — no log, no error, confirmed via a live packet
    /// capture against a real server (a hand-built HEADER_1 packet never
    /// left the receiving node, while the identical payload wrapped in
    /// HEADER_2 with the upstream's transport ID was relayed and
    /// delivered in under a second). `transportId` is learned passively
    /// from any received frame with two address fields — see
    /// InterfaceManager's `lastKnownTransportId`.
    static func buildDataPacket(destinationHash: Data, ciphertext: Data, transportId: Data? = nil) -> Data {

        var packet = Data()

        if let transportId, transportId.count == 16 {
            packet.append(flagsByteRelayed(packetType: packetTypeData))
            packet.append(0) // hops
            packet.append(transportId)
        } else {
            packet.append(flagsByte(packetType: packetTypeData))
            packet.append(0) // hops
        }

        packet.append(destinationHash)
        packet.append(0) // context byte: NONE
        packet.append(ciphertext)

        return packet
    }


    // MARK: - Link request

    /// Builds an unencrypted LINKREQUEST packet addressed to a real
    /// destination hash (destination-type SINGLE — no link exists yet).
    /// data = ephemeral X25519 pubkey(32) + ephemeral Ed25519 pubkey(32),
    /// no MTU-signalling suffix — a bare 64-byte request makes a real
    /// node fall back to defaults (AES256_CBC, Reticulum.MTU) that match
    /// what we assume anyway (RNS.Link.mode_from_lr_packet/validate_request).
    /// Returns the raw packet plus its derived link_id (truncated_hash of
    /// the packet's hashable part), which becomes the address for every
    /// subsequent packet on this link.
    /// `transportId`, when known, produces a HEADER_2 packet — see
    /// buildDataPacket's doc comment for why this is required for
    /// reaching any destination not on our own physical interface.
    /// link_id must be computed over the *logical* hashable part
    /// (destinationHash + context + payload, excluding transport_id) so
    /// it matches what the recipient computes from their HEADER_1 view
    /// of the relayed-onward packet — `truncatedHash(ofRawPacket:)`'s
    /// `dropFirst(2)` would wrongly fold a HEADER_2 transport_id into the
    /// hash, so it's computed explicitly here instead.
    static func buildLinkRequestPacket(destinationHash: Data, ephemeralPublicKey: Data, signingPublicKey: Data, transportId: Data? = nil) -> (raw: Data, linkId: Data) {

        var packet = Data()
        let maskedFlags: UInt8

        if let transportId, transportId.count == 16 {
            let flags = flagsByteRelayed(packetType: packetTypeLinkRequest, destinationType: destinationSingle)
            maskedFlags = flags & 0b00001111
            packet.append(flags)
            packet.append(0) // hops
            packet.append(transportId)
        } else {
            let flags = flagsByte(packetType: packetTypeLinkRequest, destinationType: destinationSingle)
            maskedFlags = flags & 0b00001111
            packet.append(flags)
            packet.append(0) // hops
        }

        packet.append(destinationHash)
        packet.append(0) // context: NONE
        packet.append(ephemeralPublicKey)
        packet.append(signingPublicKey)

        let hashablePart = Data([maskedFlags]) + destinationHash + Data([0]) + ephemeralPublicKey + signingPublicKey
        let linkId = Hash.truncated(hashablePart)

        return (packet, linkId)
    }


    // MARK: - Path request
    //
    // Asks the network "does anyone know a path to this destination" —
    // confirmed against RNS.Transport.request_path(): addressed to a
    // fixed, well-known PLAIN destination every Reticulum node listens
    // on (name "rnstransport.path.request", hash hardcoded below since
    // it's identity-independent and never changes), carrying just
    // destination_hash + a random request tag. Real clients (nomadnet,
    // Sideband) call this before a Link attempt precisely because
    // having seen a peer's announce once doesn't guarantee every hop's
    // path table still has a fresh route by the time you act on it.

    /// truncated_hash(full_hash("rnstransport.path.request")[:10]) — the
    /// fixed destination every path request is sent to.
    static let pathRequestDestinationHash = Data(hexString: "6b9f66014d9853faab220fba47d02761")!

    static func buildPathRequestPacket(destinationHash: Data) -> Data? {

        guard let requestTag = randomBytes(16) else {
            return nil
        }

        var packet = Data()
        packet.append(flagsByte(packetType: packetTypeData, destinationType: destinationPlain))
        packet.append(0) // hops
        packet.append(pathRequestDestinationHash)
        packet.append(0) // context: NONE
        packet.append(destinationHash)
        packet.append(requestTag)

        return packet
    }


    // MARK: - Tunnel synthesis (connection liveness / reverse-route refresh)
    //
    // Traced from a real, production-hardened Reticulum reimplementation
    // (jrl290/Reticulum-rust, used by the iOS app Retichat) after
    // confirming byte-for-byte correct LINKREQUEST/PATH_REQUEST packets
    // from IceNomad still never got a reply, while the exact same
    // targets replied instantly to both a real Python client and
    // Retichat on the same phone/network. The difference: those clients
    // periodically re-announce "this TCP connection carries traffic for
    // me" to the upstream node. Without it, the upstream's reverse-route
    // mapping for our connection can be garbage-collected while we're
    // idle — announces still arrive fine (broadcast, no reverse route
    // needed), but anything that must be routed BACK to us specifically
    // (an LRPROOF, a delivered message) has nowhere to go and is
    // silently dropped upstream, with zero trace on our end. This sends
    // the same signal: a signed PLAIN-destination packet identifying us,
    // tied to this specific interface.
    //
    // data = our identity's public key(64) + full_hash(interface
    // description)(32) + a random hash(16) + signature over those
    // three fields(64) — 176 bytes total.

    /// truncated_hash(full_hash("rnstransport.tunnel.synthesize"))
    static let tunnelSynthesizeDestinationHash = Data(hexString: "91bf0910267b59b0e864e0d4c91602ca")!

    static func buildSynthesizeTunnelPacket(interfaceDescription: String) -> Data? {

        let identity = IdentityStore.shared.myIdentity
        let publicKey = identity.publicKeyBytes

        let interfaceHash = Hash.full(Data(interfaceDescription.utf8))

        guard let randomSeed = randomBytes(16) else {
            return nil
        }

        let randomHash = Hash.truncated(randomSeed)

        let signedData = publicKey + interfaceHash + randomHash

        guard let signature = identity.sign(signedData) else {
            return nil
        }

        var packet = Data()
        packet.append(flagsByte(packetType: packetTypeData, destinationType: destinationPlain))
        packet.append(0) // hops
        packet.append(tunnelSynthesizeDestinationHash)
        packet.append(0) // context: NONE
        packet.append(signedData)
        packet.append(signature)

        return packet
    }


    private static func randomBytes(_ count: Int) -> Data? {

        var bytes = Data(count: count)

        let result = bytes.withUnsafeMutableBytes { ptr -> Int32 in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }

        return result == errSecSuccess ? bytes : nil
    }


    // MARK: - Packets over an established link

    /// Builds a packet addressed to a link_id (destination-type LINK,
    /// regardless of packet type/context — matches RNS.Packet's special
    /// LRPROOF-context handling generalized to every over-the-link packet
    /// we send: REQUEST, LRRTT, LINKCLOSE, RESOURCE_REQ, RESOURCE_HMU).
    /// `payload` must already be encrypted (via the link's Token) or be
    /// one of the contexts RNS leaves unencrypted at the packet level —
    /// this function does not do any encryption itself.
    static func buildLinkPacket(linkId: Data, packetType: UInt8 = packetTypeData, context: UInt8, payload: Data) -> Data {

        var packet = Data()
        packet.append(flagsByte(packetType: packetType, destinationType: destinationLink))
        packet.append(0) // hops
        packet.append(linkId)
        packet.append(context)
        packet.append(payload)

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
