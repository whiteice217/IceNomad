//
//  ContentView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

enum AppTab: CaseIterable, Identifiable {

    case messages
    case announce
    case browser
    case settings
    case connections

    var id: Self { self }

    var label: String {
        switch self {
        case .messages: return "Messages"
        case .announce: return "Announce"
        case .browser: return "Browser"
        case .settings: return "Settings"
        case .connections: return "Connections"
        }
    }

    var icon: String {
        switch self {
        case .messages: return "message"
        case .announce: return "shareplay"
        case .browser: return "globe"
        case .settings: return "gearshape"
        case .connections: return "network"
        }
    }
}


struct ContentView: View {

    @State private var selectedTab: AppTab

    /// Defaults to Browser — IceNomad's central, day-to-day tab. Passed
    /// explicitly right after the first-run setup wizard routes the user
    /// somewhere specific instead (e.g. "Set Up an RNode" lands on
    /// Connections) — see StartupManager.pendingPostSetupTab.
    init(initialTab: AppTab? = nil) {
        _selectedTab = State(initialValue: initialTab ?? .browser)
    }

    /// Set by BrowserView when an `lxmf@<hash>` Micron link is tapped —
    /// MessagesView observes this and navigates straight to that
    /// conversation. Lives here (alongside selectedTab) since Browser and
    /// Messages are sibling tabs with no other shared state.
    @State private var pendingChatHex: String?

    /// Set by AnnounceView's "Browse" swipe action — BrowserView observes
    /// this and connects to that node, the reverse direction of
    /// pendingChatHex above. Replaces the old in-Browser node drawer: node
    /// selection now happens from the Announce tab instead of a popup.
    @State private var pendingBrowseHex: String?

    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var bannerCenter = NotificationBannerCenter.shared

    /// Identity naming + connection setup both now happen in
    /// ConnectionSetupWizardView (see StartupManager.awaitingSetup for
    /// the normal first-run trigger) — this is the *other* way to reach
    /// it, wired to Settings' "Reset Connections" action.
    @State private var isShowingSetupWizard = false

    var body: some View {

        ZStack(alignment: .top) {

            TabView(selection: $selectedTab) {

                MessagesView()
                    .tabItem {
                        Label(AppTab.messages.label, systemImage: AppTab.messages.icon)
                    }
                    .tag(AppTab.messages)
                    .badge(messageStore.totalUnreadCount)

                AnnounceView(selectedTab: $selectedTab, pendingBrowseHex: $pendingBrowseHex)
                    .tabItem {
                        Label(AppTab.announce.label, systemImage: AppTab.announce.icon)
                    }
                    .tag(AppTab.announce)

                // Central by design — Browser (Tux as its home page) is
                // meant to be IceNomad's day-to-day default, not one tab
                // among equals. Sits in the middle slot on purpose.
                BrowserView(selectedTab: $selectedTab, pendingChatHex: $pendingChatHex, pendingBrowseHex: $pendingBrowseHex)
                    .tabItem {
                        Label(AppTab.browser.label, systemImage: AppTab.browser.icon)
                    }
                    .tag(AppTab.browser)

                SettingsView(selectedTab: $selectedTab, pendingChatHex: $pendingChatHex, isShowingSetupWizard: $isShowingSetupWizard)
                    .tabItem {
                        Label(AppTab.settings.label, systemImage: AppTab.settings.icon)
                    }
                    .tag(AppTab.settings)

                ConnectionsView(selectedTab: $selectedTab, pendingChatHex: $pendingChatHex, pendingBrowseHex: $pendingBrowseHex)
                    .tabItem {
                        Label(AppTab.connections.label, systemImage: AppTab.connections.icon)
                    }
                    .tag(AppTab.connections)
            }
            // Opening a chat from anywhere other than Messages' own list used
            // to route through a Binding into MessagesView and hope its
            // onChange fired — unreliable specifically when the Messages tab
            // wasn't already the active one (two earlier fix attempts at the
            // symptom both failed). Presenting the chat as a modal sheet
            // directly here instead sidesteps the question entirely: this
            // TabView container is always live regardless of which tab is
            // showing, so this always fires. ChatView already handles both a
            // known address (existing messages) and a brand-new one (empty,
            // ready to type) the same way, so no separate "new message" path
            // is needed — this doubles as that.
            .sheet(isPresented: pendingChatPresented) {

                if let hex = pendingChatHex {

                    NavigationStack {
                        ChatView(peerHashHex: hex)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { pendingChatHex = nil }
                                }
                            }
                    }
                }
            }

            // Themed, pulsing "new message" toast — overlaid above the
            // TabView (not tied to any one tab) so it's visible regardless
            // of which tab is active when a message arrives.
            if let banner = bannerCenter.current {

                IncomingMessageBannerView(banner: banner) {
                    bannerCenter.dismiss()
                    pendingChatHex = banner.peerHashHex
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bannerCenter.current)
        .fullScreenCover(isPresented: $isShowingSetupWizard) {

            ConnectionSetupWizardView(
                onAddedConnection: { isShowingSetupWizard = false },
                onSkip: { _ in isShowingSetupWizard = false }
            )
        }
    }


    private var pendingChatPresented: Binding<Bool> {

        Binding(
            get: { pendingChatHex != nil },
            set: { if !$0 { pendingChatHex = nil } }
        )
    }
}
