//
//  HKDF.swift
//  IceNomad
//
//  HMAC-based key derivation. This matches RNS's own hkdf() function
//  EXACTLY (confirmed against RNS/Cryptography/HKDF.py) — it's standard
//  RFC 5869 HKDF-SHA256, so CryptoKit's built-in HKDF implementation
//  produces bit-identical output. The only RNS-specific behavior is the
//  default salt (32 zero bytes) and default info (empty) when omitted.
//

import Foundation
import CryptoKit

enum ReticulumHKDF {

    static func derive(length: Int, inputKeyMaterial: Data, salt: Data?, context: Data? = nil) -> Data {

        let effectiveSalt: Data = (salt?.isEmpty ?? true) ? Data(repeating: 0, count: 32) : salt!
        let info = context ?? Data()

        let key = CryptoKit.HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: inputKeyMaterial),
            salt: effectiveSalt,
            info: info,
            outputByteCount: length
        )

        return key.withUnsafeBytes { Data($0) }
    }
}
