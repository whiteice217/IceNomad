//
//  FavoritesStore.swift
//  IceNomad
//
//  Saved NomadNet pages, persisted locally. Shown on the Browser's home
//  screen (see BrowserView) so returning to a known page doesn't require
//  re-typing its hash or waiting for it to announce again.
//

import Foundation
import Combine


final class FavoritesStore: ObservableObject {

    static let shared = FavoritesStore()

    private init() {
        favorites = FavoritesStorage.shared.load()
    }


    @Published private(set) var favorites: [Favorite] = []


    func isFavorite(destinationHashHex: String, path: String) -> Bool {

        favorites.contains { $0.destinationHashHex == destinationHashHex && $0.path == path }
    }


    /// Adds the page if it isn't already saved, otherwise removes it —
    /// matches the single star-button toggle in BrowserView's toolbar.
    func toggle(destinationHashHex: String, path: String, label: String?) {

        if isFavorite(destinationHashHex: destinationHashHex, path: path) {
            remove(destinationHashHex: destinationHashHex, path: path)
        } else {
            add(destinationHashHex: destinationHashHex, path: path, label: label)
        }
    }


    func add(destinationHashHex: String, path: String, label: String?) {

        guard !isFavorite(destinationHashHex: destinationHashHex, path: path) else {
            return
        }

        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)

        favorites.append(
            Favorite(
                destinationHashHex: destinationHashHex,
                path: path,
                customLabel: (trimmed?.isEmpty ?? true) ? nil : trimmed,
                dateAdded: Date()
            )
        )

        persist()
    }


    func remove(destinationHashHex: String, path: String) {

        favorites.removeAll { $0.destinationHashHex == destinationHashHex && $0.path == path }
        persist()
    }


    /// Every folder name currently in use, alphabetized — feeds the
    /// "move to folder" picker in the management popover so picking an
    /// existing folder doesn't require retyping it exactly.
    var folderNames: [String] {

        Set(favorites.compactMap(\.folder)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }


    func rename(_ favorite: Favorite, to newLabel: String) {

        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }) else { return }

        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        favorites[index].customLabel = trimmed.isEmpty ? nil : trimmed
        persist()
    }


    func setFolder(_ favorite: Favorite, to folder: String?) {

        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }) else { return }

        let trimmed = folder?.trimmingCharacters(in: .whitespacesAndNewlines)
        favorites[index].folder = (trimmed?.isEmpty ?? true) ? nil : trimmed
        persist()
    }


    func remove(_ favorite: Favorite) {

        favorites.removeAll { $0.id == favorite.id }
        persist()
    }


    private func persist() {
        FavoritesStorage.shared.save(favorites)
    }
}


// MARK: - Storage

private class FavoritesStorage {

    static let shared = FavoritesStorage()

    private let key = "browser_favorites"

    func save(_ favorites: [Favorite]) {

        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> [Favorite] {

        guard let data = UserDefaults.standard.data(forKey: key),
              let favorites = try? JSONDecoder().decode([Favorite].self, from: data)
        else {
            return []
        }

        return favorites
    }
}
