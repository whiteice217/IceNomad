//
//  ContentView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

enum AppTab: CaseIterable, Identifiable {

    case connections
    case announce
    case messages
    case browser
    case settings

    var id: Self { self }

    var label: String {
        switch self {
        case .connections: return "Connections"
        case .announce: return "Announce"
        case .messages: return "Messages"
        case .browser: return "Browser"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .connections: return "network"
        case .announce: return "shareplay"
        case .messages: return "message"
        case .browser: return "globe"
        case .settings: return "gearshape"
        }
    }
}


struct ContentView: View {

    @State private var selectedTab: AppTab = .connections

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

    var body: some View {

        TabView(selection: $selectedTab) {

            ConnectionsView(selectedTab: $selectedTab, pendingChatHex: $pendingChatHex, pendingBrowseHex: $pendingBrowseHex)
                .tabItem {
                    Label(AppTab.connections.label, systemImage: AppTab.connections.icon)
                }
                .tag(AppTab.connections)

            AnnounceView(selectedTab: $selectedTab, pendingBrowseHex: $pendingBrowseHex)
                .tabItem {
                    Label(AppTab.announce.label, systemImage: AppTab.announce.icon)
                }
                .tag(AppTab.announce)

            MessagesView(pendingChatHex: $pendingChatHex)
                .tabItem {
                    Label(AppTab.messages.label, systemImage: AppTab.messages.icon)
                }
                .tag(AppTab.messages)

            BrowserView(selectedTab: $selectedTab, pendingChatHex: $pendingChatHex, pendingBrowseHex: $pendingBrowseHex)
                .tabItem {
                    Label(AppTab.browser.label, systemImage: AppTab.browser.icon)
                }
                .tag(AppTab.browser)

            SettingsView(selectedTab: $selectedTab, pendingChatHex: $pendingChatHex)
                .tabItem {
                    Label(AppTab.settings.label, systemImage: AppTab.settings.icon)
                }
                .tag(AppTab.settings)
        }
    }
}
