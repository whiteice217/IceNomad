//
//  Ed25519.swift
//  IceNomad
//
//  Ed25519 signatures, matching RNS's use of Ed25519PrivateKey/PublicKey
//  for signing keys.
//

import Foundation
import CryptoKit

enum Ed25519 {

    struct KeyPair {
        let privateKey: Curve25519.Signing.PrivateKey

        var publicKeyBytes: Data { privateKey.publicKey.rawRepresentation }
        var privateKeyBytes: Data { privateKey.rawRepresentation }
    }

    static func generateKeyPair() -> KeyPair {
        KeyPair(privateKey: Curve25519.Signing.PrivateKey())
    }

    static func keyPair(fromPrivateBytes bytes: Data) throws -> KeyPair {
        KeyPair(privateKey: try Curve25519.Signing.PrivateKey(rawRepresentation: bytes))
    }

    static func sign(message: Data, privateKeyBytes: Data) throws -> Data {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyBytes)
        return try key.signature(for: message)
    }

    static func verify(signature: Data, message: Data, publicKeyBytes: Data) -> Bool {

        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyBytes) else {
            return false
        }

        return key.isValidSignature(signature, for: message)
    }
}
