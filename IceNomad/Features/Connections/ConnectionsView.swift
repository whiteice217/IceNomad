//
//  ConnectionsView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

// MARK: - Models

enum ConnectionType: String, CaseIterable, Identifiable, Codable {
    case tcpClient = "TCP Client"
    case rNode = "RNode"

    var id: String { rawValue }
}

// MARK: - RNode Config

struct RNodeConfig: Codable {
    var name: String = ""
    var device: String = ""

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
    @StateObject private var interfaceManager = InterfaceManager()
    @State private var isRefreshing = false
    
    // TCP
    @State private var name = ""
    @State private var address = ""
    @State private var port = ""
    
    // RNode
    @State private var rnode = RNodeConfig()
    
    var body: some View {
        
        NavigationStack {
            
            VStack {
                
                if connections.isEmpty {

                    VStack(spacing: 16) {

                        Text("No Connections")
                            .font(.headline)


                        Button {
                            addState = .choosingType
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 60))
                        }


                        if addState != .idle {
                            Divider()
                            addFlowView
                        }
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
                                        ? Color.green
                                        : Color.red
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
                                        .foregroundStyle(.secondary)
                                    
                                    Text("Port: \(conn.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: "network")
                                        Text("TCP Client")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.blue)
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
                                        .foregroundStyle(.blue)
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
                            .tint(.blue)
                        }
                    }
                    .listRowSpacing(12)
                    
                    
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
        .onAppear {
            
            interfaceManager.loadInterfaces()
            interfaceManager.startAll()
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
            HStack {
                Text("Device")
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Menu {
                    Button("No Device") { rnode.device = "" }
                    Button("Device A") { rnode.device = "Device A" }
                    Button("Device B") { rnode.device = "Device B" }
                } label: {
                    HStack {
                        Text(rnode.device.isEmpty ? "Select Device" : rnode.device)
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(8)
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
                    print("Saving frequency:", rnode.frequencyHzString)
                    
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
                .foregroundStyle(.secondary)
            
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
