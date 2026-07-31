//
//  QRCodeView.swift
//  IceNomad
//
//  Renders a destination address as a scannable QR code — the fastest
//  way to hand someone your LXMF address in person, no typing 32 hex
//  characters by hand.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {

    let label: String
    let value: String
    /// Prefixed onto `value` inside the QR image itself (not the text
    /// shown below it, which stays plain for easy manual copying) so a
    /// scan self-describes what kind of address this is — see
    /// ScannedCode.parse. Nil means encode `value` as-is.
    var scheme: String? = nil

    @Environment(\.dismiss) private var dismiss

    private var qrPayload: String {

        guard let scheme else { return value }

        // A real "scheme://" URL, not a bare "scheme:value" — Apple's
        // own Camera app (and most third-party scanners) only recognize
        // well-formed URLs as actionable QR content; a colon-only prefix
        // with no "//" was scanning as unusable/no-data in Camera even
        // though IceNomad's own VisionKit-based scanner read it fine.
        return "\(scheme)://\(value)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                if let image = Self.generate(from: qrPayload) {

                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.top, 24)

                } else {

                    ContentUnavailableView(
                        "Couldn't Generate QR Code",
                        systemImage: "qrcode"
                    )
                }

                Text(value)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .navigationTitle(label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }


    private static func generate(from string: String) -> UIImage? {

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return nil
        }

        // The raw CI output is tiny (one pixel per module) — scale it up
        // with nearest-neighbor so it stays crisp instead of blurring.
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

        let context = CIContext()

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
