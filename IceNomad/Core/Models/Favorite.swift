//
//  Favorite.swift
//  IceNomad
//
//  A saved NomadNet page — a destination hash + path, optionally with a
//  custom label. Shown on the Browser's home screen so a page doesn't
//  need to be re-typed or re-discovered via announces every time.
//

import Foundation

struct Favorite: Identifiable, Codable, Equatable {

    var id: String { "\(destinationHashHex):\(path)" }

    let destinationHashHex: String
    let path: String
    var customLabel: String?
    var folder: String? = nil
    let dateAdded: Date
}
