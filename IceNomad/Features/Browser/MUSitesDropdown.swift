//
//  MUSitesDropdown.swift
//  IceNomad
//
//  The Browser toolbar's announce button opens this as a real popover
//  (a floating card anchored to the button, not a system Menu) — gives
//  room for a proper row layout (name, hash, hop count, last heard) and
//  a sort control, the way the old node drawer looked, without needing
//  a full-screen sheet or a slide-out side panel for it.
//

import SwiftUI

private enum SiteSortOption: String, CaseIterable, Identifiable {

    case time = "Time"
    case hops = "Hops"
    case alphabetical = "A–Z"

    var id: String { rawValue }

    var systemImage: String {

        switch self {
        case .time: return "clock"
        case .hops: return "arrow.triangle.branch"
        case .alphabetical: return "textformat"
        }
    }
}


struct MUSitesDropdown: View {

    let sites: [Peer]
    @ObservedObject var contactStore: ContactStore
    let onSelect: (Peer) -> Void

    @State private var sortOption: SiteSortOption = .time

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            Text("NomadNet")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Picker("Sort", selection: $sortOption) {

                ForEach(SiteSortOption.allCases) { option in
                    Label(option.rawValue, systemImage: option.systemImage)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if sites.isEmpty {

                Text("No MU sites heard yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)

            } else {

                ScrollView {

                    LazyVStack(alignment: .leading, spacing: 0) {

                        ForEach(sorted(sites)) { site in

                            Button {
                                onSelect(site)
                            } label: {
                                siteRow(site)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 300)
    }


    private func siteRow(_ site: Peer) -> some View {

        VStack(alignment: .leading, spacing: 2) {

            HStack {

                Text(contactStore.displayName(for: site.destinationHashHex))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(site.interfaceColor ?? Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let hops = site.hopCount {

                    Label("\(hops)", systemImage: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .labelStyle(.titleAndIcon)
                }
            }

            HStack {

                Text(site.destinationHashHex)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(PeerStore.shared.lastSeen(for: site.destinationHashHex), style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }


    private func sorted(_ list: [Peer]) -> [Peer] {

        switch sortOption {

        case .time:
            return list.sorted { PeerStore.shared.lastSeen(for: $0.destinationHashHex) > PeerStore.shared.lastSeen(for: $1.destinationHashHex) }

        case .hops:
            return list.sorted { ($0.hopCount ?? .max) < ($1.hopCount ?? .max) }

        case .alphabetical:
            return list.sorted {
                contactStore.displayName(for: $0.destinationHashHex)
                    .localizedCaseInsensitiveCompare(contactStore.displayName(for: $1.destinationHashHex)) == .orderedAscending
            }
        }
    }
}
