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

struct RNodeConfig: Codable {
    var name: String = ""
    var device: String = ""          // display name of the paired BLE peripheral
    var peripheralIdentifier: String = ""   // CBPeripheral.identifier.uuidString — used to reconnect

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

// MARK: - State

enum AddState: Equatable {
    case idle
    case choosingType
    case enteringDetails(ConnectionType)
    case editing(UUID)
}

// MARK: - View

struct ConnectionsView: View {
    
    @State private var connections: [Connection] = ConnectionStorage.shared.load()
    @State private var addState: AddState = .idle
    @ObservedObject private var interfaceManager = InterfaceManager.shared
    @State private var isRefreshing = false
    @State private var isShowingRNodePairing = false
    @State private var isShowingAddressQRCode = false
    
    // TCP
    @State private var name = ""
    @State private var address = ""
    @State private var port = ""
    
    // RNode
    @State private var rnode = RNodeConfig()
    
    var body: some View {
        
        NavigationStack {

            VStack {

                myAddressesCard
                    .padding(.horizontal)
                    .padding(.top, 8)

                if connections.isEmpty {

                    ScrollView {

                        VStack(spacing: 20) {

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
                        }
                        .padding(.bottom, 24)
                    }

                } else {
                    
                    List(connections) { conn in
                        
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
                                            Image(systemName: "wifi")
                                            Text("RNode")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(Theme.rnodeBlue)
                                    }
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            
                            Button(role: .destructive) {
                                deleteConnection(conn)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                editConnection(conn)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Theme.accent)
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
        }
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

            addressRow(label: "LXMF", value: LXMFDestination.myDestinationHashHex, description: "Share this so other LXMF/NomadNet users can message you.")
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }


    func addressRow(label: String, value: String, description: String) -> some View {

        VStack(alignment: .leading, spacing: 2) {

            HStack(spacing: 6) {

                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)

                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    isShowingAddressQRCode = true
                } label: {
                    Image(systemName: "qrcode")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $isShowingAddressQRCode) {
                    QRCodeView(label: label, value: value)
                }

                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            Text(description)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
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
