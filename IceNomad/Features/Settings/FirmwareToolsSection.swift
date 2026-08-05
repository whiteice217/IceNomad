//
//  FirmwareToolsSection.swift
//  IceNomad
//
//  Mac-only: flashing an ESP32 means talking directly to a USB-serial
//  device, which iOS doesn't allow third-party apps to do without MFi
//  certification — a real platform restriction, not something we can
//  code around. Not shown on iOS at all (see SettingsView's call site)
//  rather than a "use the Mac version" stub, since there's nothing
//  actionable here for an iPhone user. This is a real (if intentionally
//  partial) start: detecting a connected board and confirming it's
//  alive and talking the ESP32 ROM bootloader protocol. Actually
//  writing firmware isn't built yet — see ESP32ROMLoader's doc comment
//  for why that's a deliberately separate next step.
//
//  This whole file is Mac Catalyst only — ESP32SerialPort/ESP32ROMLoader
//  are themselves gated the same way (raw POSIX serial access isn't
//  available to sandboxed iOS apps), so the type-check would fail on
//  iOS even though SettingsView's call site already skips instantiating
//  this view there.

#if targetEnvironment(macCatalyst)

import SwiftUI

struct FirmwareToolsSection: View {

    var body: some View {

        Section {

            FirmwareDetectRow()

        } header: {
            Text("RNode Firmware Tools")
        } footer: {
            Text("Detects a Heltec V3 connected over USB and confirms it's talking the ESP32 bootloader protocol. Flashing firmware isn't available yet — this is the first step.")
        }
    }
}


private struct FirmwareDetectRow: View {

    private enum Status: Equatable {
        case idle
        case detecting
        case found
        case failed(String)
    }

    @State private var ports: [String] = []
    @State private var status: Status = .idle

    var body: some View {

        VStack(alignment: .leading, spacing: 10) {

            if ports.isEmpty {

                Text("No USB-serial devices found. Plug in your RNode and try again.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

            } else {

                ForEach(ports, id: \.self) { port in

                    HStack {

                        VStack(alignment: .leading, spacing: 2) {

                            Text(port)
                                .font(.system(.subheadline, design: .monospaced))

                            statusText
                        }

                        Spacer()

                        Button {
                            detect(port: port)
                        } label: {
                            if status == .detecting {
                                ProgressView()
                            } else {
                                Text("Detect")
                            }
                        }
                        .disabled(status == .detecting)
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                refreshPorts()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .onAppear {
            refreshPorts()
        }
    }


    @ViewBuilder
    private var statusText: some View {

        switch status {

        case .idle:
            EmptyView()

        case .detecting:
            Text("Resetting into bootloader…")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

        case .found:
            Label("Board detected and responding", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.success)

        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.danger)
        }
    }


    private func refreshPorts() {

        let devicesDirectory = "/dev"

        let entries = (try? FileManager.default.contentsOfDirectory(atPath: devicesDirectory)) ?? []

        ports = entries
            .filter { $0.hasPrefix("cu.") }
            .filter { !$0.contains("Bluetooth") && !$0.contains("debug-console") }
            .sorted()
            .map { "\(devicesDirectory)/\($0)" }
    }


    private func detect(port: String) {

        status = .detecting

        DispatchQueue.global(qos: .userInitiated).async {

            let serial = ESP32SerialPort(path: port)

            do {

                try serial.open()
                defer { serial.close() }

                let loader = ESP32ROMLoader(port: serial)
                try loader.connect()

                // Only a liveness/protocol check for now — ESP32-S3
                // (Heltec V3's chip) doesn't use the older chip-magic
                // register the way ESP32/ESP8266 do, so this isn't
                // read as an identifying value, just confirmation the
                // ROM bootloader is there and answering commands.
                _ = try loader.readChipDetectMagic()

                DispatchQueue.main.async {
                    status = .found
                }

            } catch {

                DispatchQueue.main.async {
                    status = .failed("No response — check the board is connected and try again")
                }
            }
        }
    }
}

#endif
