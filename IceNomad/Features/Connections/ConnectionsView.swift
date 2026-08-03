//
//  ConnectionsView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI
import UIKit

// MARK: - Models

enum ConnectionType: String, CaseIterable, Identifiable, Codable {
    case tcpClient = "TCP Client"
    case rNode = "RNode"

    var id: String { rawValue }
}

// MARK: - RNode Config

/// RNode Firmware exposes the exact same KISS command protocol over
/// three different transports — USB serial, Bluetooth (Classic SPP or
/// BLE, board-dependent), and, on boards with `HAS_WIFI` (confirmed in
/// firmware source: Heltec32 V3/V4, T3S3, T-Deck, T-Beam Supreme, XIAO
/// S3), a raw TCP server on port 7633 in either station (join an
/// existing network) or access-point mode. Bluetooth's ~10-30m range is
/// a real limitation for something like mounting the radio up a tree
/// for elevation — WiFi's range is much longer, and since it's the same
/// wire protocol either way, only the transport underneath RNodeInterface
/// needs to change, not the KISS layer itself.
enum RNodeConnectionMethod: String, Codable, Identifiable {
    case bluetooth = "Bluetooth"
    case usb = "USB"
    case wifi = "WiFi"

    var id: String { rawValue }

    /// Not a plain CaseIterable — USB-serial device access needs raw
    /// POSIX open()/termios, which iOS doesn't allow third-party apps
    /// (no MFi certification here), same restriction as Firmware Tools.
    /// Hidden from the picker entirely on iOS rather than shown and
    /// failing at connect time.
    static var allCases: [RNodeConnectionMethod] {
        #if targetEnvironment(macCatalyst)
        [.bluetooth, .usb, .wifi]
        #else
        [.bluetooth, .wifi]
        #endif
    }
}

struct RNodeConfig: Codable {
    var name: String = ""
    var device: String = ""          // display name of the paired BLE peripheral
    var peripheralIdentifier: String = ""   // CBPeripheral.identifier.uuidString — used to reconnect

    var connectionMethod: RNodeConnectionMethod = .bluetooth
    /// The RNode's own IP when in WiFi mode — its AP-mode default is
    /// 10.0.0.1 (confirmed in firmware source), or whatever your router
    /// hands out in station mode.
    var wifiHost: String = ""
    var wifiPort: String = "7633"
    /// /dev/cu.* path for a directly USB-connected RNode — Mac Catalyst
    /// only, same restriction as connectionMethod.usb generally.
    var usbSerialPath: String = ""

    var freqGHz: String = "0"
    var freqMHz: String = "915"
    var freqKHz: String = "0"
    var freqHz: String = "0"

    var bandwidth: String = "125 KHz"
    var transmitPower: String = "7"
    var spreadingFactor: String = "8"
    var codingRate: String = "5"

    var frequencyHzString: String {
        
        let ghz = Int(freqGHz) ?? 0
        let mhz = Int(freqMHz) ?? 0
        let khz = Int(freqKHz) ?? 0
        let hz = Int(freqHz) ?? 0

        let totalHz = (ghz * 1_000_000_000) +
                      (mhz * 1_000_000) +
                      (khz * 1_000) +
                      (hz * 1)

        return String(format: "%012d", totalHz)
    }


    /// Same value as frequencyHzString, but as the raw UInt32 Hz the
    /// RNode's CMD_FREQUENCY KISS command actually expects on the wire.
    var frequencyHz: UInt32 {

        let ghz = UInt32(freqGHz) ?? 0
        let mhz = UInt32(freqMHz) ?? 0
        let khz = UInt32(freqKHz) ?? 0
        let hz = UInt32(freqHz) ?? 0

        return (ghz * 1_000_000_000) + (mhz * 1_000_000) + (khz * 1_000) + hz
    }


    /// Parses a "125 KHz" / "7.8 KHz" style bandwidth label into raw Hz,
    /// for CMD_BANDWIDTH — RNode firmware expects the exact Hz value,
    /// not a picker label.
    var bandwidthHz: UInt32 {

        let numeric = bandwidth.split(separator: " ").first.map(String.init) ?? "0"

        guard let khz = Double(numeric) else {
            return 125_000
        }

        return UInt32((khz * 1000).rounded())
    }


    init() {}

    /// Custom decode so existing saved connections (from before WiFi
    /// support existed) don't fail to load entirely for missing keys —
    /// the three new fields fall back to their defaults (Bluetooth,
    /// empty host, port 7633) instead of the whole `RNodeConfig`
    /// silently vanishing from `ConnectionStorage`.
    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decode(String.self, forKey: .name)
        device = try container.decode(String.self, forKey: .device)
        peripheralIdentifier = try container.decode(String.self, forKey: .peripheralIdentifier)

        connectionMethod = try container.decodeIfPresent(RNodeConnectionMethod.self, forKey: .connectionMethod) ?? .bluetooth
        wifiHost = try container.decodeIfPresent(String.self, forKey: .wifiHost) ?? ""
        wifiPort = try container.decodeIfPresent(String.self, forKey: .wifiPort) ?? "7633"
        usbSerialPath = try container.decodeIfPresent(String.self, forKey: .usbSerialPath) ?? ""

        freqGHz = try container.decode(String.self, forKey: .freqGHz)
        freqMHz = try container.decode(String.self, forKey: .freqMHz)
        freqKHz = try container.decode(String.self, forKey: .freqKHz)
        freqHz = try container.decode(String.self, forKey: .freqHz)

        bandwidth = try container.decode(String.self, forKey: .bandwidth)
        transmitPower = try container.decode(String.self, forKey: .transmitPower)
        spreadingFactor = try container.decode(String.self, forKey: .spreadingFactor)
        codingRate = try container.decode(String.self, forKey: .codingRate)
    }


    var transmitPowerByte: UInt8 {
        UInt8(clamping: Int(transmitPower) ?? 7)
    }


    var spreadingFactorByte: UInt8 {
        UInt8(clamping: Int(spreadingFactor) ?? 8)
    }


    var codingRateByte: UInt8 {
        UInt8(clamping: Int(codingRate) ?? 5)
    }
}

// MARK: - Connection

struct Connection: Identifiable, Codable {
    var id: UUID = UUID()

    var name: String
    var address: String = ""
    var port: String = ""
    var type: ConnectionType
    var rnodeConfig: RNodeConfig? = nil

    var isConnected: Bool = false
}

/// A pre-filled TCP option shown (grayed out, tap to fill the form rather
/// than added silently) on first boot before the user has configured
/// anything — otherwise a brand new user faces a blank list with no idea
/// what a real address/port even looks like.
struct SuggestedConnection: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let port: String
    var isRecommended: Bool = false

    /// The canonical list — was a private copy inside ConnectionsView
    /// until the first-run setup wizard needed the exact same options.
    /// IceNomad's own relay first (recommended); beyond that, real
    /// community-run public Reticulum hubs pulled from the live
    /// directory at directory.rns.recipes — verify that list again
    /// before assuming any of these are still up if a future session
    /// revisits this, since they're run by other people, not IceNomad.
    static let all: [SuggestedConnection] = [
        SuggestedConnection(name: "IceNomad Public Relay", address: "rns.icenomad.net", port: "4242", isRecommended: true),
        SuggestedConnection(name: "RMAP", address: "rmap.world", port: "4242"),
        SuggestedConnection(name: "Sydney RNS", address: "sydney.reticulum.au", port: "4242"),
        SuggestedConnection(name: "Birdsnet BR", address: "rns.birdsnet.com.br", port: "4242"),
        SuggestedConnection(name: "Inertia.Chat", address: "use.inertia.chat", port: "4242"),
    ]
}

// MARK: - State

enum AddState: Equatable {
    case idle
    case choosingType
    case enteringDetails(ConnectionType)
    case editing(UUID)
}

// MARK: - View

struct ConnectionsView: View {

    @Binding var selectedTab: AppTab
    /// Set after a successful scan resolves to an LXMF address —
    /// MessagesView observes this the same way it does for a Micron
    /// `lxmf@hash` link tap.
    @Binding var pendingChatHex: String?
    /// Set after a successful scan resolves to a NomadNet page — same
    /// cross-tab hint BrowserView already observes for the Announce
    /// tab's "Browse" swipe action.
    @Binding var pendingBrowseHex: String?

    @State private var connections: [Connection] = ConnectionStorage.shared.load()
    @State private var addState: AddState = .idle
    @ObservedObject private var interfaceManager = InterfaceManager.shared
    @State private var isRefreshing = false
    @State private var isShowingRNodePairing = false
    @State private var usbSerialPorts: [String] = []
    @State private var controllingConnection: Connection?
    @State private var isShowingAddressQRCode = false
    @State private var isShowingScanner = false
    @State private var pendingScannedCode: ScannedCode?
    @State private var scanErrorMessage: String?
    
    // TCP
    @State private var name = ""
    @State private var address = ""
    @State private var port = ""
    
    // RNode
    @State private var rnode = RNodeConfig()

    /// Shown only while the user has no TCP client configured yet —
    /// tapping one pre-fills the TCP form rather than adding silently,
    /// so the user still confirms with Save. See SuggestedConnection.all
    /// for the actual list (shared with the first-run setup wizard).
    private let suggestedConnections = SuggestedConnection.all


    var body: some View {
        
        NavigationStack {

            VStack {

                if connections.isEmpty {

                    ScrollView {

                        VStack(spacing: 20) {

                            myAddressesCard
                                .padding(.horizontal)
                                .padding(.top, 8)

                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 48))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.top, 40)

                            VStack(spacing: 8) {

                                Text("No Connections Yet")
                                    .font(.title3.weight(.semibold))

                                Text("IceNomad needs at least one connection to reach the Reticulum network. Add one to start seeing announces and messages.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }

                            VStack(alignment: .leading, spacing: 16) {

                                instructionRow(
                                    icon: "network",
                                    color: Theme.tcpGreen,
                                    title: "TCP Connection",
                                    body: "Connect to a Reticulum node over the internet or your local network. You'll need its address (hostname or IP) and port — ask whoever runs the node, or use a public one."
                                )

                                instructionRow(
                                    icon: "wave.3.right",
                                    color: Theme.rnodeBlue,
                                    title: "RNode (Bluetooth/USB)",
                                    body: "Pair a physical RNode-compatible LoRa radio. Turn it on and make sure it's paired in Bluetooth settings (or connected via USB) before adding it here."
                                )
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 16)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal)

                            if !suggestedConnections.isEmpty {

                                VStack(alignment: .leading, spacing: 8) {

                                    Text("Quick Start")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(.horizontal)

                                    ForEach(suggestedConnections) { suggestion in
                                        suggestedConnectionRow(suggestion)
                                            .padding(.horizontal)
                                    }
                                }
                            }

                            Button {
                                addState = .choosingType
                            } label: {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("Add Connection")
                                }
                                .padding(.horizontal, 20)
                            }
                            .buttonStyle(.borderedProminent)


                            if addState != .idle {
                                Divider()
                                addFlowView
                            }

                            // First-run screen — the natural place to
                            // mention this is a hobby project someone
                            // built and maintains out of pocket, for
                            // anyone who wants to help keep it going, and
                            // that bug reports have a real place to land.
                            VStack(spacing: 4) {

                                Link(destination: URL(string: "https://github.com/whiteice217/IceNomad")!) {

                                    Label("Enjoying IceNomad? Feel free to donate", systemImage: "heart.fill")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                Link(destination: URL(string: "https://github.com/whiteice217/IceNomad/issues")!) {

                                    Label("Found a bug? Report it on GitHub", systemImage: "ladybug")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.bottom, 24)
                    }

                } else {

                    List {

                        Section {
                            myAddressesCard
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        ForEach(connections) { conn in

                        // A per-row Menu instead of .swipeActions — a
                        // swipe gesture doesn't exist on a Mac trackpad
                        // click, confirmed not working there. Tap/click
                        // on the ellipsis behaves the same on both.
                        HStack(alignment: .top, spacing: 8) {

                        VStack(alignment: .leading, spacing: 8) {

                            HStack(spacing: 8) {

                                Circle()
                                    .fill(
                                        interfaceManager.interfaces.contains {
                                            $0.name == conn.name && $0.isConnected
                                        }
                                        ? Theme.success
                                        : Theme.danger
                                    )
                                    .frame(width: 10, height: 10)

                                Text(conn.name)
                                    .font(.headline)
                            }

                            switch conn.type {

                            case .tcpClient:

                                VStack(alignment: .leading, spacing: 6) {

                                    Text("Host: \(conn.address)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)

                                    Text("Port: \(conn.port)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)

                                    HStack(spacing: 4) {
                                        Image(systemName: "network")
                                        Text("TCP Client")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Theme.tcpGreen)
                                }

                            case .rNode:

                                if let rnode = conn.rnodeConfig {

                                    VStack(alignment: .leading) {

                                        Text("Frequency: \(rnode.frequencyHzString)")
                                        Text("Bandwidth: \(rnode.bandwidth)")
                                        Text("Power: \(rnode.transmitPower)")

                                        HStack(spacing: 4) {

                                            Image(systemName: rnodeConnectionIcon(rnode.connectionMethod))
                                            Text("RNode via \(rnode.connectionMethod.rawValue)")

                                            if let battery = interfaceManager.rnodeBatteryStatus[conn.name] {

                                                Spacer(minLength: 6)
                                                Label("\(battery.percent)%", systemImage: batteryIcon(battery))
                                                    .foregroundStyle(battery.percent < 20 && battery.state == .discharging ? Theme.danger : Theme.textSecondary)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(Theme.rnodeBlue)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 8)

                        Menu {

                            Button {
                                editConnection(conn)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            if conn.type == .rNode {

                                Button {
                                    controllingConnection = conn
                                } label: {
                                    Label("Radio Controls", systemImage: "slider.horizontal.3")
                                }
                            }

                            Button(role: .destructive) {
                                deleteConnection(conn)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        }
                        }
                    }
                    .listRowSpacing(12)
                    .listRowBackground(Theme.surface)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)


                    Button {
                        addState = .choosingType
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Connection")
                        }
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom)


                    if addState != .idle {
                        Divider()
                        addFlowView
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Connections")
            .toolbar {

                ToolbarItem(placement: .topBarLeading) {

                    Button {
                        isShowingScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {

                        isRefreshing = true

                        interfaceManager.restartAll()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isRefreshing = false
                        }

                    } label: {

                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(
                                isRefreshing ?
                                .linear(duration: 1)
                                .repeatForever(autoreverses: false)
                                : .default,
                                value: isRefreshing
                            )
                    }
                }
            }
            // Routing (tab switch + cross-tab pending-hex) has to happen
            // AFTER the scanner sheet has actually finished dismissing —
            // QRScannerSheet calls its own dismiss() right after onScan
            // fires, so setting selectedTab/pendingChatHex synchronously
            // inside that same callback races the sheet's own dismissal
            // animation and the navigation silently gets dropped (this is
            // why a scan routed to the Messages tab but never actually
            // pushed a ChatView). Stashing the result and acting on it in
            // sheet(onDismiss:) — which SwiftUI guarantees fires only once
            // the sheet is fully gone — removes the race entirely.
            .sheet(isPresented: $isShowingScanner, onDismiss: {

                if let scanned = pendingScannedCode {
                    pendingScannedCode = nil
                    handleScan(scanned)
                }

            }) {
                QRScannerSheet { scanned in
                    pendingScannedCode = scanned
                }
            }
            .alert("Couldn't Read That Code", isPresented: scanErrorBinding) {

                Button("OK", role: .cancel) {}

            } message: {
                Text("That QR code isn't a recognized IceNomad address.")
            }
            .sheet(item: $controllingConnection) { conn in

                RNodeControlsView(
                    connectionName: conn.name,
                    connectionMethod: conn.rnodeConfig?.connectionMethod ?? .bluetooth
                )
            }
        }
    }


    /// Routes a scanned code to wherever it belongs — messaging for an
    /// LXMF address, browsing for a NomadNet page. Once stickers exist in
    /// the wild, this is the "walk up, scan, get dropped into the right
    /// place" moment the whole feature is for.
    private func handleScan(_ scanned: ScannedCode) {

        switch scanned {

        case .lxmf(let hex):
            switchTabThenRoute(to: .messages) { pendingChatHex = hex }

        case .nomadNet(let hex, _):
            switchTabThenRoute(to: .browser) { pendingBrowseHex = hex }

        case .unrecognized:
            scanErrorMessage = "Unrecognized code"
        }
    }


    /// Switches tabs first, then sets the routing hint one run-loop tick
    /// later — setting both in the same synchronous pass (as this used
    /// to do) was unreliable specifically coming out of this sheet's
    /// onDismiss: the destination tab's view isn't reliably ready to
    /// observe the pendingChatHex/pendingBrowseHex change in the same
    /// transaction as the tab switch itself, so the change gets missed.
    private func switchTabThenRoute(to tab: AppTab, _ setHint: @escaping () -> Void) {

        selectedTab = tab

        DispatchQueue.main.async {
            setHint()
        }
    }


    private var scanErrorBinding: Binding<Bool> {

        Binding(
            get: { scanErrorMessage != nil },
            set: { if !$0 { scanErrorMessage = nil } }
        )
    }
// MARK: - FLOW
    
    @ViewBuilder
    var addFlowView: some View {
        
        switch addState {
            
        case .idle:
            EmptyView()
            
        case .choosingType:
            VStack(spacing: 20) {
                
                Text("Select Connection Type")
                    .font(.headline)
                
                Button {
                    resetAll()
                    addState = .enteringDetails(.tcpClient)
                } label: {
                    Text("TCP Client")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                
                Button {
                    resetAll()
                    addState = .enteringDetails(.rNode)
                } label: {
                    Text("RNode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                
                Button {
                    addState = .idle
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
            
            
        case .enteringDetails(let type):
            
            if type == .tcpClient {
                tcpForm()
            } else {
                rnodeForm()
            }
            
            
        case .editing(let id):
            
            if let connection = connections.first(where: { $0.id == id }) {
                
                if connection.type == .tcpClient {
                    tcpForm()
                } else {
                    rnodeForm()
                }
                
            } else {
                EmptyView()
            }
        }
    }
    // MARK: - TCP FORM
    
    func tcpForm() -> some View {
        
        VStack(spacing: 12) {
            
            Text("TCP Client")
                .font(.headline)
            
            labeledField("Name", text: $name)
            labeledField("Address", text: $address)
            labeledField("Port", text: $port, keyboard: .numberPad)
            
            
            HStack(spacing: 20) {
                
                Button {
                    
                    switch addState {
                        
                    case .editing(let id):
                        
                        if let index = connections.firstIndex(where: {
                            $0.id == id
                        }) {
                            
                            connections[index].name = name
                            connections[index].address = address
                            connections[index].port = port
                        }
                        
                        
                    default:
                        
                        connections.append(
                            Connection(
                                name: name,
                                address: address,
                                port: port,
                                type: .tcpClient
                            )
                        )
                    }
                    
                    
                    ConnectionStorage.shared.save(connections)
                    interfaceManager.restartAll()

                    resetAll()
                    addState = .idle


                } label: {

                    Text("Save")
                        .frame(maxWidth: .infinity)

                }
                .buttonStyle(.borderedProminent)
                
                
                
                Button {
                    
                    resetAll()
                    addState = .idle
                    
                } label: {
                    
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                    
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.top)
        }
        .padding()
    }
    // MARK: - RNODE FORM
    
    func rnodeForm() -> some View {
        
        VStack(spacing: 14) {
            
            Text("RNode Configuration")
                .font(.headline)
            
            labeledField("Name", text: $rnode.name)

            // Connection method
            VStack(alignment: .leading, spacing: 6) {

                Text("Connect Via")

                Picker("Connect Via", selection: $rnode.connectionMethod) {
                    ForEach(RNodeConnectionMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if rnode.connectionMethod == .bluetooth {

                // Device
                VStack(alignment: .leading, spacing: 6) {

                    Text("Device")

                    Button {
                        isShowingRNodePairing = true
                    } label: {
                        HStack {

                            Image(systemName: rnode.peripheralIdentifier.isEmpty ? "antenna.radiowaves.left.and.right" : "checkmark.circle.fill")
                                .foregroundStyle(rnode.peripheralIdentifier.isEmpty ? Theme.textSecondary : Theme.success)

                            Text(rnode.device.isEmpty ? "Pair via Bluetooth…" : rnode.device)
                                .foregroundStyle(Theme.textPrimary)

                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(8)
                        .background(Theme.surface)
                        .cornerRadius(8)
                    }
                }
                .sheet(isPresented: $isShowingRNodePairing) {

                    RNodePairingView { device in
                        rnode.device = device.name
                        rnode.peripheralIdentifier = device.id.uuidString

                        if rnode.name.isEmpty {
                            rnode.name = device.name
                        }
                    }
                }

            } else if rnode.connectionMethod == .usb {

                #if targetEnvironment(macCatalyst)
                // USB serial — same /dev/cu.* scan Firmware Tools uses to
                // find a connected board, just picking a port to talk
                // live KISS traffic over instead of the ROM bootloader.
                VStack(alignment: .leading, spacing: 6) {

                    Text("USB Port")

                    if usbSerialPorts.isEmpty {

                        Text("No USB-serial devices found. Plug in your RNode and tap Refresh.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)

                    } else {

                        Picker("USB Port", selection: $rnode.usbSerialPath) {
                            ForEach(usbSerialPorts, id: \.self) { port in
                                Text((port as NSString).lastPathComponent).tag(port)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .padding(8)
                        .background(Theme.surface)
                        .cornerRadius(8)
                    }

                    Button {
                        refreshUSBSerialPorts()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .font(.caption)
                }
                .onAppear {
                    refreshUSBSerialPorts()

                    if rnode.usbSerialPath.isEmpty {
                        rnode.usbSerialPath = usbSerialPorts.first ?? ""
                    }
                }
                #endif

            } else {

                // WiFi host/port — the RNode's own IP once it's in WiFi
                // mode, not this device's. Its AP-mode default is
                // 10.0.0.1 (confirmed in firmware source); in station
                // mode it's whatever your router hands out.
                VStack(alignment: .leading, spacing: 6) {

                    Text("RNode Address")

                    HStack(spacing: 8) {

                        TextField("IP address, e.g. 10.0.0.1", text: $rnode.wifiHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.numbersAndPunctuation)
                            .padding(8)
                            .background(Theme.surface)
                            .cornerRadius(8)

                        TextField("Port", text: $rnode.wifiPort)
                            .keyboardType(.numberPad)
                            .frame(width: 70)
                            .padding(8)
                            .background(Theme.surface)
                            .cornerRadius(8)
                    }

                    Text("Put the RNode in WiFi mode first (rnodeconf, or the on-device Bootstrap Console) — 10.0.0.1 is its own access-point address, port 7633 is the default.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Frequency
            VStack(alignment: .leading, spacing: 6) {
                
                HStack {
                    labeledMiniField("GHz", text: $rnode.freqGHz, keyboard: .numberPad)
                    labeledMiniField("MHz", text: $rnode.freqMHz, keyboard: .numberPad)
                    labeledMiniField("KHz", text: $rnode.freqKHz, keyboard: .numberPad)
                    labeledMiniField("Hz", text: $rnode.freqHz, keyboard: .numberPad)
                }
                
                Text("US Recommended: 915 MHz (Change at your own risk)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            pickerRow("Bandwidth", selection: $rnode.bandwidth, items: [
                "7.8 KHz","10.4 KHz","15.6 KHz","20.8 KHz",
                "31.25 KHz","41.7 KHz","62.5 KHz",
                "125 KHz","250 KHz","500 KHz","1625 KHz"
            ])
            
            pickerRow("Transmit Power", selection: $rnode.transmitPower,
                      items: (1...10).map { "\($0)" })
            
            pickerRow("Spreading Factor", selection: $rnode.spreadingFactor,
                      items: (5...12).map { "\($0)" })
            
            pickerRow("Coding Rate", selection: $rnode.codingRate,
                      items: (5...8).map { "\($0)" })
            
            HStack(spacing: 20) {
                
                Button {
                    let connection = Connection(
                        id: {
                            if case .editing(let id) = addState {
                                return id
                            }
                            return UUID()
                        }(),
                        name: rnode.name,
                        address: "",
                        port: "",
                        type: .rNode,
                        rnodeConfig: rnode
                    )


                    switch addState {

                    case .editing(let id):

                        if let index = connections.firstIndex(where: {
                            $0.id == id
                        }) {
                            connections[index] = connection
                        }


                    default:

                        connections.append(connection)

                    }


                    ConnectionStorage.shared.save(connections)
                    interfaceManager.restartAll()

                    resetAll()
                    addState = .idle
                } label: {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    
                    resetAll()
                    addState = .idle
                    
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.top)
            
        }
        .padding()
    }
    
    // MARK: - COMPONENTS

    /// Your identity's own addresses — not tied to any one connection,
    /// since they're derived from your identity key, not an interface.
    /// Shown here since this is where people naturally look for "how do
    /// I get reached."
    var myAddressesCard: some View {

        VStack(alignment: .leading, spacing: 10) {

            Text("Your Address")
                .font(.subheadline.weight(.semibold))

            addressRow(label: "LXMF", value: LXMFDestination.myDestinationHashHex, description: "Share this so other LXMF/NomadNet users can message you.", scheme: "lxmf")
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }


    func addressRow(label: String, value: String, description: String, scheme: String? = nil) -> some View {

        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 6) {

                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)

                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(description)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            // Full-size, clearly-labeled buttons instead of tiny bare
            // icons — this is the primary "share my address" action in
            // the app, worth being easy to hit and easy to read.
            HStack(spacing: 10) {

                Button {
                    isShowingAddressQRCode = true
                } label: {
                    Label("QR Code", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $isShowingAddressQRCode) {
                    QRCodeView(label: label, value: value, scheme: scheme)
                }

                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
    }


    /// A muted, dashed-border "preset" row — tapping it pre-fills the TCP
    /// form rather than adding the connection silently, so Save is still
    /// an explicit, reviewable step.
    func suggestedConnectionRow(_ suggestion: SuggestedConnection) -> some View {

        Button {
            resetAll()
            name = suggestion.name
            address = suggestion.address
            port = suggestion.port
            addState = .enteringDetails(.tcpClient)
        } label: {

            HStack(spacing: 10) {

                Image(systemName: "network")
                    .foregroundStyle(suggestion.isRecommended ? Theme.tcpGreen : Theme.textSecondary)

                VStack(alignment: .leading, spacing: 2) {

                    HStack(spacing: 6) {

                        Text(suggestion.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)

                        if suggestion.isRecommended {

                            Text("RECOMMENDED")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(Theme.tcpGreen)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.tcpGreen.opacity(0.15), in: Capsule())
                        }
                    }

                    Text("\(suggestion.address):\(suggestion.port)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Text("Use")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(10)
            .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.divider, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }


    func instructionRow(icon: String, color: Color = Theme.accent, title: String, body: String) -> some View {

        HStack(alignment: .top, spacing: 12) {

            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(body)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }


    func rnodeConnectionIcon(_ method: RNodeConnectionMethod) -> String {

        switch method {
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .usb: "cable.connector"
        case .wifi: "wifi"
        }
    }


    func batteryIcon(_ status: RNodeBatteryStatus) -> String {

        if status.state == .charging || status.state == .charged {
            return "battery.100.bolt"
        }

        switch status.percent {
        case 0..<20: return "battery.0"
        case 20..<50: return "battery.25"
        case 50..<80: return "battery.50"
        default: return "battery.100"
        }
    }


    #if targetEnvironment(macCatalyst)
    /// Same /dev/cu.* scan as Firmware Tools' port list — filters out
    /// Bluetooth-backed and debug-console pseudo-ports, which never are
    /// an actual connected USB-serial board.
    func refreshUSBSerialPorts() {

        let devicesDirectory = "/dev"

        let entries = (try? FileManager.default.contentsOfDirectory(atPath: devicesDirectory)) ?? []

        usbSerialPorts = entries
            .filter { $0.hasPrefix("cu.") }
            .filter { !$0.contains("Bluetooth") && !$0.contains("debug-console") }
            .sorted()
            .map { "\(devicesDirectory)/\($0)" }
    }
    #endif


    func labeledField(_ title: String,
                      text: Binding<String>,
                      keyboard: UIKeyboardType = .default) -> some View {
        
        HStack {
            Text(title)
                .frame(width: 120, alignment: .leading)
            
            TextField("", text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    func labeledMiniField(_ title: String,
                          text: Binding<String>,
                          keyboard: UIKeyboardType = .numberPad) -> some View {
        
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            
            TextField("", text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        }
    }
    
    func pickerRow(_ title: String,
                   selection: Binding<String>,
                   items: [String]) -> some View {

        HStack {

            Text(title)
                .frame(width: 120, alignment: .leading)

            Picker("", selection: selection) {

                ForEach(items, id: \.self) { item in
                    Text(item)
                        .tag(item)
                }

            }
            .pickerStyle(.menu)
        }
    }


    // MARK: - Swipe Actions

    func deleteConnection(_ connection: Connection) {

        connections.removeAll {
            $0.id == connection.id
        }

        ConnectionStorage.shared.save(connections)
        interfaceManager.restartAll()
    }


    func editConnection(_ connection: Connection) {

        switch connection.type {

        case .tcpClient:

            name = connection.name
            address = connection.address
            port = connection.port


        case .rNode:

            if let config = connection.rnodeConfig {
                rnode = config
            }
        }

        addState = .editing(connection.id)
    }


    // MARK: - RESET

    func resetAll() {

        name = ""
        address = ""
        port = ""
        rnode = RNodeConfig()

    }

}
