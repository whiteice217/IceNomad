//
//  AnnouncePacket.swift
//  IceNomad
//
//  Parses the DATA field of an ANNOUNCE packet.
//
//  Layout (from RNS/Destination.py announce()):
//    public_key   64 bytes   (32 X25519 encryption + 32 Ed25519 signing)
//    name_hash    10 bytes
//    random_hash  10 bytes
//    ratchet      0 or 32 bytes  (present only if context flag bit is set)
//    signature    64 bytes
//    app_data     remainder (optional, app-specific)
//

import Foundation


struct AnnouncePacket {

    static let publicKeyLength = 64
    static let nameHashLength = 10
    static let randomHashLength = 10
    static let ratchetLength = 32
    static let signatureLength = 64


    let destinationHash: Data
    let encryptionPublicKey: Data
    let signingPublicKey: Data
    let nameHash: Data
    let randomHash: Data
    let ratchet: Data?
    let signature: Data
    let appData: Data


    /// Attempts to parse an announce payload. Returns nil if the packet
    /// is too short to contain the fixed-size fields it must have.
    init?(packet: ReticulumPacket) {

        guard packet.isAnnounce else {
            return nil
        }

        guard let destinationHash = packet.destinationHash else {
            return nil
        }

        let data = packet.payload
        var offset = data.startIndex

        func take(_ length: Int) -> Data? {

            guard let end = data.index(
                offset,
                offsetBy: length,
                limitedBy: data.endIndex
            ) else {
                return nil
            }

            let slice = Data(data[offset..<end])
            offset = end
            return slice
        }

        guard let publicKey = take(Self.publicKeyLength),
              let nameHash = take(Self.nameHashLength),
              let randomHash = take(Self.randomHashLength)
        else {
            return nil
        }

        var ratchet: Data? = nil

        if packet.contextFlagSet {

            guard let ratchetBytes = take(Self.ratchetLength) else {
                return nil
            }

            ratchet = ratchetBytes
        }

        guard let signature = take(Self.signatureLength) else {
            return nil
        }

        let appData = Data(data[offset..<data.endIndex])

        self.destinationHash = destinationHash
        self.encryptionPublicKey = Data(publicKey.prefix(32))
        self.signingPublicKey = Data(publicKey.suffix(32))
        self.nameHash = nameHash
        self.randomHash = randomHash
        self.ratchet = ratchet
        self.signature = signature
        self.appData = appData
    }


    /// Best-effort human-readable name from app_data. Reticulum does not
    /// define a universal format for app_data — it's app-specific — so
    /// this is a guess (valid UTF-8 text), not a guaranteed display name.
    var displayName: String? {

        guard !appData.isEmpty else {
            return nil
        }

        guard let text = String(data: appData, encoding: .utf8) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }


    var destinationHashHex: String {

        destinationHash.map { String(format: "%02x", $0) }.joined()
    }
}
