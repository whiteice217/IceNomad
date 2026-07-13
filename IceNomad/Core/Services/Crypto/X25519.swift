//
//  X25519.swift
//  IceNomad
//
//  X25519 elliptic-curve Diffie-Hellman key agreement, matching RNS's
//  use of X25519PrivateKey/X25519PublicKey for encryption keys.
//

import Foundation
import CryptoKit

enum X25519 {

    struct KeyPair {
        let privateKey: Curve25519.KeyAgreement.PrivateKey

        var publicKeyBytes: Data { privateKey.publicKey.rawRepresentation }
        var privateKeyBytes: Data { privateKey.rawRepresentation }
    }

    static func generateKeyPair() -> KeyPair {
        KeyPair(privateKey: Curve25519.KeyAgreement.PrivateKey())
    }

    static func keyPair(fromPrivateBytes bytes: Data) throws -> KeyPair {
        KeyPair(privateKey: try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes))
    }

    /// Raw ECDH shared secret — matches RNS's `private_key.exchange(public_key)`.
    /// The raw bytes (not a derived key) are what feed into HKDF next.
    static func sharedSecret(privateKeyBytes: Data, publicKeyBytes: Data) throws -> Data {

        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyBytes)
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKeyBytes)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)

        return shared.withUnsafeBytes { Data($0) }
    }
}
