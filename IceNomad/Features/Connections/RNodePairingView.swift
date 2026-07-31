//
//  RNodePairingView.swift
//  IceNomad
//
//  Scans for nearby RNode devices advertising the Nordic UART Service
//  and lets the user pick one to pair. Selecting a device just records
//  its CoreBluetooth identifier in RNodeConfig — RNodeInterface does
//  the actual connecting when the connection is started.
//

import SwiftUI

struct RNodePairingView: View {

    @ObservedObject private var ble = RNodeBLEManager.shared
    @Environment(\.dismiss) private var dismiss

    let onSelect: (DiscoveredRNode) -> Void

    var body: some View {
        NavigationStack {
            Group {

                if !ble.isBluetoothReady {

                    ContentUnavailableView(
                        "Bluetooth Unavailable",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        description: Text("Turn on Bluetooth to scan for RNode devices.")
                    )

                } else if ble.discovered.isEmpty {

                    VStack(spacing: 16) {

                        ProgressView()

                        Text("Searching for RNode devices…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Make sure your RNode is powered on and in range.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else {

                    List(ble.discovered) { device in

                        Button {
                            onSelect(device)
                            ble.stopScan()
                            dismiss()
                        } label: {

                            HStack {

                                VStack(alignment: .leading, spacing: 2) {

                                    Text(device.name)
                                        .foregroundStyle(.primary)

                                    Text(device.id.uuidString)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Label("\(device.rssi)", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pair RNode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        ble.stopScan()
                        dismiss()
                    }
                }
            }
            .onAppear {
                ble.startScan()
            }
            .onDisappear {
                ble.stopScan()
            }
        }
    }
}
