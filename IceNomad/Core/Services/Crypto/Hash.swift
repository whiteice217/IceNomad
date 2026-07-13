//
//  Hash.swift
//  IceNomad
//
//  SHA-256 hashing, matching RNS.Identity.full_hash / truncated_hash.
//

import Foundation
import CryptoKit

enum Hash {

    /// Full SHA-256 hash — matches RNS's `Identity.full_hash()`.
    static func full(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    /// Truncated hash: the first `length` bytes of the full SHA-256 hash.
    /// Reticulum uses a 128-bit (16 byte) truncated hash throughout for
    /// identity and destination hashes — matches `Identity.truncated_hash()`.
    static func truncated(_ data: Data, length: Int = 16) -> Data {
        Data(full(data).prefix(length))
    }
}
