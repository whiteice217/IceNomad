//
//  FavoritesManagerPopover.swift
//  IceNomad
//
//  Long-press the Browser's star button to open this — a real management
//  surface for saved pages (rename, organize into folders, delete),
//  distinct from the short-tap "favorite/unfavorite the current page"
//  gesture on the same button. A floating popover rather than a drawer,
//  matching MUSitesDropdown's pattern.
//

import SwiftUI

struct FavoritesManagerPopover: View {

    @ObservedObject var favoritesStore: FavoritesStore
    let onSelect: (Favorite) -> Void

    @State private var renamingFavorite: Favorite?
    @State private var renameText = ""

    @State private var movingFavorite: Favorite?
    @State private var newFolderText = ""

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            Text("Favorites")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if favoritesStore.favorites.isEmpty {

                Text("No favorites saved yet — star a page while browsing to add one.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)

            } else {

                ScrollView {

                    LazyVStack(alignment: .leading, spacing: 12) {

                        ForEach(groupedFolders, id: \.self) { folder in

                            VStack(alignment: .leading, spacing: 0) {

                                Text(folder ?? "Unfiled")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal)
                                    .padding(.bottom, 4)

                                ForEach(favorites(in: folder)) { favorite in

                                    favoriteRow(favorite)

                                    Divider()
                                        .padding(.leading)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 300)
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
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
