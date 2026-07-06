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
    var id = UUID()

    var name: String
    var address: String = ""
    var port: String = ""
    var type: ConnectionType
    var rnodeConfig: RNodeConfig? = nil
}


// MARK: - State

enum AddState {
    case idle
    case choosingType
    case enteringDetails(ConnectionType)
}

// MARK: - View

struct ConnectionsView: View {

    @State private var connections: [Connection] = ConnectionStorage.shared.load()
    @State private var addState: AddState = .idle

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
                    }

                } else {

                    List(connections) { conn in

                        VStack(alignment: .leading, spacing: 8) {

                            HStack(spacing: 8) {

                                Circle()
                                    .fill(Color.red) // Placeholder: dead/offline
                                    .frame(width: 10, height: 10)

                                Text(conn.name)
                                    .font(.headline)
                            }
                            
                            switch conn.type {

                            case .tcpClient:

                                HStack(spacing: 4) {
                                    Image(systemName: "network")

                                    Text("TCP Client")
                                }
                                .font(.caption)
                                .foregroundStyle(.blue)
                                
                            case .rNode:

                                if let rnode = conn.rnodeConfig {


                                    VStack(spacing: 4) {

                                        HStack {

                                            Text("GHz")
                                                .frame(width: 50)

                                            Text("MHz")
                                                .frame(width: 50)

                                            Text("KHz")
                                                .frame(width: 50)

                                            Text("Hz")
                                                .frame(width: 50)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        HStack {

                                            Text(String(format: "%03d", Int(rnode.freqGHz) ?? 0))
                                                .frame(width: 50)

                                            Text(String(format: "%03d", Int(rnode.freqMHz) ?? 0))
                                                .frame(width: 50)

                                            Text(String(format: "%03d", Int(rnode.freqKHz) ?? 0))
                                                .frame(width: 50)

                                            Text("000")
                                                .frame(width: 50)
                                        }
                                        .font(.system(.body, design: .monospaced))

                                    }

                                    Divider()



                                    Text("Bandwidth: \(rnode.bandwidth)")
                                    Text("Transmit Power: \(rnode.transmitPower)")
                                    Text("Spread: \(rnode.spreadingFactor)")
                                    Text("Code: \(rnode.codingRate)")

                                    HStack(spacing: 4) {
                                        Image(systemName: "wifi")

                                        Text("RNode")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.blue)
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

                    Button("Add Connection") {

                        addState = .choosingType
                    }
                    .padding(.bottom)
                }
            }

            .navigationTitle("Connections")

            .sheet(isPresented: Binding(

                get: {

                    if case .idle = addState {
                        return false
                    }

                    return true
                },

                set: { newValue in

                    if !newValue {
                        addState = .idle
                    }
                }

            )) {

                addFlowView
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

                    connections.append(
                        Connection(
                            name: name,
                            address: address,
                            port: port,
                            type: .tcpClient
                        )
                    )

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
                        name: rnode.name,
                        address: "",
                        port: "",
                        type: .rNode,
                        rnodeConfig: rnode
                    )

                    connections.append(connection)

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
            .onAppear {

                if !items.contains(selection.wrappedValue) {
                    selection.wrappedValue = items.first ?? ""
                }
            }
        }
    }

    // MARK: - Swipe Actions

    func deleteConnection(_ connection: Connection) {

        connections.removeAll { $0.id == connection.id }

        ConnectionStorage.shared.save(connections)
    }

    func editConnection(_ connection: Connection) {

        print("Editing connection:", connection.name)

    }
    
    // MARK: - RESET

    func resetAll() {
        name = ""
        address = ""
        port = ""
        rnode = RNodeConfig()
    }
}
