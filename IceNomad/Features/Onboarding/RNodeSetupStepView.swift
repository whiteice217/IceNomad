//
//  RNodeSetupStepView.swift
//  IceNomad
//
//  The setup wizard's RNode step — a purpose-built "add a new RNode"
//  form, not a shared component with ConnectionsView.rnodeForm(). That
//  form supports both adding AND editing an existing connection, tied
//  into ConnectionsView's own @State (addState, connections list) in
//  ways that weren't worth the risk of refactoring apart mid-wizard-build
//  — this duplicates the real add-flow (same RNodeConfig model, same
//  RNodePairingView, same RF parameter set/defaults) faithfully instead.
//  If the two ever need to be reconciled into one shared component,
//  that's a deliberate follow-up, not implied by this file existing.
//

import SwiftUI

struct RNodeSetupStepView: View {

    let onSaved: () -> Void

    @State private var rnode = RNodeConfig()
    @State private var isShowingRNodePairing = false
    @State private var usbSerialPorts: [String] = []

    var body: some View {

        ScrollView {

            VStack(alignment: .leading, spacing: 16) {

                VStack(alignment: .leading, spacing: 6) {

                    Text("Set Up Your RNode")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)

                    // USB only actually works on Mac Catalyst
                    // (RNodeConnectionMethod.allCases already excludes
                    // it on iOS) — this text used to unconditionally
                    // mention it on both platforms, which was just
                    // wrong on iOS since there was never a USB option
                    // to pick.
                    #if targetEnvironment(macCatalyst)
                    Text("Connect over Bluetooth, USB, or WiFi.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    #else
                    Text("Connect over Bluetooth or WiFi.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    #endif
                }

                labeledField("Name", text: $rnode.name)

                VStack(alignment: .leading, spacing: 6) {

                    Text("Connect Via")
                        .foregroundStyle(Theme.textPrimary)

                    Picker("Connect Via", selection: $rnode.connectionMethod) {
                        ForEach(RNodeConnectionMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                connectionMethodFields

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
                    "7.8 KHz", "10.4 KHz", "15.6 KHz", "20.8 KHz",
                    "31.25 KHz", "41.7 KHz", "62.5 KHz",
                    "125 KHz", "250 KHz", "500 KHz", "1625 KHz"
                ])

                pickerRow("Transmit Power", selection: $rnode.transmitPower, items: (1...10).map { "\($0)" })
                pickerRow("Spreading Factor", selection: $rnode.spreadingFactor, items: (5...12).map { "\($0)" })
                pickerRow("Coding Rate", selection: $rnode.codingRate, items: (5...8).map { "\($0)" })

                Button {
                    save()
                } label: {
                    Text("Save & Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isReadyToSave)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }


    @ViewBuilder
    private var connectionMethodFields: some View {

        switch rnode.connectionMethod {

        case .bluetooth:

            VStack(alignment: .leading, spacing: 6) {

                Text("Device")
                    .foregroundStyle(Theme.textPrimary)

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

        case .usb:

            #if targetEnvironment(macCatalyst)
            VStack(alignment: .leading, spacing: 6) {

                Text("USB Port")
                    .foregroundStyle(Theme.textPrimary)

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

        case .wifi:

            VStack(alignment: .leading, spacing: 6) {

                Text("RNode Address")
                    .foregroundStyle(Theme.textPrimary)

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
    }


    private var isReadyToSave: Bool {

        guard !rnode.name.isEmpty else {
            return false
        }

        switch rnode.connectionMethod {
        case .bluetooth: return !rnode.peripheralIdentifier.isEmpty
        case .usb: return !rnode.usbSerialPath.isEmpty
        case .wifi: return !rnode.wifiHost.isEmpty
        }
    }


    private func save() {

        let connection = Connection(name: rnode.name, address: "", port: "", type: .rNode, rnodeConfig: rnode)

        var connections = ConnectionStorage.shared.load()
        connections.append(connection)
        ConnectionStorage.shared.save(connections)
        InterfaceManager.shared.restartAll()

        onSaved()
    }


    #if targetEnvironment(macCatalyst)
    private func refreshUSBSerialPorts() {

        let devicesDirectory = "/dev"

        let entries = (try? FileManager.default.contentsOfDirectory(atPath: devicesDirectory)) ?? []

        usbSerialPorts = entries
            .filter { $0.hasPrefix("cu.") }
            .filter { !$0.contains("Bluetooth") && !$0.contains("debug-console") }
            .sorted()
            .map { "\(devicesDirectory)/\($0)" }
    }
    #endif


    private func labeledField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {

        HStack {
            Text(title)
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(Theme.textPrimary)

            TextField("", text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
        }
    }


    private func labeledMiniField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .numberPad) -> some View {

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


    private func pickerRow(_ title: String, selection: Binding<String>, items: [String]) -> some View {

        HStack {

            Text(title)
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(Theme.textPrimary)

            Picker("", selection: selection) {
                ForEach(items, id: \.self) { item in
                    Text(item).tag(item)
                }
            }
            .pickerStyle(.menu)
        }
    }
}
