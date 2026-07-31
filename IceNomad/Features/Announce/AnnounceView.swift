//
//  AnnounceView.swift
//  IceNomad
//

import SwiftUI

/// Announces on a shared public Reticulum network aren't all the same
/// kind of thing — a raw announce carries no notion of "this is a
/// NomadNet node" vs "this is an LXMF messaging peer" beyond its
/// destination's aspect name hash (see Peer.isNomadNetNode/isLXMFPeer,
/// each a real positive check against the actual expected hash for that
/// aspect, not a guess). Mixing all of them into one undifferentiated
/// list is what made the Browser's "announce" button land somewhere that
/// didn't obviously match "nodes I can browse."
private enum PeerScope: String, CaseIterable, Identifiable {

    case lxmf = "LXMF(Messages)"
    case nodes = "MU Sites"
    // Named "Unknown" rather than "Other" — "Unnamed Peers" is already
    // used elsewhere on this screen for a different thing (a peer with
    // no announced display name), and calling this scope "Other" implied
    // a known third category when really it's just "didn't match either
    // real aspect hash." See the nameHash diagnostic on rows in this
    // scope (peerRow) for helping tell real-but-unrecognized apps apart
    // from anything that looks like garbage.
    case other = "Unknown"

    var id: String { rawValue }
}


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

    @Binding var selectedTab: AppTab
    /// Set on a "Browse" swipe action — BrowserView observes this and
    /// connects to that node, replacing the old in-Browser node drawer.
    @Binding var pendingBrowseHex: String?

    @ObservedObject private var peerStore = PeerStore.shared
    @ObservedObject private var contactStore = ContactStore.shared
    @ObservedObject private var interfaceManager = InterfaceManager.shared

    @State private var contactsExpanded = true
    @State private var unnamedExpanded = false
    @State private var chatTarget: String?
    @State private var sortOption: PeerSortOption = .lastHeard
    @State private var scope: PeerScope = .lxmf
    @State private var searchText = ""
    @State private var didSendAnnounce = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                Picker("Scope", selection: $scope) {

                    ForEach(PeerScope.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Group {
                    if searchFilteredPeers.isEmpty {

                        if scopedPeers.isEmpty {

                            ContentUnavailableView(
                                emptyStateTitle,
                                systemImage: "dot.radiowaves.left.and.right",
                                description: Text(emptyStateDescription)
                            )

                        } else {

                            ContentUnavailableView.search(text: searchText)
                        }

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
                                    .foregroundStyle(Theme.success)
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
                                    .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .listRowSpacing(12)
                    .listRowBackground(Theme.surface)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Announce")
            .searchable(text: $searchText, prompt: "Search name, hash, or hop count")
            .navigationDestination(item: $chatTarget) { hex in
                ChatView(peerHashHex: hex)
            }
            .toolbar {

                // Moved here from Settings — this is where announcing
                // and controlling how many get kept actually belongs;
                // Settings still has "Your Identity" (the name that goes
                // out in the announce), just not the trigger/history knob.
                ToolbarItem(placement: .topBarLeading) {

                    Menu {

                        Button {

                            interfaceManager.sendAnnounce()
                            didSendAnnounce = true

                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                didSendAnnounce = false
                            }

                        } label: {
                            Label("Send Announce Now", systemImage: "megaphone")
                        }

                        Picker("Keep Announces", selection: $peerStore.maxAnnounces) {

                            ForEach(PeerStore.announceLimitOptions, id: \.self) { limit in
                                Text("\(limit)").tag(limit)
                            }
                        }

                    } label: {
                        Image(systemName: didSendAnnounce ? "checkmark.circle.fill" : "megaphone")
                            .foregroundStyle(didSendAnnounce ? Theme.success : Theme.textPrimary)
                    }
                }

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

    private var scopedPeers: [Peer] {

        switch scope {
        case .nodes: return peerStore.peers.filter(\.isNomadNetNode)
        case .lxmf: return peerStore.peers.filter(\.isLXMFPeer)
        case .other: return peerStore.peers.filter { !$0.isNomadNetNode && !$0.isLXMFPeer }
        }
    }

    private var emptyStateTitle: String {

        switch scope {
        case .nodes: return "No MU Sites Yet"
        case .lxmf: return "No LXMF Peers Yet"
        case .other: return "Nothing Else Heard"
        }
    }

    private var emptyStateDescription: String {

        switch scope {
        case .nodes: return "NomadNet nodes you can browse will appear here as they announce."
        case .lxmf: return "LXMF messaging peers will appear here as they announce."
        case .other: return "Announces from anything else on the network will appear here."
        }
    }

    /// A pure number searches by hop count instead of name/hash — lets
    /// you quickly find the closest (or a specific-distance) peer without
    /// typing anything else. Matches the old node drawer's search before
    /// it was replaced by this scope-based screen.
    private var searchFilteredPeers: [Peer] {

        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else { return scopedPeers }

        if let hopQuery = UInt8(trimmed) {
            return scopedPeers.filter { $0.hopCount == hopQuery }
        }

        return scopedPeers.filter {
            contactStore.displayName(for: $0.destinationHashHex).localizedCaseInsensitiveContains(trimmed)
                || $0.destinationHashHex.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var contactPeers: [Peer] {

        searchFilteredPeers.filter { contactStore.isContact($0.destinationHashHex) }
    }

    private var namedPeers: [Peer] {

        searchFilteredPeers.filter { $0.displayName != nil }
    }

    private var unnamedPeers: [Peer] {

        searchFilteredPeers.filter { $0.displayName == nil }
    }


    // MARK: - Row

    @ViewBuilder
    private func peerRow(_ peer: Peer) -> some View {

        let isContact = contactStore.isContact(peer.destinationHashHex)

        // A per-row Menu instead of .swipeActions — a swipe gesture
        // doesn't exist on a Mac trackpad click, confirmed not working
        // there. Tap/click on the ellipsis behaves the same on both.
        HStack(alignment: .top, spacing: 8) {

        peerDetails(peer, isContact: isContact)

        Spacer(minLength: 8)

        Menu {

            if peer.isNomadNetNode {

                Button {
                    pendingBrowseHex = peer.destinationHashHex
                    selectedTab = .browser
                } label: {
                    Label("Browse", systemImage: "globe")
                }
            }

            if peer.isLXMFPeer {

                Button {
                    chatTarget = peer.destinationHashHex
                } label: {
                    Label("Message", systemImage: "message")
                }
            }

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

        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        }
    }


    /// The row's text content — split out from peerRow so the trailing
    /// Menu button (see peerRow) can sit alongside it instead of being
    /// swallowed by the tap-to-browse gesture below.
    @ViewBuilder
    private func peerDetails(_ peer: Peer, isContact: Bool) -> some View {

        VStack(alignment: .leading, spacing: 4) {

            HStack {

                Text(contactStore.displayName(for: peer.destinationHashHex))
                    .font(.headline)
                    .foregroundStyle(peer.interfaceColor ?? Theme.textPrimary)

                if isContact {
                    Image(systemName: "person.fill.checkmark")
                        .foregroundStyle(Theme.success)
                        .font(.caption)
                }
            }

            Text(peer.destinationHashHex)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            if scope == .other {

                // The whole point of this scope is "didn't match a
                // recognized aspect" — showing the raw aspect nameHash
                // lets Bryan actually tell a real unrecognized app
                // (Sideband-style variants, other RNS demos/tools on the
                // same shared network) apart from garbage, instead of me
                // guessing without live traffic to look at.
                Text("Aspect hash: \(peer.nameHash.hexString)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            HStack {

                if let hops = peer.hopCount {
                    Label("\(hops) hop\(hops == 1 ? "" : "s")", systemImage: "arrow.triangle.branch")
                }

                Text(peerStore.lastSeen(for: peer.destinationHashHex), style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {

            // A MU Site row's whole tap target jumps straight into
            // browsing it — this is the primary reason to be looking at
            // this scope at all, so it doesn't need to hide behind the
            // swipe action the way Message/Add Contact do.
            guard peer.isNomadNetNode else { return }

            pendingBrowseHex = peer.destinationHashHex
            selectedTab = .browser
        }
    }


    // MARK: - Sorting

    private func sorted(_ list: [Peer]) -> [Peer] {

        switch sortOption {

        case .lastHeard:
            return list.sorted { peerStore.lastSeen(for: $0.destinationHashHex) > peerStore.lastSeen(for: $1.destinationHashHex) }

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
