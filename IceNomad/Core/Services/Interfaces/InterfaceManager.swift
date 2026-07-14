//
//  InterfaceManager.swift
//  IceNomad
//

import Foundation
import Combine


class InterfaceManager: ObservableObject {

    // MARK: - Shared instance
    //
    // A single shared instance, so every view (Connections, Messages,
    // Browser, Announce) sends and receives through the same actual
    // connections, instead of each owning an independent copy.

    static let shared = InterfaceManager()


    // MARK: - Properties

    private let packetParser = PacketParser()

    @Published private(set) var interfaces: [ReticulumInterface] = []

    @Published var connectionStates: [String: Bool] = [:]

    @Published var receivedPacketCount: Int = 0


    // MARK: - Init

    init() {

        let myHash = ReticulumDestination.myDestinationHashHex
        let myIdentityHash = IdentityStore.shared.myIdentity.hash.hexString

        print("🆔 My identity hash:    \(myIdentityHash)")
        print("🆔 My destination hash: \(myHash)")

        packetParser.onFrameReceived = { [weak self] frame in

            DispatchQueue.main.async {

                self?.handle(frame: frame)
            }
        }
    }


    private func handle(frame: ReticulumFrame) {

        let packet = ReticulumPacket(frame: frame)

        if packet.isAnnounce {

            debugLogIncomingAnnounce(packet)
            PeerStore.shared.handle(frame: frame)
            return
        }

        if packet.isData {

            handleDataPacket(packet)
            return
        }
    }


    /// Logs every parsed announce, and flags loudly if it's OUR OWN
    /// announce coming back to us — the clearest possible proof that an
    /// outbound announce actually reached the network and was
    /// considered well-formed by whatever relayed it back.
    private func debugLogIncomingAnnounce(_ packet: ReticulumPacket) {

        guard let destinationHash = packet.destinationHash else {
            print("📡 ANNOUNCE IN — but no destination hash could be parsed from it.")
            return
        }

        let hex = destinationHash.hexString
        let isMine = destinationHash == ReticulumDestination.myDestinationHash

        guard let announce = AnnouncePacket(packet: packet) else {
            print("📡 ANNOUNCE IN from \(hex) — but the payload didn't parse as a valid announce.")
            return
        }

        let name = announce.displayName ?? "(unnamed)"

        if isMine {
            print("🔁 MY OWN ANNOUNCE CAME BACK — \(hex) as \"\(name)\". This confirms your announce reached the network and round-tripped successfully.")
        } else {
            print("📡 ANNOUNCE IN — \(hex) as \"\(name)\", \(packet.frame.hopCount.map { "\($0) hop(s)" } ?? "hop count unknown")")
        }
    }


    /// A DATA packet carries no sender address by design (Reticulum's
    /// "initiator anonymity") — only whether it's addressed to us. If it
    /// is, decrypt with our own identity and unpack the sender info
    /// IceNomad embeds inside the envelope (see MessageEnvelope.swift).
    private func handleDataPacket(_ packet: ReticulumPacket) {

        guard let destinationHash = packet.destinationHash else {
            print("📩 DATA IN — but no destination hash could be parsed from it.")
            return
        }

        let hex = destinationHash.hexString
        let mine = ReticulumDestination.myDestinationHashHex
        let isMine = destinationHash == ReticulumDestination.myDestinationHash

        print("📩 DATA IN — addressed to \(hex) (mine is \(mine)) — \(isMine ? "MATCH, attempting decrypt" : "not for me, ignoring")")

        guard isMine else {
            return
        }

        do {

            let plaintext = try IdentityStore.shared.myIdentity.decrypt(packet.payload)

            guard let (senderHex, senderPublicKey, text) = MessageEnvelope.parse(plaintext) else {
                print("🔒 Decrypted OK, but envelope verification failed (bad signature or malformed envelope) — dropped.")
                return
            }

            print("🔓 Decrypted message from \(senderHex): \"\(text)\"")

            PeerStore.shared.recordDirectContact(
                destinationHashHex: senderHex,
                identityPublicKey: senderPublicKey
            )

            MessageStore.shared.receive(text: text, from: senderHex)

        } catch {
            print("🔒 Decrypt FAILED (HMAC/AES error, meaning it likely wasn't actually encrypted to us, or is corrupt): \(error)")
        }
    }


    // MARK: - Load Interfaces

    func loadInterfaces() {

        interfaces.removeAll()

        print("Loading interfaces...")

        let connections = ConnectionStorage.shared.load()


        for connection in connections {

            switch connection.type {


            // MARK: TCP Client

            case .tcpClient:

                let tcp = TCPClient(
                    name: connection.name,
                    address: connection.address,
                    port: connection.port
                )


                tcp.onReceive = { [weak self] data in

                    DispatchQueue.main.async {

                        self?.receivedPacketCount += 1

                        self?.packetParser.receive(data)
                    }
                }


                tcp.onStatusChanged = { [weak self] connected in

                    DispatchQueue.main.async {

                        self?.connectionStates[connection.name] = connected

                        print(
                            connected ?
                            "🟢 \(connection.name) connected" :
                            "🔴 \(connection.name) disconnected"
                        )

                        if connected {
                            // Let the network know we exist shortly after connecting.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                self?.sendAnnounce()
                            }
                        }
                    }
                }


                interfaces.append(tcp)



            // MARK: RNode

            case .rNode:

                guard let config = connection.rnodeConfig else {
                    continue
                }


                let rnode = RNodeInterface(
                    config: config
                )


                rnode.onReceive = { [weak self] data in

                    DispatchQueue.main.async {

                        self?.receivedPacketCount += 1

                        self?.packetParser.receive(data)
                    }
                }


                interfaces.append(rnode)
            }
        }


        print("Loaded interfaces:", interfaces.count)
    }



    // MARK: - Interface Control

    func startAll() {

        for interface in interfaces {

            print("Starting:", interface.name)

            interface.start()
        }
    }


    func stopAll() {

        for interface in interfaces {

            interface.stop()
        }
    }



    // MARK: - Restart

    func restartAll() {

        print("Restarting interfaces...")

        stopAll()

        loadInterfaces()

        startAll()
    }



    // MARK: - Sending

    /// Sends raw (already HDLC-framed) bytes out every connected interface.
    /// Logs how many interfaces were actually eligible to send on, since
    /// "send() was called" and "bytes actually went somewhere" are two
    /// different things if nothing is connected.
    func send(_ framedData: Data) {

        let connectedInterfaces = interfaces.filter { $0.isConnected }

        guard !connectedInterfaces.isEmpty else {
            print("⚠️ send() called with \(framedData.count) bytes, but no interfaces are connected — nothing was sent.")
            return
        }

        for interface in connectedInterfaces {
            interface.send(data: framedData)
        }
    }


    /// Builds and sends an ANNOUNCE for your own identity, with your
    /// display name (from Settings) as app_data.
    func sendAnnounce() {

        let name = UserProfile.shared.displayName
        let appData = Data(name.utf8)

        guard let rawPacket = PacketBuilder.buildAnnouncePacket(appData: appData) else {
            print("⚠️ Could not build announce packet — this means IdentityStore has no private key, which shouldn't happen.")
            return
        }

        let framed = PacketBuilder.hdlcFrame(rawPacket)

        print("🔔 ANNOUNCE OUT — as \"\(name)\", destination \(ReticulumDestination.myDestinationHashHex), \(rawPacket.count) raw bytes / \(framed.count) framed bytes")

        send(framed)
    }


    /// Encrypts and sends a chat message to a peer whose public key is
    /// already known (from a prior announce or direct message).
    func sendMessage(text: String, to destinationHashHex: String, recipientPublicKey: Data) -> Bool {

        guard let recipient = ReticulumIdentity(publicKeyBytes: recipientPublicKey) else {
            print("✉️ MESSAGE OUT to \(destinationHashHex) FAILED — recipient public key (\(recipientPublicKey.count) bytes) is invalid.")
            return false
        }

        guard let envelope = MessageEnvelope.build(text: text) else {
            print("✉️ MESSAGE OUT to \(destinationHashHex) FAILED — could not build/sign the envelope.")
            return false
        }

        guard let destinationHash = Data(hexString: destinationHashHex) else {
            print("✉️ MESSAGE OUT to \(destinationHashHex) FAILED — that doesn't look like a valid hex destination hash.")
            return false
        }

        do {

            let ciphertext = try recipient.encrypt(envelope)
            let rawPacket = PacketBuilder.buildDataPacket(destinationHash: destinationHash, ciphertext: ciphertext)
            let framed = PacketBuilder.hdlcFrame(rawPacket)

            print("✉️ MESSAGE OUT to \(destinationHashHex) — \(rawPacket.count) raw bytes / \(framed.count) framed bytes")

            send(framed)
            return true

        } catch {
            print("✉️ MESSAGE OUT to \(destinationHashHex) FAILED — encryption threw: \(error)")
            return false
        }
    }
}


extension Data {

    init?(hexString: String) {

        var data = Data()
        var hex = hexString

        guard hex.count % 2 == 0 else {
            return nil
        }

        while !hex.isEmpty {
            let byteString = hex.prefix(2)

            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }

            data.append(byte)
            hex = String(hex.dropFirst(2))
        }

        self = data
    }

    /// Lowercase hex string, for debug logging.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
