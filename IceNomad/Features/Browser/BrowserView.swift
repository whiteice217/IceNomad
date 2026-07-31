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

    @StateObject private var browserState = BrowserState()
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var peerStore = PeerStore.shared
    @ObservedObject private var contactStore = ContactStore.shared

    @State private var isShowingDownloads = false
    @State private var isNodeDrawerOpen = false
    @FocusState private var isAddressFieldFocused: Bool

    var body: some View {
        ZStack {

            VStack(spacing: 0) {

                topBar

                Divider()

                // Real Micron pages are authored against a fixed-width
                // terminal grid — ASCII-art banners only hold their shape
                // unwrapped. Rather than force-reflowing (and breaking)
                // them to fit a narrow phone screen, the page renders at
                // its natural width and pans like an image; landscape
                // naturally reveals more of it at once.
                ScrollView([.horizontal, .vertical]) {
                    MicronView(source: browserState.content) { link in
                        browserState.followLink(link)
                    }
                    .padding()
                }
                .background(Theme.background)
                .scrollDismissesKeyboard(.immediately)
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
                isAddressFieldFocused = false
                browserState.navigateFromAddressBar()
            })
            .textFieldStyle(.roundedBorder)
            .font(.system(.footnote, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($isAddressFieldFocused)

            Button {
                isAddressFieldFocused = false
                browserState.navigateFromAddressBar()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
            }
            .disabled(browserState.addressText.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                browserState.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(browserState.current == nil)

            DownloadsButton(progress: downloadManager.activeProgress) {
                isShowingDownloads = true
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
