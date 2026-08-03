//
//  RNodeControlsView.swift
//  IceNomad
//
//  Live device controls for a connected RNode — reboot, display power/
//  sleep, and WiFi settings (mode, name, password, static IP). These are
//  fire-and-forget KISS commands sent straight to the physical board
//  (RNodeInterface's new reboot()/setDisplayIntensity()/etc.), not local
//  app config the way radio frequency/bandwidth/etc. are — so unlike the
//  rest of Connections, there's no "saved" state here to edit, and no
//  way to read back what's currently set (the firmware doesn't expose a
//  query command for it). Everything here is write-only, applied live.
//

import SwiftUI

struct RNodeControlsView: View {

    let connectionName: String
    let connectionMethod: RNodeConnectionMethod

    @ObservedObject private var interfaceManager = InterfaceManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var displayBlankSeconds: Int = 0
    @State private var wifiMode: UInt8 = RNodeKISS.wifiModeAccessPoint
    @State private var ssid = ""
    @State private var password = ""
    @State private var staticIP = ["", "", "", ""]
    @State private var staticNetmask = ["255", "255", "255", "0"]
    @State private var isConfirmingReboot = false
    @State private var didSendCommand = false

    private static let blankTimeoutOptions: [(label: String, seconds: Int)] = [
        ("Never (Always On)", 0),
        ("15 Seconds", 15),
        ("30 Seconds", 30),
        ("1 Minute", 60),
        ("5 Minutes", 300)
    ]

    var body: some View {
        NavigationStack {
            Form {

                Section {

                    HStack {

                        Label("Live Connection", systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(isLive ? Theme.success : Theme.danger)

                        Spacer()

                        if !isLive {
                            Text("Not connected right now")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                } footer: {
                    Text("These send commands straight to the physical board — there's no saved config here, and the firmware doesn't report back what's currently set, only what you send.")
                }

                Section("Battery") {

                    if let status = interfaceManager.rnodeBatteryStatus[connectionName] {

                        HStack {

                            Label("\(status.percent)%", systemImage: batteryIcon(status))
                                .foregroundStyle(batteryColor(status))

                            Spacer()

                            Text(batteryStateLabel(status.state))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }

                    } else {

                        Text("No battery data yet — the device reports this on its own every few seconds once connected.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Section {

                    Button {
                        interfaceManager.rnodeInterface(named: connectionName)?.setDisplayIntensity(0xFF)
                        flashSent()
                    } label: {
                        Label("Turn Screen On", systemImage: "sun.max")
                    }
                    .disabled(!isLive)

                    Button {
                        interfaceManager.rnodeInterface(named: connectionName)?.setDisplayIntensity(0x00)
                        flashSent()
                    } label: {
                        Label("Turn Screen Off", systemImage: "moon")
                    }
                    .disabled(!isLive)

                    Picker("Auto-Sleep", selection: $displayBlankSeconds) {

                        ForEach(Self.blankTimeoutOptions, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }
                    .onChange(of: displayBlankSeconds) {
                        interfaceManager.rnodeInterface(named: connectionName)?.setDisplayBlankTimeout(seconds: UInt8(clamping: displayBlankSeconds))
                        flashSent()
                    }
                    .disabled(!isLive)

                } header: {
                    Text("Screen")
                } footer: {
                    Text("Auto-Sleep blanks the display after that many seconds of inactivity to save power — it wakes back up on its own the next time the board does anything.")
                }

                Section {

                    Picker("Mode", selection: $wifiMode) {
                        Text("Off").tag(RNodeKISS.wifiModeOff)
                        Text("Station (join a network)").tag(RNodeKISS.wifiModeStation)
                        Text("Access Point (its own hotspot)").tag(RNodeKISS.wifiModeAccessPoint)
                    }
                    .onChange(of: wifiMode) {
                        interfaceManager.rnodeInterface(named: connectionName)?.setWiFiMode(wifiMode)
                        flashSent()
                    }
                    .disabled(!isLive)

                    HStack {

                        TextField("Network Name (SSID)", text: $ssid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button("Save") {
                            interfaceManager.rnodeInterface(named: connectionName)?.setWiFiSSID(ssid)
                            flashSent()
                        }
                        .disabled(!isLive || ssid.isEmpty)
                    }

                    HStack {

                        SecureField("Password (leave blank for open)", text: $password)

                        Button("Save") {
                            interfaceManager.rnodeInterface(named: connectionName)?.setWiFiPassword(password)
                            flashSent()
                        }
                        .disabled(!isLive)
                    }

                    if wifiMode == RNodeKISS.wifiModeStation {

                        VStack(alignment: .leading, spacing: 6) {

                            Text("Static IP (optional)")
                                .font(.subheadline)

                            HStack(spacing: 6) {
                                ForEach(0..<4, id: \.self) { i in
                                    TextField("0", text: $staticIP[i])
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                }
                            }

                            Text("Netmask")
                                .font(.subheadline)

                            HStack(spacing: 6) {
                                ForEach(0..<4, id: \.self) { i in
                                    TextField("255", text: $staticNetmask[i])
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                }
                            }

                            Button("Save Static IP") {
                                applyStaticIP()
                            }
                            .disabled(!isLive)
                        }
                    }

                } header: {
                    Text("WiFi")
                } footer: {

                    if wifiMode == RNodeKISS.wifiModeAccessPoint {
                        Text("In Access Point mode the board's own IP is fixed at 10.0.0.1 by the firmware — that's not something the static IP fields below can change.")
                    } else {
                        Text("Static IP only applies in Station mode. Leave it blank to get an address via DHCP instead.")
                    }
                }

                Section {

                    Button(role: .destructive) {
                        isConfirmingReboot = true
                    } label: {
                        Label("Reboot RNode", systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(!isLive)
                }
            }
            .navigationTitle("Radio Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                if didSendCommand {
                    ToolbarItem(placement: .topBarTrailing) {
                        Label("Sent", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .confirmationDialog(
                "Reboot this RNode?",
                isPresented: $isConfirmingReboot,
                titleVisibility: .visible
            ) {
                Button("Reboot", role: .destructive) {
                    interfaceManager.rnodeInterface(named: connectionName)?.reboot()
                    flashSent()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The radio will go offline for a few seconds while it restarts.")
            }
            .onAppear {
                wifiMode = connectionMethod == .wifi ? RNodeKISS.wifiModeAccessPoint : RNodeKISS.wifiModeOff
            }
        }
    }


    private var isLive: Bool {
        interfaceManager.rnodeInterface(named: connectionName) != nil
    }


    private func flashSent() {

        didSendCommand = true

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            didSendCommand = false
        }
    }


    private func applyStaticIP() {

        guard let ip = parsedOctets(staticIP), let nm = parsedOctets(staticNetmask) else {
            return
        }

        interfaceManager.rnodeInterface(named: connectionName)?.setWiFiStaticIP(ip, netmask: nm)
        flashSent()
    }


    private func parsedOctets(_ fields: [String]) -> (UInt8, UInt8, UInt8, UInt8)? {

        let values = fields.compactMap { UInt8($0) }

        guard values.count == 4 else {
            return nil
        }

        return (values[0], values[1], values[2], values[3])
    }


    private func batteryIcon(_ status: RNodeBatteryStatus) -> String {

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


    private func batteryColor(_ status: RNodeBatteryStatus) -> Color {

        if status.percent < 20 && status.state == .discharging {
            return Theme.danger
        }

        return Theme.textPrimary
    }


    private func batteryStateLabel(_ state: RNodeKISS.BatteryState) -> String {

        switch state {
        case .unknown: return "Unknown"
        case .discharging: return "On Battery"
        case .charging: return "Charging"
        case .charged: return "Fully Charged"
        }
    }
}
