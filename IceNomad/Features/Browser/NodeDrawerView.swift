//
//  NodeDrawerView.swift
//  IceNomad
//
//  Pulls out over the browser from the left edge. Lists announced
//  NomadNet nodes (filtered from PeerStore via NomadNetNode), lets you
//  scroll and tap one to "connect", then slides back into hiding.
//

import SwiftUI

struct NodeDrawerView: View {

    @Binding var isOpen: Bool
    let peers: [Peer]
    @ObservedObject var contactStore: ContactStore
    let onSelect: (Peer) -> Void

    @State private var searchText: String = ""

    var body: some View {
        HStack(spacing: 0) {

            if isOpen {

                drawerContent
                    .frame(width: 270)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .leading))
            }

            edgeHandle

            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isOpen)
    }


    private var nodePeers: [Peer] {

        let nodes = peers.filter { NomadNetNode.isNode($0) }

        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        let matched: [Peer]

        if trimmed.isEmpty {

            matched = nodes

        } else if let hopQuery = UInt8(trimmed) {

            // A pure number searches by hop count instead of name — lets
            // you quickly find the closest (or a specific-distance) node
            // without typing anything else.
            matched = nodes.filter { $0.hopCount == hopQuery }

        } else {

            matched = nodes.filter {
                contactStore.displayName(for: $0.destinationHashHex)
                    .localizedCaseInsensitiveContains(trimmed)
            }
        }

        return matched.sorted { $0.lastSeen > $1.lastSeen }
    }


    private var edgeHandle: some View {

        Image(systemName: isOpen ? "chevron.left" : "chevron.right")
            .font(.caption.bold())
            .foregroundStyle(Theme.textSecondary)
            .padding(10)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(radius: 3)
            .contentShape(Circle())
            .padding(.leading, isOpen ? 4 : 6)
            .padding(.top, 60)
            .onTapGesture {
                isOpen.toggle()
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in

                        if value.translation.width > 8 {
                            isOpen = true
                        }

                        if value.translation.width < -8 {
                            isOpen = false
                        }
                    }
            )
    }


    private var drawerContent: some View {

        VStack(alignment: .leading, spacing: 0) {

            Text("NomadNet Nodes")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            searchField
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 10)

            Divider()

            if nodePeers.isEmpty {

                Text(searchText.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "No nodes announced yet."
                     : "No nodes match \"\(searchText)\".")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding()

                Spacer()

            } else {

                ScrollView {

                    LazyVStack(alignment: .leading, spacing: 0) {

                        ForEach(nodePeers) { peer in

                            Button {
                                onSelect(peer)
                            } label: {

                                VStack(alignment: .leading, spacing: 2) {

                                    HStack {

                                        Text(contactStore.displayName(for: peer.destinationHashHex))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(peer.interfaceColor ?? Theme.textPrimary)
                                            .lineLimit(1)

                                        Spacer(minLength: 8)

                                        if let hops = peer.hopCount {

                                            Label("\(hops)", systemImage: "arrow.triangle.branch")
                                                .font(.caption2)
                                                .foregroundStyle(Theme.textSecondary)
                                                .labelStyle(.titleAndIcon)
                                        }
                                    }

                                    Text(peer.destinationHashHex)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Divider()
                                .padding(.leading)
                        }
                    }
                }
            }
        }
    }


    private var searchField: some View {

        HStack(spacing: 6) {

            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            TextField("Search name or hop count", text: $searchText)
                .font(.caption)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {

                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
