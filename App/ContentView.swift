//
//  ContentView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

struct ContentView: View {

    var body: some View {

        TabView {
            
            ConnectionsView()
                .tabItem {
                    Label("Connections", systemImage: "network")
                }
            AnnounceView()
                .tabItem {
                    Label("Announce", systemImage: "shareplay")
                }
            
            MessagesView()
                .tabItem {
                    Label("Messages", systemImage: "message")
                }
            
            BrowserView()
                .tabItem {
                    Label("Browser", systemImage: "globe")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
