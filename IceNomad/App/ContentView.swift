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

    var body: some View {

        TabView(selection: $selectedTab) {

            ConnectionsView()
                .tabItem {
                    Label(AppTab.connections.label, systemImage: AppTab.connections.icon)
                }
                .tag(AppTab.connections)

            AnnounceView()
                .tabItem {
                    Label(AppTab.announce.label, systemImage: AppTab.announce.icon)
                }
                .tag(AppTab.announce)

            MessagesView()
                .tabItem {
                    Label(AppTab.messages.label, systemImage: AppTab.messages.icon)
                }
                .tag(AppTab.messages)

            BrowserView(selectedTab: $selectedTab)
                .tabItem {
                    Label(AppTab.browser.label, systemImage: AppTab.browser.icon)
                }
                .tag(AppTab.browser)

            SettingsView()
                .tabItem {
                    Label(AppTab.settings.label, systemImage: AppTab.settings.icon)
                }
                .tag(AppTab.settings)
        }
    }
}
