//
//  ConnectionStorage.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation

class ConnectionStorage {

    static let shared = ConnectionStorage()

    private let key = "saved_connections"

    func save(_ connections: [Connection]) {

        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }


    func load() -> [Connection] {

        guard let data = UserDefaults.standard.data(forKey: key),
              let connections = try? JSONDecoder().decode([Connection].self, from: data)
        else {
            return []
        }

        return connections
    }
}
