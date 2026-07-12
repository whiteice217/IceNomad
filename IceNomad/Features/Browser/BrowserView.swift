//
//  BrowserView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//
//  Full-screen browser: custom top bar (node list toggle, back/forward,
//  home, address bar, downloads), a left-edge node drawer, and a
//  bottom floating dock standing in for the (hidden) system tab bar.
//
//  Page content is still placeholder text — see BrowserState — until
//  the crypto/Link layer exists to actually fetch real pages.
//

import SwiftUI

struct BrowserView: View {

    @Binding var selectedTab: AppTab

    @StateObject private var orientation = OrientationObserver()
    @StateObject private var browserState = BrowserState()
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var peerStore = PeerStore.shared
    @ObservedObject private var contactStore = ContactStore.shared

    @State private var isShowingDownloads = false
    @State private var isNodeDrawerOpen = false

    var body: some View {
        ZStack {

            VStack(spacing: 0) {

                topBar

                Divider()

                ScrollView {
                    MicronView(source: browserState.content) { link in
                        browserState.followLink(link)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            NodeDrawerView(
                isOpen: $isNodeDrawerOpen,
                peers: peerStore.peers,
                contactStore: contactStore
            ) { peer in

                browserState.connect(to: peer.destinationHashHex)

                withAnimation {
                    isNodeDrawerOpen = false
                }
            }

            FloatingDockView(selectedTab: $selectedTab)

            if orientation.isLandscape {
                OrientationOverlay()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $isShowingDownloads) {
            DownloadsView()
        }
    }


    private var topBar: some View {

        HStack(spacing: 12) {

            Button {
                withAnimation {
                    isNodeDrawerOpen.toggle()
                }
            } label: {
                Image(systemName: "list.bullet")
            }

            Button {
                browserState.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!browserState.canGoBack)

            Button {
                browserState.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!browserState.canGoForward)

            Button {
                browserState.goHome()
            } label: {
                Image(systemName: "house")
            }
            .disabled(browserState.current?.destinationHashHex == nil)

            TextField("Node hash : path", text: $browserState.addressText, onCommit: {
                browserState.navigateFromAddressBar()
            })
            .textFieldStyle(.roundedBorder)
            .font(.system(.footnote, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            DownloadsButton(progress: downloadManager.activeProgress) {
                isShowingDownloads = true
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
