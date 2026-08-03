//
//  FavoritesDrawerView.swift
//  IceNomad
//
//  Mac Catalyst-only counterpart to FavoritesManagerPopover — a real
//  in-view right-side drawer that shrinks BrowserView's content column
//  instead of floating over it. On Mac, clicking the star button always
//  opens this drawer now; the old short-tap "favorite/unfavorite the
//  current page" gesture moves to the "Add/Remove This Page" row here
//  instead of living on the star button itself. iOS keeps the existing
//  short-tap-toggle + long-press-popover behavior unchanged. Folder
//  grouping and the rename/move-to-folder interaction are ported from
//  FavoritesManagerPopover rather than shared — both are file-private
//  to their own view, and this drawer deliberately uses a real List
//  (for native swipe-to-delete) where the popover uses a plain
//  ScrollView/LazyVStack, so the two aren't pixel-identical by design.
//

import SwiftUI

struct FavoritesDrawerView: View {

    @ObservedObject var favoritesStore: FavoritesStore
    let currentPage: BrowserState.PageRef?
    let isCurrentFavorited: Bool
    let onToggleCurrent: () -> Void
    let onSelect: (Favorite) -> Void
    let onClose: () -> Void

    @State private var renamingFavorite: Favorite?
    @State private var renameText = ""

    @State private var movingFavorite: Favorite?
    @State private var newFolderText = ""

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            HStack {

                Text("Favorites")
                    .font(.headline)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if currentPage != nil {

                Button {
                    onToggleCurrent()
                } label: {
                    Label(
                        isCurrentFavorited ? "Remove This Page" : "Add This Page",
                        systemImage: isCurrentFavorited ? "star.fill" : "star"
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()
            }

            if favoritesStore.favorites.isEmpty {

                Text("No favorites saved yet — add this page, or star one while browsing.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer()

            } else {

                List {

                    ForEach(groupedFolders, id: \.self) { folder in

                        Section {

                            ForEach(favorites(in: folder)) { favorite in

                                favoriteRow(favorite)
                                    .swipeActions(edge: .trailing) {

                                        Button(role: .destructive) {
                                            favoritesStore.remove(favorite)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }

                        } header: {
                            Text(folder ?? "Unfiled")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .alert("Rename Favorite", isPresented: renamingBinding) {

            TextField("Label", text: $renameText)

            Button("Save") {
                if let favorite = renamingFavorite {
                    favoritesStore.rename(favorite, to: renameText)
                }
            }

            Button("Cancel", role: .cancel) {}
        }
        .alert("New Folder", isPresented: movingBinding) {

            TextField("Folder name", text: $newFolderText)

            Button("Save") {
                if let favorite = movingFavorite {
                    favoritesStore.setFolder(favorite, to: newFolderText)
                }
            }

            Button("Cancel", role: .cancel) {}
        }
    }


    private var renamingBinding: Binding<Bool> {

        Binding(
            get: { renamingFavorite != nil },
            set: { if !$0 { renamingFavorite = nil } }
        )
    }


    private var movingBinding: Binding<Bool> {

        Binding(
            get: { movingFavorite != nil },
            set: { if !$0 { movingFavorite = nil } }
        )
    }


    private var groupedFolders: [String?] {

        var seen = Set<String?>()
        var order: [String?] = []

        for favorite in favoritesStore.favorites {

            if !seen.contains(favorite.folder) {
                seen.insert(favorite.folder)
                order.append(favorite.folder)
            }
        }

        // Unfiled (nil) always leads, named folders follow alphabetically.
        return order.sorted { lhs, rhs in

            switch (lhs, rhs) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (a?, b?): return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        }
    }


    private func favorites(in folder: String?) -> [Favorite] {

        favoritesStore.favorites.filter { $0.folder == folder }
    }


    private func favoriteRow(_ favorite: Favorite) -> some View {

        HStack(spacing: 8) {

            Button {
                onSelect(favorite)
            } label: {

                VStack(alignment: .leading, spacing: 2) {

                    Text(favorite.customLabel ?? favorite.destinationHashHex)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Text("\(favorite.destinationHashHex):\(favorite.path)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {

                Button {
                    renameText = favorite.customLabel ?? ""
                    renamingFavorite = favorite
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Menu {

                    Button("Unfiled") {
                        favoritesStore.setFolder(favorite, to: nil)
                    }

                    ForEach(favoritesStore.folderNames, id: \.self) { name in
                        Button(name) {
                            favoritesStore.setFolder(favorite, to: name)
                        }
                    }

                    Button {
                        newFolderText = ""
                        movingFavorite = favorite
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                    }

                } label: {
                    Label("Move to Folder", systemImage: "folder")
                }

                Button(role: .destructive) {
                    favoritesStore.remove(favorite)
                } label: {
                    Label("Delete", systemImage: "trash")
                }

            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
            }
        }
    }
}
