//
//  IdentityStore.swift
//  IceNomad
//
//  Holds and persists YOUR Reticulum identity. Stored in the iOS
//  Keychain (not UserDefaults) since the private key here IS your
//  presence on the network — anyone who has it can impersonate you.
//
//  On first launch, generates a new identity and saves it. On every
//  launch after that, loads the same one back, so your address stays
//  stable across app restarts.
//

import Foundation
import Combine
import Security

final class IdentityStore: ObservableObject {

    static let shared = IdentityStore()

    let myIdentity: ReticulumIdentity

    private let keychainAccount = "icenomad-primary-identity"
    private let keychainService = "com.icenomad.identity"

    private init() {

        if let existing = IdentityStore.loadFromKeychain(
            service: keychainService,
            account: keychainAccount
        ), let identity = ReticulumIdentity(privateKeyBytes: existing) {

            self.myIdentity = identity

        } else {

            let identity = ReticulumIdentity()

            if let privateKey = identity.privateKeyBytes {
                IdentityStore.saveToKeychain(
                    privateKey,
                    service: keychainService,
                    account: keychainAccount
                )
            }

            self.myIdentity = identity
        }
    }


    // MARK: - Keychain

    private static func saveToKeychain(_ data: Data, service: String, account: String) {

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Remove any existing entry first — SecItemAdd fails on a duplicate.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)

        if status != errSecSuccess {
            print("⚠️ Failed to save identity to Keychain, status: \(status)")
        }
    }


    private static func loadFromKeychain(service: String, account: String) -> Data? {

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }
}
  
