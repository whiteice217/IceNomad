//
//  InterfaceManager.swift
//  IceNomad
//

import Foundation
import Combine
import OSLog


class InterfaceManager: ObservableObject {

    // MARK: - Shared instance
    //
    // A single shared instance, so every view (Connections, Messages,
    // Browser, Announce) sends and receives through the same actual
    // connections, instead of each owning an independent copy.

    static let shared = InterfaceManager()


    // MARK: - Properties

    @Published private(set) var interfaces: [ReticulumInterface] = []

    /// Matches SuggestedConnection.all's recommended "IceNomad Public
    /// Relay" entry's address (ConnectionsView.swift) — kept as a
    /// literal here rather than a cross-reference since that type lives
    /// in Features, which this Core-layer file can't import. Keep the
    /// two in sync if that entry's address ever changes.
    static let iceNomadPublicRelayHost = "rns.icenomad.net"

    /// Whether a connected TCP interface is actually IceNomad's own
    /// relay, not just some other TCP/RNode connection — BrowserState's
    /// Tux-cache tiers (real HTTP render, then Reticulum-cached .mu)
    /// only make sense to try over our own relay; anyone using a
    /// different relay or bridge falls straight to genuine live
    /// browsing instead (Bryan's explicit call, 2026-08-04).
    var isUsingIceNomadPublicRelay: Bool {
        interfaces.contains { interface in
            guard let tcpClient = interface as? TCPClient else { return false }
            return tcpClient.isConnected && tcpClient.address == Self.iceNomadPublicRelayHost
        }
    }

    @Published var connectionStates: [String: Bool] = [:]

    @Published var receivedPacketCount: Int = 0

    /// RNode interface name -> last CMD_STAT_BAT the device pushed —
    /// keyed the same way connectionStates is, since an RNodeInterface
    /// itself isn't Observable (mirrors the existing pattern rather than
    /// adding a second one).
    @Published var rnodeBatteryStatus: [String: RNodeBatteryStatus] = [:]

    /// interface name -> its "TCPInterface[name/host:port]"-style
    /// description, used for periodic tunnel-synthesis re-signalling.
    private var tcpInterfaceDescriptions: [String: String] = [:]

    private var tunnelSynthesisTimer: Timer?

    /// The most recently observed transport instance ID from any incoming
    /// frame with two address fields (HEADER_2) — i.e. our upstream
    /// relay's own identity. As a leaf client with a single upstream
    /// interface, every packet requiring relay always names the same
    /// transport ID here (whoever we're directly connected to), so this
    /// one value, learned passively from ordinary traffic like announces,
    /// is all that's needed to correctly address any outbound unicast
    /// packet. See PacketBuilder.buildDataPacket's doc comment for why a
    /// destination hash alone (HEADER_1) silently fails to reach anyone
    /// not on our own physical interface.
    private(set) var lastKnownTransportId: Data?


    // MARK: - Init

    init() {

        let myHash = ReticulumDestination.myDestinationHashHex
        let myLXMFHash = LXMFDestination.myDestinationHashHex
        let myIdentityHash = IdentityStore.shared.myIdentity.hash.hexString

        Log.identity.info("My identity hash: \(myIdentityHash, privacy: .public) — IceNomad: \(myHash, privacy: .public) — LXMF: \(myLXMFHash, privacy: .public)")

        LinkManager.shared.onIncomingLXMFMessage = { [weak self] fullEnvelope in
            self?.deliverDirectLXMFMessage(fullEnvelope)
        }

        // Periodically re-signal "this TCP connection carries traffic for
        // me" to the upstream node — see buildSynthesizeTunnelPacket's
        // doc comment. Without this, a connection that's been open and
        // idle for a while (relative to inactivity, not wall-clock —
        // announces alone don't count as far as the upstream reverse-
        // route table is concerned) silently loses its return path:
        // things we send keep going out fine, but replies addressed
        // back to us (a Link proof, a delivered message) have nowhere
        // to go and vanish upstream with zero trace on our end.
        tunnelSynthesisTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.sendSynthesizeTunnelToAllConnected()
        }
    }


    private func handle(frame: ReticulumFrame, source: ConnectionType) {

        if let transportId = frame.transportId {
            lastKnownTransportId = transportId
        }

        let packet = ReticulumPacket(frame: frame)

        if packet.isAnnounce {

            logAnnounceParseFailures(packet)
            PeerStore.shared.handle(frame: frame, source: source)
            return
        }

        if packet.packetType == "LINKREQUEST" {

            // The only destination we accept incoming links to is our
            // LXMF delivery destination — that's what lets real LXMF
            // clients deliver a message via DIRECT method.
            LinkManager.shared.handleIncomingLinkRequest(packet: packet)
            return
        }

        if packet.packetType == "PROOF" {

            // Either an LRPROOF completing a handshake we initiated, or
            // (rarely) a packet-delivery proof over a link we accepted.
            LinkManager.shared.handle(packet: packet)
            return
        }

        if packet.isData {

            // Try Link routing first: a DATA packet over an established
            // (or handshaking) link is addressed by link_id, which looks
            // just like any other destination hash at this layer.
            if LinkManager.shared.handle(packet: packet) {
                return
            }

            handleDataPacket(packet)
            return
        }
    }


    /// Announces arrive constantly (every few seconds on a live network)
    /// so logging each one would just be noise — only real parse
    /// failures are worth a log line here.
    private func logAnnounceParseFailures(_ packet: ReticulumPacket) {

        guard let destinationHash = packet.destinationHash else {
            Log.reticulum.error("Incoming announce had no parseable destination hash")
            return
        }

        if AnnouncePacket(packet: packet) == nil {
            Log.reticulum.error("Incoming announce from \(destinationHash.hexString, privacy: .public) didn't parse as a valid announce payload")
        }
    }


    /// A DATA packet carries no sender address by design (Reticulum's
    /// "initiator anonymity") — only whether it's addressed to us. We
    /// listen on two destinations: our own icenomad.chat one (using our
    /// own envelope, which embeds the sender's key) and a real
    /// lxmf.delivery one (using real LXMF's format, which requires
    /// already knowing the sender from a prior announce).
    private func handleDataPacket(_ packet: ReticulumPacket) {

        guard let destinationHash = packet.destinationHash else {
            Log.reticulum.error("Incoming data packet had no parseable destination hash")
            return
        }

        if destinationHash == ReticulumDestination.myDestinationHash {
            handleIceNomadDataPacket(packet)
            return
        }

        if destinationHash == LXMFDestination.myDestinationHash {
            handleLXMFDataPacket(packet)
            return
        }

        // Addressed to someone else — normal, happens for every relayed
        // packet on a shared transport node. Not worth logging.
    }


    private func handleIceNomadDataPacket(_ packet: ReticulumPacket) {

        do {

            let plaintext = try IdentityStore.shared.myIdentity.decrypt(packet.payload)

            guard let (senderHex, senderPublicKey, text) = MessageEnvelope.parse(plaintext) else {
                Log.lxmf.error("Decrypted IceNomad packet, but envelope verification failed (bad signature or malformed envelope) — dropped")
                return
            }

            PeerStore.shared.recordDirectContact(
                destinationHashHex: senderHex,
                identityPublicKey: senderPublicKey
            )

            MessageStore.shared.receive(text: text, from: senderHex)

        } catch {
            Log.lxmf.error("IceNomad packet decrypt failed (HMAC/AES error — likely wasn't actually encrypted to us, or is corrupt): \(error)")
        }
    }


    /// Real LXMF messages don't carry the sender's public key — only a
    /// 16-byte source hash — so verifying one needs the sender's
    /// identity already resolved, from either a cached announce or (if
    /// we don't have one yet) actively asking the network for it, same
    /// as `PeerStore.resolveIdentity` already does before connecting to
    /// someone new. A message from someone we haven't directly heard
    /// announce yet is a completely normal occurrence — their announce
    /// may just not have reached us yet — not a reason to give up
    /// immediately (confirmed this was silently dropping real, valid
    /// messages: the sender's Link was accepted fine, only the message
    /// itself got rejected here).
    private func handleLXMFDataPacket(_ packet: ReticulumPacket) {

        do {

            let plaintext = try IdentityStore.shared.myIdentity.decrypt(packet.payload)

            // Opportunistic (single-packet) LXMF wire format is
            // source_hash(16) + signature(64) + payload — the
            // destination_hash is NOT on the wire (real LXMF strips it
            // since it's redundant with the packet's own addressing;
            // RNS.LXMRouter.delivery_packet() reconstructs the full
            // envelope as `packet.destination.hash + data` before
            // parsing, which is exactly what parseOpportunistic does).
            guard plaintext.count > 80 else {
                Log.lxmf.error("Decrypted LXMF payload too short to be a valid message — dropped")
                return
            }

            let sourceHash = Data(plaintext.prefix(16))
            let sourceHex = sourceHash.hexString

            resolveSenderThen(sourceHex) { [weak self] senderPublicKey in

                guard let self else { return }

                guard let message = LXMFMessage.parseOpportunistic(plaintext, myDestinationHash: LXMFDestination.myDestinationHash, senderPublicKey: senderPublicKey) else {
                    Log.lxmf.error("LXMF message from \(sourceHex, privacy: .public) failed signature verification or parsing — dropped")
                    return
                }

                MessageStore.shared.receive(text: message.content, from: sourceHex)
            }

        } catch {
            Log.lxmf.error("LXMF packet decrypt failed (HMAC/AES error — likely wasn't actually encrypted to us, or is corrupt): \(error)")
        }
    }


    /// A message delivered via LXMF's DIRECT method, over a Link we
    /// accepted (LinkManager.handleIncomingLinkRequest). Unlike
    /// opportunistic delivery, the full envelope (including our own
    /// destination_hash) is on the wire as-is — `__as_packet()`/
    /// `__as_resource()` send `self.packed` unstripped for DIRECT.
    private func deliverDirectLXMFMessage(_ fullEnvelope: Data) {

        guard fullEnvelope.count > 96 else {
            Log.lxmf.error("Decrypted LXMF (DIRECT) payload too short to be a valid message — dropped")
            return
        }

        let sourceHash = Data(fullEnvelope.dropFirst(16).prefix(16))
        let sourceHex = sourceHash.hexString

        resolveSenderThen(sourceHex) { senderPublicKey in

            guard let message = LXMFMessage.parse(fullEnvelope, senderPublicKey: senderPublicKey) else {
                Log.lxmf.error("LXMF (DIRECT) message from \(sourceHex, privacy: .public) failed signature verification or parsing — dropped")
                return
            }

            MessageStore.shared.receive(text: message.content, from: sourceHex)
        }
    }


    /// Shared by both delivery paths above: use the sender's cached
    /// identity if we already have it, otherwise actively resolve it
    /// (PATH_REQUEST + poll, same mechanism `PeerStore.resolveIdentity`
    /// already uses elsewhere) before calling back — instead of
    /// dropping every message from a sender we haven't happened to
    /// cache an announce from yet.
    private func resolveSenderThen(_ sourceHex: String, _ onResolved: @escaping (Data) -> Void) {

        if let peer = PeerStore.shared.peers.first(where: { $0.destinationHashHex == sourceHex }) {
            onResolved(peer.identityPublicKey)
            return
        }

        Log.lxmf.info("LXMF message from \(sourceHex, privacy: .public) — no cached identity yet, resolving before verifying")

        PeerStore.shared.resolveIdentity(for: sourceHex) { peer in

            guard let peer else {
                Log.lxmf.error("LXMF message from \(sourceHex, privacy: .public) — identity resolution timed out, dropped")
                return
            }

            onResolved(peer.identityPublicKey)
        }
    }


    // MARK: - Load Interfaces

    func loadInterfaces() {

        interfaces.removeAll()

        Log.network.info("Loading interfaces...")

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

                // Each interface gets its own parser — sharing one across
                // multiple simultaneous byte streams would corrupt
                // whichever frame was mid-assembly on the other stream.
                let parser = PacketParser()

                parser.onFrameReceived = { [weak self] frame in

                    DispatchQueue.main.async {

                        self?.handle(frame: frame, source: .tcpClient)
                    }
                }

                tcp.onReceive = { [weak self] data in

                    DispatchQueue.main.async {

                        self?.receivedPacketCount += 1

                        parser.receive(data)
                    }
                }


                tcp.onStatusChanged = { [weak self] connected in

                    DispatchQueue.main.async {

                        self?.connectionStates[connection.name] = connected

                        if connected {
                            Log.network.info("\(connection.name, privacy: .public) connected")
                        } else {
                            Log.network.error("\(connection.name, privacy: .public) disconnected")
                        }

                        if connected {

                            self?.tcpInterfaceDescriptions[connection.name] =
                                "TCPInterface[\(connection.name)/\(connection.address):\(connection.port)]"

                            // Let the network know we exist shortly after connecting.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                self?.sendAnnounce()
                            }

                            // Fixes the specific "cold start" case: a
                            // fresh connection has no reverse-route
                            // history yet upstream, so the very first
                            // Link/message attempt right after connecting
                            // needs this signalled immediately rather
                            // than waiting for the next periodic tick.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self?.sendSynthesizeTunnel(interfaceName: connection.name)
                            }

                        } else {
                            self?.tcpInterfaceDescriptions.removeValue(forKey: connection.name)
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

                        // RNode's onReceive already hands us a single,
                        // fully-unwrapped Reticulum packet (KISS framing
                        // was the transport's own envelope, stripped by
                        // RNodeInterface) — no HDLC extraction needed, just
                        // the leading throwaway byte ReticulumFrame expects
                        // in place of TCP's marker byte.
                        let frame = ReticulumFrame(data: Data([0x00]) + data)
                        self?.handle(frame: frame, source: .rNode)
                    }
                }


                rnode.onStatusChanged = { [weak self] connected in

                    DispatchQueue.main.async {

                        self?.connectionStates[connection.name] = connected

                        if connected {
                            Log.network.info("\(connection.name, privacy: .public) connected")
                        } else {
                            Log.network.error("\(connection.name, privacy: .public) disconnected")
                        }

                        if connected {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                self?.sendAnnounce()
                            }
                        }
                    }
                }


                rnode.onBatteryUpdate = { [weak self] state, percent in

                    DispatchQueue.main.async {
                        self?.rnodeBatteryStatus[connection.name] = RNodeBatteryStatus(state: state, percent: percent)
                    }
                }


                interfaces.append(rnode)
            }
        }


        Log.network.info("Loaded \(self.interfaces.count) interface(s)")
    }



    // MARK: - Interface Control

    func startAll() {

        for interface in interfaces {

            Log.network.info("Starting interface \(interface.name, privacy: .public)")

            interface.start()
        }
    }


    func stopAll() {

        for interface in interfaces {

            interface.stop()
        }
    }


    /// Looks up the live RNodeInterface instance for a saved connection,
    /// so device-control UI (reboot, display, WiFi settings) can call its
    /// methods directly — those are fire-and-forget commands to the
    /// physical board, not local config, so there's no need to route
    /// them through Connection/RNodeConfig the way radio parameters are.
    /// nil if that connection isn't currently running (e.g. mid-restart,
    /// or a different transport failed to connect).
    func rnodeInterface(named name: String) -> RNodeInterface? {

        interfaces.first { $0.name == name } as? RNodeInterface
    }



    // MARK: - Restart

    func restartAll() {

        Log.network.info("Restarting interfaces...")

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
            Log.network.error("send() called with \(framedData.count) bytes, but no interfaces are connected — nothing was sent")
            return
        }

        for interface in connectedInterfaces {
            interface.send(data: framedData)
        }
    }


    /// Builds and sends ANNOUNCEs for both destinations: our own
    /// icenomad.chat one, and a real lxmf.delivery one (so genuine
    /// NomadNet/Sideband clients can see and address you).
    func sendAnnounce() {

        let name = UserProfile.shared.displayName

        if let rawPacket = PacketBuilder.buildAnnouncePacket(
            destinationHash: ReticulumDestination.myDestinationHash,
            nameHash: ReticulumDestination.nameHash,
            appData: Data(name.utf8)
        ) {
            let framed = PacketBuilder.hdlcFrame(rawPacket)
            Log.reticulum.info("Announce out (IceNomad) as \"\(name, privacy: .public)\"")
            send(framed)
        } else {
            Log.identity.fault("Could not build IceNomad announce packet — this means IdentityStore has no private key, which shouldn't happen")
        }

        if let rawPacket = PacketBuilder.buildAnnouncePacket(
            destinationHash: LXMFDestination.myDestinationHash,
            nameHash: LXMFDestination.nameHash,
            appData: LXMFDestination.announceAppData(displayName: name)
        ) {
            let framed = PacketBuilder.hdlcFrame(rawPacket)
            Log.lxmf.info("Announce out (LXMF) as \"\(name, privacy: .public)\"")
            send(framed)
        } else {
            Log.lxmf.error("Could not build LXMF announce packet")
        }

        UserProfile.shared.markAnnounced()
    }


    /// Re-signals "this TCP connection carries traffic for me" for one
    /// named interface — see buildSynthesizeTunnelPacket's doc comment.
    private func sendSynthesizeTunnel(interfaceName: String) {

        guard connectionStates[interfaceName] == true,
              let description = tcpInterfaceDescriptions[interfaceName],
              let rawPacket = PacketBuilder.buildSynthesizeTunnelPacket(interfaceDescription: description)
        else {
            return
        }

        Log.network.debug("Tunnel synthesize for \(interfaceName, privacy: .public)")
        send(PacketBuilder.hdlcFrame(rawPacket))
    }


    private func sendSynthesizeTunnelToAllConnected() {

        for name in tcpInterfaceDescriptions.keys {
            sendSynthesizeTunnel(interfaceName: name)
        }
    }


    /// Encrypts and sends a real LXMF message to a peer whose public key
    /// is already known (from a prior announce).
    func sendMessage(text: String, to destinationHashHex: String, recipientPublicKey: Data) -> Bool {

        guard let recipient = ReticulumIdentity(publicKeyBytes: recipientPublicKey) else {
            Log.lxmf.error("Message out to \(destinationHashHex, privacy: .public) FAILED — recipient public key (\(recipientPublicKey.count) bytes) is invalid")
            return false
        }

        guard let destinationHash = Data(hexString: destinationHashHex) else {
            Log.lxmf.error("Message out to \(destinationHashHex, privacy: .public) FAILED — not a valid hex destination hash")
            return false
        }

        guard let message = LXMFMessage.compose(to: destinationHash, content: text) else {
            Log.lxmf.error("Message out to \(destinationHashHex, privacy: .public) FAILED — could not build/sign the LXMF message")
            return false
        }

        do {

            let ciphertext = try recipient.encrypt(message.opportunisticPackedData)
            let rawPacket = PacketBuilder.buildDataPacket(destinationHash: destinationHash, ciphertext: ciphertext, transportId: lastKnownTransportId)
            let framed = PacketBuilder.hdlcFrame(rawPacket)

            send(framed)
            return true

        } catch {
            Log.lxmf.error("Message out to \(destinationHashHex, privacy: .public) FAILED — encryption threw: \(error)")
            return false
        }
    }


    /// Sends an LXMF message via DIRECT method — establishes a Link and
    /// pushes the full (unstripped) envelope over it, matching what real
    /// LXMF clients use as their default/preferred delivery method.
    /// Confirmed against a real LXMF listener that plain OPPORTUNISTIC
    /// packets to this network don't arrive reliably, while DIRECT
    /// delivery over a Link consistently does — reuses the same Link
    /// infrastructure (with active path-resolution) already proven out
    /// for NomadNet browsing.
    func sendDirectMessage(text: String, to destinationHashHex: String, completion: @escaping (Bool) -> Void) {

        guard let destinationHash = Data(hexString: destinationHashHex) else {
            Log.lxmf.error("Message out (DIRECT) to \(destinationHashHex, privacy: .public) FAILED — not a valid hex destination hash")
            completion(false)
            return
        }

        guard let message = LXMFMessage.compose(to: destinationHash, content: text) else {
            Log.lxmf.error("Message out (DIRECT) to \(destinationHashHex, privacy: .public) FAILED — could not build/sign the LXMF message")
            completion(false)
            return
        }

        LinkManager.shared.connect(to: destinationHashHex) { result in

            switch result {

            case .failure(let error):
                Log.lxmf.notice("Message out (DIRECT) to \(destinationHashHex, privacy: .public) — link failed (\(String(describing: error))), falling back to opportunistic")
                completion(false)

            case .success(let link):

                let succeeded = link.sendPayload(message.packedData)

                if !succeeded {
                    Log.lxmf.error("Message out (DIRECT) to \(destinationHashHex, privacy: .public) FAILED — link not active")
                }

                completion(succeeded)
            }
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
