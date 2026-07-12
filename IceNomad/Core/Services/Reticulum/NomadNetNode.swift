//
//  NomadNetNode.swift
//  IceNomad
//
//  NomadNet nodes announce under the destination aspect "nomadnetwork.node"
//  (confirmed against NomadNet's own docs — it uses RNS Link request/response
//  on that aspect, not LXMF). Every announce carries a truncated SHA-256
//  hash of its full destination name, so we can precompute the expected
//  hash for that aspect and compare, purely locally — no crypto/Link
//  needed for this part, just plain SHA-256 via CryptoKit.
//

import Foundation
import CryptoKit

enum NomadNetNode {

    /// Truncated (10-byte) SHA-256 of "nomadnetwork.node".
    static let expectedNameHash: Data = {

        let digest = SHA256.hash(data: Data("nomadnetwork.node".utf8))
        return Data(digest.prefix(10))
    }()


    static func isNode(_ peer: Peer) -> Bool {

        peer.nameHash == expectedNameHash
    }
}
