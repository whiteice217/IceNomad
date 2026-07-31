//
//  QRScannerView.swift
//  IceNomad
//
//  Camera-based QR scanner (VisionKit's DataScannerViewController) —
//  auto-detects the first QR code in frame and hands its payload back,
//  no manual tap-to-capture needed. This is the "point your phone at a
//  sticker" half of the vision; ScannedCode.route (below) is the "figure
//  out what to do with it" half, shared by every entry point that
//  presents this view.
//

import SwiftUI

// DataScannerViewController/its delegate/RecognizedItem are all marked
// unavailable under Mac Catalyst (confirmed by a failed Catalyst build —
// not documented clearly anywhere obvious) — this whole representable
// only compiles for iOS/iPadOS; QRScannerSheet provides a Catalyst-safe
// fallback that never references any of these types.
#if !targetEnvironment(macCatalyst)

import VisionKit
import Vision

struct QRScannerView: UIViewControllerRepresentable {

    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {

        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .accurate,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )

        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {

        guard !context.coordinator.hasStarted else { return }
        context.coordinator.hasStarted = true

        try? uiViewController.startScanning()
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {

        let onScan: (String) -> Void
        var hasStarted = false
        private var hasFired = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {

            // Fire on the first QR code seen and stop — this view gets
            // torn down by its presenter right after, so there's nothing
            // useful about reporting a second one before that happens.
            guard !hasFired, let item = addedItems.first, case .barcode(let barcode) = item else {
                return
            }

            guard let payload = barcode.payloadStringValue else {
                return
            }

            hasFired = true
            onScan(payload)
        }
    }
}

#endif


// MARK: - Scanned code routing

/// What a scanned (or generated) QR payload means and where it should
/// take the user — shared by every scan entry point so "scan a sticker
/// on the street" behaves identically whether it happened from
/// Connections or the Browser.
enum ScannedCode {

    case lxmf(hex: String)
    case nomadNet(hex: String, path: String)
    case unrecognized

    /// LXMF addresses are shared as `lxmf://<hash>`, NomadNet pages as
    /// `nomadnet://<hash><path>` (see QRCodeView / Browser's share-page
    /// QR) — a real "scheme://" URL, not a bare "scheme:value", since
    /// that's what Apple's own Camera app (and most third-party
    /// scanners) actually recognize as actionable QR content. A bare
    /// 32-hex-character string is still accepted as LXMF too, since
    /// that's what this app generated before this format existed and
    /// existing printed/saved codes shouldn't break.
    static func parse(_ raw: String) -> ScannedCode {

        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("lxmf://") {

            let hex = String(text.dropFirst("lxmf://".count)).lowercased()
            return isValidHash(hex) ? .lxmf(hex: hex) : .unrecognized
        }

        if text.hasPrefix("nomadnet://") {

            let rest = String(text.dropFirst("nomadnet://".count))

            guard rest.count >= 32 else { return .unrecognized }

            let hex = String(rest.prefix(32)).lowercased()
            let pathPart = String(rest.dropFirst(32))
            let path = pathPart.isEmpty ? "/page/index.mu" : pathPart

            return isValidHash(hex) ? .nomadNet(hex: hex, path: path) : .unrecognized
        }

        if isValidHash(text.lowercased()) {
            return .lxmf(hex: text.lowercased())
        }

        return .unrecognized
    }

    private static func isValidHash(_ hex: String) -> Bool {
        hex.count == 32 && hex.allSatisfy(\.isHexDigit)
    }
}
