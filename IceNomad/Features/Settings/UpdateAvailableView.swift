//
//  UpdateAvailableView.swift
//  IceNomad
//
//  Shown when AppUpdateChecker finds a newer GitHub release than the
//  version actually running -- real patch notes (the release's own
//  body, rendered through the same MarkdownDocumentView the bundled
//  User Guide uses) plus a direct link to the release page. Bryan's
//  explicit spec: checking the box is how the user accepts that some
//  features may not match this exact patch notes text (their build is
//  now behind) while choosing to keep using it as-is -- Continue stays
//  disabled until it's checked, so that's a real acknowledgment, not
//  just a formality.
//

import SwiftUI

struct UpdateAvailableView: View {

    let update: AppUpdateChecker.UpdateInfo
    var onDismissForNow: () -> Void
    var onAcknowledge: () -> Void

    @State private var hasAcknowledged = false

    var body: some View {

        NavigationStack {

            VStack(spacing: 0) {

                ScrollView {

                    VStack(alignment: .leading, spacing: 16) {

                        VStack(alignment: .leading, spacing: 4) {

                            Text("Version \(update.version) is available")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)

                            Text("You're currently on \(AppUpdateChecker.shared.currentVersion).")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Link(destination: update.releaseURL) {
                            Label("Download the Update", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Divider()

                        MarkdownDocumentView(markdown: update.notes)
                    }
                    .padding()
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {

                    Toggle(isOn: $hasAcknowledged) {
                        Text("I understand some features may not match this version's release notes on my current build, and I want to keep using it as-is.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .toggleStyle(.switch)

                    Button {
                        onAcknowledge()
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasAcknowledged)
                }
                .padding()
                .background(Theme.surface)
            }
            .background(Theme.background)
            .navigationTitle("Update Available")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now", action: onDismissForNow)
                }
            }
        }
    }
}
