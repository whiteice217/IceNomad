//
//  ContentView.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI

enum AppTab: CaseIterable, Identifiable {

    case messages
    case browser
    case settings

    var id: Self { self }

    var label: String {
        switch self {
        case .messages: return "Messages"
        case .browser: return "Browser"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .messages: return "message"
        case .browser: return "globe"
        case .settings: return "gearshape"
        }
    }
}


struct ContentView: View {

    @State private var selectedTab: AppTab

    /// Defaults to Browser — IceNomad's central, day-to-day tab. Passed
    /// explicitly right after the first-run setup wizard routes the user
    /// somewhere specific instead — see StartupManager.pendingPostSetupTab.
    /// (Connections is reached via Settings now, not its own tab.)
    init(initialTab: AppTab? = nil) {
        _selectedTab = State(initialValue: initialTab ?? .browser)
    }

    /// Set by BrowserView when an `lxmf@<hash>` Micron link is tapped —
    /// MessagesView observes this and navigates straight to that
    /// conversation. Lives here (alongside selectedTab) since Browser and
    /// Messages are sibling tabs with no other shared state.
    @State private var pendingChatHex: String?

    /// Set after a QR scan (Connections) resolves to a NomadNet page —
    /// BrowserView observes this and connects to that node. The
    /// Announce tab used to also set this via a "Browse" swipe action,
    /// but that whole tab was removed (Bryan's call: NomadNet-node
    /// discovery happens through Tux search in Browser now, and the
    /// tab's LXMF-specific job moved to Messages) — QR scanning is the
    /// only remaining source of this hint.
    @State private var pendingBrowseHex: String?

    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var bannerCenter = NotificationBannerCenter.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var updateChecker = AppUpdateChecker.shared

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

                // Central by design — Browser (Tux as its home page) is
                // meant to be IceNomad's day-to-day default, not one tab
                // among equals. Sits in the middle slot on purpose.
                BrowserView(selectedTab: $selectedTab, pendingChatHex: $pendingChatHex, pendingBrowseHex: $pendingBrowseHex)
                    .tabItem {
                        Label(AppTab.browser.label, systemImage: AppTab.browser.icon)
                    }
                    .tag(AppTab.browser)

                // Connections used to be its own tab — folded into a
                // "Manage Connections" row here instead (Bryan's call:
                // "no need for an extra button that causes confusion").
                // ConnectionsView itself is unchanged internally, just
                // reached via NavigationLink now instead of the tab bar.
                SettingsView(selectedTab: $selectedTab, pendingChatHex: $pendingChatHex, pendingBrowseHex: $pendingBrowseHex, isShowingSetupWizard: $isShowingSetupWizard)
                    .tabItem {
                        Label(AppTab.settings.label, systemImage: AppTab.settings.icon)
                    }
                    .tag(AppTab.settings)
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
        // A tapped download's save-location prompt — asked *before* any
        // network fetch happens (see DownloadManager's header comment),
        // and lives here rather than on BrowserView so it always
        // reliably appears the instant a link is tapped, whether or not
        // the Downloads list sheet (also on BrowserView) happens to be
        // open. See BrowserView's matching comment.
        .sheet(item: $downloadManager.pendingExport) { export in

            DocumentExporterView(url: export.placeholderURL) { pickedURL in
                downloadManager.destinationPicked(id: export.id, url: pickedURL)
            } onCancel: {
                downloadManager.destinationPickCancelled(id: export.id)
            }
        }
        // One check per launch, fired from here (not StartupManager) so
        // it never gates or delays the splash sequence — this is purely
        // informational, not something worth making the user wait on.
        .onAppear {
            AppUpdateChecker.shared.checkForUpdate()
        }
        .sheet(isPresented: updateAvailablePresented) {

            if let update = updateChecker.availableUpdate {

                UpdateAvailableView(
                    update: update,
                    onDismissForNow: { updateChecker.dismissForNow() },
                    onAcknowledge: { updateChecker.acknowledge() }
                )
            }
        }
    }


    private var pendingChatPresented: Binding<Bool> {

        Binding(
            get: { pendingChatHex != nil },
            set: { if !$0 { pendingChatHex = nil } }
        )
    }


    private var updateAvailablePresented: Binding<Bool> {

        Binding(
            get: { updateChecker.availableUpdate != nil },
            set: { if !$0 { updateChecker.dismissForNow() } }
        )
    }
}
