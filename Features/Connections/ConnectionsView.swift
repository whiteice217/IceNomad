//
//  ConnectionsView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

// MARK: - Models

enum ConnectionType: String, CaseIterable, Identifiable {
    case tcpClient = "TCP Client"
    case rNode = "RNode"

    var id: String { rawValue }
}

struct Connection: Identifiable {
    let id = UUID()
    var name: String
    var address: String
    var port: String
    var type: ConnectionType
}

// MARK: - RNode Config

struct RNodeConfig {
    var name: String = ""
    var device: String = ""

    var freqGHz: String = ""
    var freqMHz: String = "915"
    var freqKHz: String = ""

    var bandwidth: String = "125 KHz"
    var transmitPower: String = "7"
    var spreadingFactor: String = "8"
    var codingRate: String = "5"
}

// MARK: - State

enum AddState {
    case idle
    case choosingType
    case enteringDetails(ConnectionType)
}

// MARK: - View

struct ConnectionsView: View {

    @State private var connections: [Connection] = []
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
                        VStack(alignment: .leading) {
                            Text(conn.name)
                                .font(.headline)

                            Text("\(conn.address):\(conn.port)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(conn.type.rawValue)
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }

                    Button("Add Connection") {
                        addState = .choosingType
                    }
                    .padding(.bottom)
                }
            }
            .navigationTitle("Connections")
            .sheet(isPresented: Binding(
                get: {
                    if case .idle = addState { return false }
                    return true
                },
                set: { newValue in
                    if !newValue { addState = .idle }
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

                Button("TCP Client") {
                    resetAll()
                    addState = .enteringDetails(.tcpClient)
                }

                Button("RNode") {
                    resetAll()
                    addState = .enteringDetails(.rNode)
                }

                Button("Cancel") {
                    addState = .idle
                }
                .foregroundStyle(.red)
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

            Button("Save") {

                connections.append(
                    Connection(name: name,
                                address: address,
                                port: port,
                                type: .tcpClient)
                )

                resetAll()
                addState = .idle
            }

            Button("Cancel") {
                resetAll()
                addState = .idle
            }
            .foregroundStyle(.red)
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
                    .frame(width: 120, alignment: .leading)

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
            HStack {
                labeledMiniField("GHz", text: $rnode.freqGHz, keyboard: .numberPad)
                labeledMiniField("MHz", text: $rnode.freqMHz, keyboard: .numberPad)
                labeledMiniField("KHz", text: $rnode.freqKHz, keyboard: .numberPad)
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

            Button("Save") {
                print("RNode:", rnode)
                resetAll()
                addState = .idle
            }

            Button("Cancel") {
                resetAll()
                addState = .idle
            }
            .foregroundStyle(.red)
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
                    Text(item).tag(item)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - RESET

    func resetAll() {
        name = ""
        address = ""
        port = ""
        rnode = RNodeConfig()
    }
}
