//
//  BrowserHomeView.swift
//  IceNomad
//
//  Shown in place of page content whenever the Browser has no active
//  page (nothing navigated to yet, or Home tapped with nothing to
//  return to isn't possible — this is purely the "nothing loaded"
//  state). Leads with the app logo, then either a list of saved pages
//  or, if none are saved yet, a short explainer of how browsing works.
//

import SwiftUI

struct BrowserHomeView: View {

    let favorites: [Favorite]
    let onSelect: (Favorite) -> Void
    let onDelete: (Favorite) -> Void

    var body: some View {

        ScrollView {

            VStack(spacing: 24) {

                Image("IceNomadSplash")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 96 * 0.2237, style: .continuous))
                    .padding(.top, 32)

                if favorites.isEmpty {
                    welcomeMessage
                } else {
                    favoritesList
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
        .background(Theme.background)
    }


    private var welcomeMessage: some View {

        VStack(spacing: 10) {

            Text("IceNomad Browser")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Open the node list on the left to connect to a NomadNet node. Once connected, Home will jump to that node's /page/index.mu, and links on the page will navigate normally.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Tap the star while browsing a page to save it here as a favorite.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 8)
    }


    private var favoritesList: some View {

        VStack(alignment: .leading, spacing: 0) {

            Text("Favorites")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

            ForEach(Array(favorites.enumerated()), id: \.element.id) { index, favorite in

                HStack(spacing: 12) {

                    Text("\(index + 1)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 20, alignment: .trailing)

                    Button {
                        onSelect(favorite)
                    } label: {

                        VStack(alignment: .leading, spacing: 2) {

                            Text(favorite.customLabel ?? favorite.destinationHashHex)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)

                            Text("\(favorite.destinationHashHex):\(favorite.path)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDelete(favorite)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 8)
            }
        }
    }
}
