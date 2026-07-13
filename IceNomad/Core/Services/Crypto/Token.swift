//
//  Token.swift
//  IceNomad
//
//  A Fernet-like symmetric token, matching RNS.Cryptography.Token exactly:
//    IV (16 bytes) + AES-CBC(PKCS7-padded plaintext) + HMAC-SHA256 (32 bytes)
//  keyed from either a 32-byte key (AES-128: signing_key = key[0:16],
//  encryption_key = key[16:32]) or a 64-byte key (AES-256: key[0:32]/key[32:64]).
//  Single-destination message encryption (RNS.Identity.encrypt/decrypt)
//  specifically uses the 32-byte/AES-128 form.
//
//  CryptoKit doesn't expose AES-CBC directly (only AES-GCM), so this one
//  piece uses CommonCrypto — everything else in the crypto layer is CryptoKit.
//

import Foundation
import CryptoKit
import CommonCrypto
import Security

enum ReticulumToken {

    static let overhead = 48 // iv(16) + hmac(32)

    enum TokenError: Error {
        case invalidKeyLength
        case invalidToken
        case invalidHMAC
        case cryptoFailure
    }

    static func encrypt(plaintext: Data, key: Data) throws -> Data {

        let (signingKey, encryptionKey) = try splitKey(key)

        var iv = Data(count: 16)
        let ivResult = iv.withUnsafeMutableBytes { ptr -> Int32 in
            SecRandomCopyBytes(kSecRandomDefault, 16, ptr.baseAddress!)
        }

        guard ivResult == errSecSuccess else {
            throw TokenError.cryptoFailure
        }

        let ciphertext = try aesCBC(operation: CCOperation(kCCEncrypt), data: plaintext, key: encryptionKey, iv: iv)

        let signedParts = iv + ciphertext
        let hmac = hmacSHA256(key: signingKey, message: signedParts)

        return signedParts + hmac
    }


    static func decrypt(token: Data, key: Data) throws -> Data {

        let (signingKey, encryptionKey) = try splitKey(key)

        guard token.count > 32 else {
            throw TokenError.invalidToken
        }

        let receivedHMAC = Data(token.suffix(32))
        let signedParts = Data(token.prefix(token.count - 32))

        let expectedHMAC = hmacSHA256(key: signingKey, message: signedParts)

        // Verify BEFORE decrypting — never attempt to decrypt on a
        // failed HMAC, to avoid padding-oracle style failure leaks.
        guard receivedHMAC == expectedHMAC else {
            throw TokenError.invalidHMAC
        }

        guard signedParts.count > 16 else {
            throw TokenError.invalidToken
        }

        let iv = Data(signedParts.prefix(16))
        let ciphertext = Data(signedParts.suffix(signedParts.count - 16))

        return try aesCBC(operation: CCOperation(kCCDecrypt), data: ciphertext, key: encryptionKey, iv: iv)
    }


    /// Matches RNS's Token.__init__: a 32-byte key means AES-128-CBC
    /// (16-byte signing key + 16-byte encryption key); a 64-byte key
    /// means AES-256-CBC (32+32). This is NOT an arbitrary choice on
    /// our end — RNS.Identity.encrypt/decrypt specifically derive a
    /// 32-byte key via HKDF, so the 32-byte/AES-128 path is what real
    /// single-destination message encryption actually uses.
    private static func splitKey(_ key: Data) throws -> (signing: Data, encryption: Data) {

        switch key.count {

        case 32:
            return (Data(key.prefix(16)), Data(key.suffix(16)))

        case 64:
            return (Data(key.prefix(32)), Data(key.suffix(32)))

        default:
            throw TokenError.invalidKeyLength
        }
    }


    // MARK: - AES-256-CBC (CommonCrypto)

    private static func aesCBC(operation: CCOperation, data: Data, key: Data, iv: Data) throws -> Data {

        let outLength = data.count + kCCBlockSizeAES128
        var outData = Data(count: outLength)
        var numBytesProcessed: size_t = 0

        let status = outData.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
            data.withUnsafeBytes { dataPtr -> CCCryptorStatus in
                iv.withUnsafeBytes { ivPtr -> CCCryptorStatus in
                    key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, data.count,
                            outPtr.baseAddress, outLength,
                            &numBytesProcessed
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw TokenError.cryptoFailure
        }

        outData.removeSubrange(numBytesProcessed..<outData.count)
        return outData
    }


    // MARK: - HMAC-SHA256

    private static func hmacSHA256(key: Data, message: Data) -> Data {

        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
        return Data(mac)
    }
}
