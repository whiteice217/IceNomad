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

        packetParser.onFrameReceived = { [weak self] frame in

            DispatchQueue.main.async {

                self?.handle(frame: frame)
            }
        }
    }


    private func handle(frame: ReticulumFrame) {

        let packet = ReticulumPacket(frame: frame)

        if packet.isAnnounce {

            PeerStore.shared.handle(frame: frame)
            return
        }

        if packet.isData {

            handleDataPacket(packet)
            return
        }
    }


    /// A DATA packet carries no sender address by design (Reticulum's
    /// "initiator anonymity") — only whether it's addressed to us. If it
    /// is, decrypt with our own identity and unpack the sender info
    /// IceNomad embeds inside the envelope (see MessageEnvelope.swift).
    private func handleDataPacket(_ packet: ReticulumPacket) {

        guard let destinationHash = packet.destinationHash,
              destinationHash == ReticulumDestination.myDestinationHash
        else {
            return // not addressed to us
        }

        do {

            let plaintext = try IdentityStore.shared.myIdentity.decrypt(packet.payload)

            guard let (senderHex, senderPublicKey, text) = MessageEnvelope.parse(plaintext) else {
                print("⚠️ Received a message that failed envelope verification — dropped.")
                return
            }

            PeerStore.shared.recordDirectContact(
                destinationHashHex: senderHex,
                identityPublicKey: senderPublicKey
            )

            MessageStore.shared.receive(text: text, from: senderHex)

        } catch {
            print("⚠️ Failed to decrypt an incoming DATA packet: \(error)")
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
    func send(_ framedData: Data) {

        for interface in interfaces where interface.isConnected {
            interface.send(data: framedData)
        }
    }


    /// Builds and sends an ANNOUNCE for your own identity, with your
    /// display name (from Settings) as app_data.
    func sendAnnounce() {

        let name = UserProfile.shared.displayName
        let appData = Data(name.utf8)

        guard let rawPacket = PacketBuilder.buildAnnouncePacket(appData: appData) else {
            print("⚠️ Could not build announce packet.")
            return
        }

        let framed = PacketBuilder.hdlcFrame(rawPacket)
        send(framed)

        print("📣 Sent announce as \"\(name)\"")
    }


    /// Encrypts and sends a chat message to a peer whose public key is
    /// already known (from a prior announce or direct message).
    func sendMessage(text: String, to destinationHashHex: String, recipientPublicKey: Data) -> Bool {

        guard let recipient = ReticulumIdentity(publicKeyBytes: recipientPublicKey) else {
            return false
        }

        guard let envelope = MessageEnvelope.build(text: text) else {
            return false
        }

        guard let destinationHash = Data(hexString: destinationHashHex) else {
            return false
        }

        do {

            let ciphertext = try recipient.encrypt(envelope)
            let rawPacket = PacketBuilder.buildDataPacket(destinationHash: destinationHash, ciphertext: ciphertext)
            let framed = PacketBuilder.hdlcFrame(rawPacket)

            send(framed)
            return true

        } catch {
            print("⚠️ Failed to encrypt/send message: \(error)")
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
}
