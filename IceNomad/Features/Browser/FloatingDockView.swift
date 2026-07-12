//
//  FloatingDockView.swift
//  IceNomad
//
//  A bottom dock that's normally collapsed to a small handle, expands
//  on tap/swipe-up to show every tab, and auto-collapses a couple
//  seconds after your last interaction. Exists because BrowserView
//  hides the system tab bar to go full-screen — this is the way back.
//

import SwiftUI

struct FloatingDockView: View {

    @Binding var selectedTab: AppTab

    @State private var isExpanded = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack {

            Spacer()

            Group {
                if isExpanded {
                    dockContent
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    handle
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 10)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
    }


    private var handle: some View {

        Image(systemName: "chevron.up")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(12)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(radius: 3)
            .contentShape(Circle())
            .onTapGesture {
                expand()
            }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        if value.translation.height < -8 {
                            expand()
                        }
                    }
            )
    }


    private var dockContent: some View {

        HStack(spacing: 24) {

            ForEach(AppTab.allCases) { tab in

                Button {
                    selectedTab = tab
                    scheduleAutoHide()
                } label: {
                    VStack(spacing: 3) {

                        Image(systemName: tab.icon)
                            .font(.title3)

                        Text(tab.label)
                            .font(.caption2)
                    }
                    .foregroundStyle(tab == selectedTab ? Color.accentColor : Color.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(radius: 6)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    if value.translation.height > 8 {
                        collapse()
                    }
                }
        )
        .onAppear {
            scheduleAutoHide()
        }
    }


    private func expand() {

        hideTask?.cancel()

        withAnimation {
            isExpanded = true
        }

        scheduleAutoHide()
    }


    private func collapse() {

        hideTask?.cancel()

        withAnimation {
            isExpanded = false
        }
    }


    private func scheduleAutoHide() {

        hideTask?.cancel()

        hideTask = Task {

            try? await Task.sleep(nanoseconds: 2_500_000_000)

            if !Task.isCancelled {
                withAnimation {
                    isExpanded = false
                }
            }
        }
    }
}
