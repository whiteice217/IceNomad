//
//  Contact.swift
//  IceNomad
//
//  App-specific contact — deliberately separate from Apple's Contacts
//  framework (CNContact). Nothing here touches the system address book.
//

import Foundation

struct Contact: Identifiable, Codable, Equatable {

    var id: String { destinationHashHex }

    let destinationHashHex: String
    var customLabel: String?
    let dateAdded: Date
}
