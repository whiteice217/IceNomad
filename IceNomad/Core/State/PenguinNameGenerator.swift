//
//  PenguinNameGenerator.swift
//  IceNomad
//
//  Randomized default display names, on-theme with the rest of the app
//  (arctic/penguin — see Theme.swift, the splash screen, nootnoot.mp3)
//  instead of a flat "Anonymous Nomad" for every new install.
//

import Foundation

enum PenguinNameGenerator {

    private static let adjectives = [
        "Frosty", "Chilly", "Icy", "Waddling", "Arctic", "Blizzard",
        "Snowy", "Glacial", "Frozen", "Polar", "Huddled", "Slippery",
        "Tobogganing", "Flippered", "Downy", "Drifting", "Brisk"
    ]

    private static let nouns = [
        "Waddler", "Huddler", "Rockhopper", "Emperor", "Tobogganer",
        "Flipper", "Iceberg", "Penguin", "Chinstrap", "Gentoo",
        "Adelie", "Skipper", "Diver", "Floe-Hopper", "Wanderer"
    ]

    static func random() -> String {
        "\(adjectives.randomElement()!) \(nouns.randomElement()!)"
    }
}
