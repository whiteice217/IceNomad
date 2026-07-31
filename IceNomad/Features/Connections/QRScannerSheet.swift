//
//  QRScannerSheet.swift
//  IceNomad
//
//  Full-screen chrome around QRScannerView — title, cancel, and a
//  friendly message if scanning isn't available. Mac Catalyst can't
//  compile against DataScannerViewController at all (see QRScannerView's
//  header), so that whole check-and-scan path is compiled out there in
//  favor of an always-unavailable message — iOS/iPadOS still checks
//  isSupported/isAvailable at runtime as normal.
//

import SwiftUI

#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

struct QRScannerSheet: View {

    let onScan: (ScannedCode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {

#if !targetEnvironment(macCatalyst)

                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {

                    QRScannerView { payload in

                        onScan(ScannedCode.parse(payload))
                        dismiss()
                    }
                    .ignoresSafeArea()

                } else {

                    ContentUnavailableView(
                        "Scanning Unavailable",
                        systemImage: "qrcode.viewfinder",
                        description: Text("This device doesn't support QR scanning, or camera access hasn't been granted in Settings.")
                    )
                }

#else

                ContentUnavailableView(
                    "Scanning Unavailable on Mac",
                    systemImage: "qrcode.viewfinder",
                    description: Text("QR scanning needs a device camera — use the iPhone/iPad app to scan, or paste the address directly.")
                )

#endif

            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
