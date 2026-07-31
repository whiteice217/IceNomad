//
//  LXMFDestination.swift
//  IceNomad
//
//  LXMF's own destination convention: app_name "lxmf", aspect "delivery"
//  — full name "lxmf.delivery". Registering and announcing on this
//  destination (alongside our own icenomad.chat one) is what makes you
//  addressable by real NomadNet/Sideband/other LXMF-based clients.
//

import Foundation

enum LXMFDestination {

    static let appName = "lxmf"
    static let aspect = "delivery"
    static let fullName = "lxmf.delivery"

    static let nameHash: Data = Hash.truncated(Data(fullName.utf8), length: 10)

    static func destinationHash(forIdentityHash identityHash: Data) -> Data {
        Hash.truncated(nameHash + identityHash, length: 16)
    }

    static var myDestinationHash: Data {
        destinationHash(forIdentityHash: IdentityStore.shared.myIdentity.hash)
    }

    static var myDestinationHashHex: String {
        myDestinationHash.map { String(format: "%02x", $0) }.joined()
    }


    /// Builds LXMF-style announce app_data: a msgpack array [name (bin), stamp_cost, features].
    /// Matches LXMF's own `display_name_from_app_data()` format so real
    /// clients (NomadNet, Sideband) show your name correctly. Sending
    /// only the name (omitting stamp_cost/features) is treated by real
    /// clients as "no stamp required" and "compression support assumed."
    static func announceAppData(displayName: String) -> Data {

        let value = MsgpackValue.array([
            .binary(Data(displayName.utf8))
        ])

        return value.encode()
    }
}
