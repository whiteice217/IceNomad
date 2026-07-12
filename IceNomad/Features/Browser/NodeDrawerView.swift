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

        peers
            .filter { NomadNetNode.isNode($0) }
            .sorted { $0.lastSeen > $1.lastSeen }
    }


    private var edgeHandle: some View {

        Image(systemName: isOpen ? "chevron.left" : "chevron.right")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
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
                .padding()

            Divider()

            if nodePeers.isEmpty {

                Text("No nodes announced yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

                                    Text(contactStore.displayName(for: peer.destinationHashHex))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)

                                    Text(peer.destinationHashHex)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
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
}
