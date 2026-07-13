//
//  ReticulumDestination.swift
//  IceNomad
//
//  IceNomad's own chat destination convention: app_name "icenomad",
//  aspect "chat" — full name "icenomad.chat".
//
//  IMPORTANT — interop scope: this lets two copies of IceNomad message
//  each other for real over Reticulum. It does NOT speak LXMF, which is
//  the envelope format apps like Sideband/NomadNet use for their own
//  chat — that's a separate, additional protocol layer (its own
//  msgpack envelope, propagation node support, etc.) that would need
//  to be implemented separately for cross-app interop. Announces and
//  page-node detection (NomadNetNode) are unaffected by this — those
//  read other apps' destinations fine, since announces are public by
//  design.
//

import Foundation

enum ReticulumDestination {

    static let appName = "icenomad"
    static let aspect = "chat"
    static let fullName = "icenomad.chat"

    /// Truncated (10-byte) SHA-256 of "icenomad.chat" — matches how
    /// every destination's name_hash is computed.
    static let nameHash: Data = Hash.truncated(Data(fullName.utf8), length: 10)

    /// A destination hash is truncated_hash(name_hash + identity_hash).
    static func destinationHash(forIdentityHash identityHash: Data) -> Data {
        Hash.truncated(nameHash + identityHash, length: 16)
    }

    /// Your own destination hash, derived from your persisted identity.
    static var myDestinationHash: Data {
        destinationHash(forIdentityHash: IdentityStore.shared.myIdentity.hash)
    }

    static var myDestinationHashHex: String {
        myDestinationHash.map { String(format: "%02x", $0) }.joined()
    }
}
