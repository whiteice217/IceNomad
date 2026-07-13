//
//  MessageEnvelope.swift
//  IceNomad
//
//  Reticulum packets deliberately carry no sender address — that's the
//  protocol's "initiator anonymity" by design (confirmed in the manual:
//  "Reticulum does not include source addresses on any packets"). So a
//  raw DATA packet arriving at you says nothing about who sent it.
//
//  To have a conversation, IceNomad embeds the sender's identity INSIDE
//  the encrypted plaintext, before encryption — same idea LXMF uses for
//  its own messages. Layout (all inside the encrypted envelope):
//
//    sender_public_key  64 bytes   (so you can identify and reply to them)
//    signature           64 bytes   (Ed25519 sig of the message text,
//                                    proving it really came from that key)
//    message_text        remainder  (UTF-8)
//
//  This is IceNomad's own envelope format — see the interop note in
//  ReticulumDestination.swift.
//

import Foundation

enum MessageEnvelope {

    enum EnvelopeError: Error {
        case malformed
        case invalidSignature
    }


    /// Builds the plaintext envelope (BEFORE encryption) for an outgoing message.
    static func build(text: String) -> Data? {

        let identity = IdentityStore.shared.myIdentity

        guard let signature = identity.sign(Data(text.utf8)) else {
            return nil
        }

        return identity.publicKeyBytes + signature + Data(text.utf8)
    }


    /// Parses and verifies a decrypted envelope. Returns the sender's
    /// destination hash (computed via IceNomad's shared name_hash) and
    /// the message text — but only if the embedded signature actually
    /// matches the embedded sender key, so a message can't be spoofed
    /// as coming from someone else.
    static func parse(_ plaintext: Data) -> (senderDestinationHashHex: String, senderPublicKey: Data, text: String)? {

        guard plaintext.count > 128 else {
            return nil
        }

        let senderPublicKey = Data(plaintext.prefix(64))
        let signature = Data(plaintext.dropFirst(64).prefix(64))
        let textData = Data(plaintext.dropFirst(128))

        guard let sender = ReticulumIdentity(publicKeyBytes: senderPublicKey) else {
            return nil
        }

        guard sender.validate(signature: signature, message: textData) else {
            return nil
        }

        guard let text = String(data: textData, encoding: .utf8) else {
            return nil
        }

        let destinationHash = ReticulumDestination.destinationHash(forIdentityHash: sender.hash)
        let hex = destinationHash.map { String(format: "%02x", $0) }.joined()

        return (hex, senderPublicKey, text)
    }
}
