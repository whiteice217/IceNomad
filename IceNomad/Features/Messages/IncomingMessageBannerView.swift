//
//  IncomingMessageBannerView.swift
//  IceNomad
//

import SwiftUI

struct IncomingMessageBannerView: View {

    let banner: IncomingMessageBanner
    let onTap: () -> Void

    @ObservedObject private var contactStore = ContactStore.shared

    @State private var isPulsing = false

    var body: some View {

        Button(action: onTap) {

            HStack(spacing: 12) {

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isPulsing ? 1.6 : 1.0)
                    .opacity(isPulsing ? 0.35 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear { isPulsing = true }

                VStack(alignment: .leading, spacing: 2) {

                    Text(contactStore.displayName(for: banner.peerHashHex))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Text(banner.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}
