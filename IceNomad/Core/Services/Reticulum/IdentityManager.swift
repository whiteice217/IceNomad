//
//  IdentityManager.swift
//  IceNomad
//
//  A Reticulum Identity: a 512-bit keyset (256-bit X25519 encryption key +
//  256-bit Ed25519 signing key), matching RNS.Identity's essential
//  behavior for single-destination messaging and announcing.
//
//  Two ways to use this:
//  - FULL identity (yours): holds private keys too, generated fresh or
//    loaded from storage. Can sign and decrypt.
//  - PEER identity (someone else's, built from their announce): holds
//    only their public keys. Can encrypt (to them) and validate (their
//    signatures), but not decrypt or sign.
//

import Foundation
import CryptoKit

final class ReticulumIdentity {

    static let publicKeySize = 64   // 32 (X25519 pub) + 32 (Ed25519 pub)
    static let privateKeySize = 64  // 32 (X25519 priv) + 32 (Ed25519 priv)
    /// HKDF output length feeding the Token key. RNS.Identity.encrypt/decrypt
    /// derive a 32-byte key specifically (→ Token's AES-128-CBC mode) —
    /// confirmed against RNS's own test vectors, not just source reading.
    static let derivedKeyLength = 32

    enum IdentityError: Error {
        case invalidKeyLength
        case noPrivateKey
        case malformedCiphertext
    }


    private let x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey?
    private let ed25519PrivateKey: Curve25519.Signing.PrivateKey?

    let x25519PublicKeyBytes: Data
    let ed25519PublicKeyBytes: Data

    /// The IDENTITY hash: truncated_hash(x25519_pub + ed25519_pub).
    /// This is NOT a destination hash — a destination hash additionally
    /// mixes in that destination's name_hash. This is the value used as
    /// the HKDF salt for single-destination encryption.
    let hash: Data


    // MARK: - Creating / Loading

    /// Generates a brand new identity with fresh random keys.
    init() {

        let x = Curve25519.KeyAgreement.PrivateKey()
        let s = Curve25519.Signing.PrivateKey()

        self.x25519PrivateKey = x
        self.ed25519PrivateKey = s
        self.x25519PublicKeyBytes = x.publicKey.rawRepresentation
        self.ed25519PublicKeyBytes = s.publicKey.rawRepresentation
        self.hash = ReticulumIdentity.computeHash(
            x25519Public: x25519PublicKeyBytes,
            ed25519Public: ed25519PublicKeyBytes
        )
    }


    /// Loads a FULL identity (with private keys) from a 64-byte private
    /// key blob — matches RNS's `get_private_key()` / `load_private_key()`
    /// format: 32 bytes X25519 private + 32 bytes Ed25519 private.
    init?(privateKeyBytes: Data) {

        guard privateKeyBytes.count == ReticulumIdentity.privateKeySize else {
            return nil
        }

        let xBytes = privateKeyBytes.prefix(32)
        let sBytes = privateKeyBytes.suffix(32)

        guard let x = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: xBytes),
              let s = try? Curve25519.Signing.PrivateKey(rawRepresentation: sBytes)
        else {
            return nil
        }

        self.x25519PrivateKey = x
        self.ed25519PrivateKey = s
        self.x25519PublicKeyBytes = x.publicKey.rawRepresentation
        self.ed25519PublicKeyBytes = s.publicKey.rawRepresentation
        self.hash = ReticulumIdentity.computeHash(
            x25519Public: x25519PublicKeyBytes,
            ed25519Public: ed25519PublicKeyBytes
        )
    }


    /// Builds a PEER identity — public keys only — from a 64-byte public
    /// key blob, exactly as seen in an ANNOUNCE payload.
    init?(publicKeyBytes: Data) {

        guard publicKeyBytes.count == ReticulumIdentity.publicKeySize else {
            return nil
        }

        let xBytes = Data(publicKeyBytes.prefix(32))
        let sBytes = Data(publicKeyBytes.suffix(32))

        guard (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: xBytes)) != nil,
              (try? Curve25519.Signing.PublicKey(rawRepresentation: sBytes)) != nil
        else {
            return nil
        }

        self.x25519PrivateKey = nil
        self.ed25519PrivateKey = nil
        self.x25519PublicKeyBytes = xBytes
        self.ed25519PublicKeyBytes = sBytes
        self.hash = ReticulumIdentity.computeHash(
            x25519Public: xBytes,
            ed25519Public: sBytes
        )
    }


    // MARK: - Key blobs

    /// 64-byte combined public key — matches RNS `get_public_key()`.
    var publicKeyBytes: Data {
        x25519PublicKeyBytes + ed25519PublicKeyBytes
    }

    /// 64-byte combined private key — matches RNS `get_private_key()`.
    /// Nil for peer identities, which hold no private keys.
    var privateKeyBytes: Data? {

        guard let x = x25519PrivateKey, let s = ed25519PrivateKey else {
            return nil
        }

        return x.rawRepresentation + s.rawRepresentation
    }

    var hasPrivateKey: Bool {
        x25519PrivateKey != nil && ed25519PrivateKey != nil
    }


    // MARK: - Signing / Verifying

    /// Signs a message. Only works on a full identity (yours).
    func sign(_ message: Data) -> Data? {

        guard let s = ed25519PrivateKey else {
            return nil
        }

        return try? s.signature(for: message)
    }


    /// Verifies a signature against THIS identity's signing public key —
    /// call this on a peer identity to check something they signed.
    func validate(signature: Data, message: Data) -> Bool {

        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: ed25519PublicKeyBytes) else {
            return false
        }

        return key.isValidSignature(signature, for: message)
    }


    // MARK: - Encrypting / Decrypting (single-destination)

    /// Encrypts `plaintext` FOR this identity. Call this on a PEER
    /// identity (their public keys) — the result can only be decrypted
    /// by whoever holds the matching private key.
    func encrypt(_ plaintext: Data) throws -> Data {

        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublicBytes = ephemeral.publicKey.rawRepresentation

        let recipientPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: x25519PublicKeyBytes)
        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(with: recipientPublicKey)
        let sharedSecretBytes = sharedSecret.withUnsafeBytes { Data($0) }

        let derivedKey = ReticulumHKDF.derive(
            length: ReticulumIdentity.derivedKeyLength,
            inputKeyMaterial: sharedSecretBytes,
            salt: hash // the RECIPIENT's identity hash
        )

        let token = try ReticulumToken.encrypt(plaintext: plaintext, key: derivedKey)

        return ephemeralPublicBytes + token
    }


    /// Decrypts a ciphertext token addressed to you. Call this on your
    /// own FULL identity (holding your private key).
    func decrypt(_ ciphertextToken: Data) throws -> Data {

        guard let myPrivateKey = x25519PrivateKey else {
            throw IdentityError.noPrivateKey
        }

        guard ciphertextToken.count > 32 else {
            throw IdentityError.malformedCiphertext
        }

        let peerPublicBytes = Data(ciphertextToken.prefix(32))
        let token = Data(ciphertextToken.suffix(ciphertextToken.count - 32))

        let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicBytes)
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        let sharedSecretBytes = sharedSecret.withUnsafeBytes { Data($0) }

        let derivedKey = ReticulumHKDF.derive(
            length: ReticulumIdentity.derivedKeyLength,
            inputKeyMaterial: sharedSecretBytes,
            salt: hash // MY OWN identity hash
        )

        return try ReticulumToken.decrypt(token: token, key: derivedKey)
    }


    // MARK: - Hashing

    private static func computeHash(x25519Public: Data, ed25519Public: Data) -> Data {
        Hash.truncated(x25519Public + ed25519Public)
    }
}
