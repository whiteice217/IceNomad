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

        VStack(alignment: .leading, spacing: 22) {

            VStack(spacing: 8) {

                Text("IceNomad Browser")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Begin browsing by selecting the announce icon (\(Image(systemName: AppTab.announce.icon))) and choosing a node.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {

                Text("THE ADDRESS BAR")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.5)

                Text("Shows the page's address: **node hash : path** — the node's destination hash, followed by the page it's serving. Most nodes default to `/page/index.mu`.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {

                Text("CONTROLS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.5)

                controlRow(
                    icon: AppTab.announce.icon,
                    text: "Shows any node that's announced itself, based on how many are kept — set from this Announce page, under **Keep Announces**."
                )
                controlRow(icon: "chevron.left", text: "Wander back to the previous page.")
                controlRow(icon: "chevron.right", text: "Wander forward to a page you'd gone back from.")
                controlRow(icon: "star", text: "Favorite the current page for later Wandering.")
                controlRow(icon: "arrow.clockwise", text: "Reload the page — or just pull down to refresh.")
                controlRow(icon: "xmark", text: "Stop the page from loading.")
                controlRow(icon: "arrow.down.circle", text: "View active or past downloads — cancel one in progress, or clear finished ones from the list.")
            }

            VStack(alignment: .leading, spacing: 4) {

                Text("ABOUT NOMADNET PAGES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(0.5)

                Text("NomadNet nodes serve pages written in **Micron** (`.mu`) — a lightweight markup in the spirit of an old BBS: plain text, simple formatting, and links to other pages, files, or people. Anyone running a node can publish one, and any NomadNet-compatible client (including IceNomad) can browse it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
    }


    @ViewBuilder
    private func controlRow(icon: String, text: String) -> some View {

        HStack(alignment: .top, spacing: 10) {

            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(Theme.accent)
                .frame(width: 20)

            Text(LocalizedStringKey(text))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
