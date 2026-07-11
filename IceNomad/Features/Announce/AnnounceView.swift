//
//  AnnounceView.swift
//  IceNomad
//

import SwiftUI

private enum PeerSortOption: String, CaseIterable, Identifiable {

    case lastHeard = "Last Heard"
    case alphabetical = "Name (A–Z)"
    case reverseAlphabetical = "Name (Z–A)"
    case hopCount = "Hop Count"

    var id: String { rawValue }

    var systemImage: String {

        switch self {
        case .lastHeard: return "clock"
        case .alphabetical: return "arrow.down"
        case .reverseAlphabetical: return "arrow.up"
        case .hopCount: return "arrow.triangle.branch"
        }
    }
}


struct AnnounceView: View {

    @ObservedObject private var peerStore = PeerStore.shared
    @ObservedObject private var contactStore = ContactStore.shared

    @State private var contactsExpanded = true
    @State private var unnamedExpanded = false
    @State private var chatTarget: String?
    @State private var sortOption: PeerSortOption = .lastHeard

    var body: some View {
        NavigationStack {
            Group {
                if peerStore.peers.isEmpty {

                    ContentUnavailableView(
                        "No Announces Yet",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Peers will appear here as announces are received.")
                    )

                } else {

                    List {

                        if !contactPeers.isEmpty {

                            Section {

                                DisclosureGroup(isExpanded: $contactsExpanded) {

                                    ForEach(sorted(contactPeers)) { peer in
                                        peerRow(peer)
                                    }

                                } label: {

                                    Label(
                                        "Contacts (\(contactPeers.count))",
                                        systemImage: "person.fill.checkmark"
                                    )
                                    .foregroundStyle(.green)
                                }
                            }
                        }

                        Section {

                            ForEach(sorted(namedPeers)) { peer in
                                peerRow(peer)
                            }

                        } header: {

                            if !contactPeers.isEmpty || !unnamedPeers.isEmpty {
                                Text("Peers")
                            }
                        }

                        if !unnamedPeers.isEmpty {

                            Section {

                                DisclosureGroup(isExpanded: $unnamedExpanded) {

                                    ForEach(sorted(unnamedPeers)) { peer in
                                        peerRow(peer)
                                    }

                                } label: {

                                    Label(
                                        "Unnamed Peers (\(unnamedPeers.count))",
                                        systemImage: "questionmark.circle"
                                    )
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listRowSpacing(12)
                }
            }
            .navigationTitle("Announce")
            .navigationDestination(item: $chatTarget) { hex in
                ChatView(peerHashHex: hex)
            }
            .toolbar {

                ToolbarItem(placement: .topBarTrailing) {

                    Menu {

                        Picker("Sort", selection: $sortOption) {

                            ForEach(PeerSortOption.allCases) { option in

                                Label(option.rawValue, systemImage: option.systemImage)
                                    .tag(option)
                            }
                        }

                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
        }
    }


    // MARK: - Filtering

    private var contactPeers: [Peer] {

        peerStore.peers.filter { contactStore.isContact($0.destinationHashHex) }
    }

    private var namedPeers: [Peer] {

        peerStore.peers.filter { $0.displayName != nil }
    }

    private var unnamedPeers: [Peer] {

        peerStore.peers.filter { $0.displayName == nil }
    }


    // MARK: - Row

    @ViewBuilder
    private func peerRow(_ peer: Peer) -> some View {

        let isContact = contactStore.isContact(peer.destinationHashHex)

        VStack(alignment: .leading, spacing: 4) {

            HStack {

                Text(contactStore.displayName(for: peer.destinationHashHex))
                    .font(.headline)

                if isContact {
                    Image(systemName: "person.fill.checkmark")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Text(peer.destinationHashHex)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {

                if let hops = peer.hopCount {
                    Label("\(hops) hop\(hops == 1 ? "" : "s")", systemImage: "arrow.triangle.branch")
                }

                Text(peer.lastSeen, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {

            Button {
                chatTarget = peer.destinationHashHex
            } label: {
                Label("Message", systemImage: "message")
            }
            .tint(.blue)

            Button {

                if isContact {
                    contactStore.removeContact(hex: peer.destinationHashHex)
                } else {
                    contactStore.addContact(hex: peer.destinationHashHex)
                }

            } label: {
                Label(
                    isContact ? "Remove Contact" : "Add Contact",
                    systemImage: isContact ? "person.fill.xmark" : "person.badge.plus"
                )
            }
            .tint(.green)
        }
    }


    // MARK: - Sorting

    private func sorted(_ list: [Peer]) -> [Peer] {

        switch sortOption {

        case .lastHeard:
            return list.sorted { $0.lastSeen > $1.lastSeen }

        case .alphabetical:
            return list.sorted {
                sortKey(for: $0).localizedCaseInsensitiveCompare(sortKey(for: $1)) == .orderedAscending
            }

        case .reverseAlphabetical:
            return list.sorted {
                sortKey(for: $0).localizedCaseInsensitiveCompare(sortKey(for: $1)) == .orderedDescending
            }

        case .hopCount:
            return list.sorted {
                ($0.hopCount ?? .max) < ($1.hopCount ?? .max)
            }
        }
    }


    private func sortKey(for peer: Peer) -> String {

        contactStore.displayName(for: peer.destinationHashHex)
    }
}


extension Peer: Hashable {

    static func == (lhs: Peer, rhs: Peer) -> Bool {
        lhs.destinationHashHex == rhs.destinationHashHex
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(destinationHashHex)
    }
}
