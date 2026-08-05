//
//  UserGuideView.swift
//  IceNomad
//
//  Settings > Getting Started — renders USER_GUIDE.md, bundled directly
//  into the app (Resources/USER_GUIDE.md, same "just drop it in the
//  synced folder" pattern nootnoot.mp3 already uses — no separate
//  Xcode project-file wiring needed) so it's available offline, in
//  every build, not just on GitHub. Bryan's explicit ask, 2026-08-05.
//

import SwiftUI

struct UserGuideView: View {

    var body: some View {

        ScrollView {

            Group {

                if let markdown = Self.loadBundledGuide() {
                    MarkdownDocumentView(markdown: markdown)
                } else {
                    // Shouldn't happen outside a broken build (the file
                    // missing from Resources/) -- a plain fallback
                    // beats a blank screen if it ever does.
                    Text("The guide couldn't be loaded. Report this — it should always be bundled with the app.")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Getting Started")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }


    private static func loadBundledGuide() -> String? {
        guard let url = Bundle.main.url(forResource: "USER_GUIDE", withExtension: "md") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
