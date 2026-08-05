//
//  AnnounceDrawerView.swift
//  IceNomad
//
//  A reusable "searchable list of peers, sortable by time/hops/A-Z"
//  drawer — started life as BrowserView's own announce drawer
//  (replacing the MUSitesDropdown popover, itself reintroducing the
//  pre-69a72da node drawer idiom). Removed from Browser once the app's
//  real Announce tab existed (it duplicated that tab), then that whole
//  tab was later deleted too — its LXMF job moved to MessagesView (as
//  "Announced Contacts"), and Bryan asked for a NomadNet-node-discovery
//  version back in Browser on Mac specifically, since deleting the
//  Announce tab left no way to see what's out there to browse. Both
//  callers share this exact view; it doesn't know or care who's hosting
//  it or how the peer list was filtered — title/empty-state text and
//  the peer list itself are all passed in.
//

import SwiftUI

private enum AnnounceDrawerSortOption: String, CaseIterable, Identifiable {

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


struct AnnounceDrawerView: View {

    let title: String
    let sites: [Peer]
    let emptyStateText: String
    @ObservedObject var contactStore: ContactStore
    let onSelect: (Peer) -> Void
    let onClose: () -> Void

    @State private var sortOption: AnnounceDrawerSortOption = .time
    @State private var searchText = ""

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            HStack {

                Text(title)
                    .font(.headline)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 6) {

                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)

                TextField("Search name, hash, or hops", text: $searchText)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {

                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal)
            .padding(.bottom, 8)

            Picker("Sort", selection: $sortOption) {

                ForEach(AnnounceDrawerSortOption.allCases) { option in
                    Label(option.rawValue, systemImage: option.systemImage)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            if searchFilteredSites.isEmpty {

                Text(sites.isEmpty ? emptyStateText : "No matches for \"\(searchText)\".")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer()

            } else {

                ScrollView {

                    LazyVStack(alignment: .leading, spacing: 0) {

                        ForEach(sorted(searchFilteredSites)) { site in

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
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }


    /// A pure number searches by hop count instead of name/hash — same
    /// convention the old full Announce tab's search used.
    private var searchFilteredSites: [Peer] {

        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else { return sites }

        if let hopQuery = UInt8(trimmed) {
            return sites.filter { $0.hopCount == hopQuery }
        }

        return sites.filter {
            contactStore.displayName(for: $0.destinationHashHex).localizedCaseInsensitiveContains(trimmed)
                || $0.destinationHashHex.localizedCaseInsensitiveContains(trimmed)
        }
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
