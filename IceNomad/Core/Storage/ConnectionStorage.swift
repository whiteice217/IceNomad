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


    /// The only non-UI way to add a connection — everywhere else (the
    /// Connections tab's own Save button) builds a `Connection` and
    /// calls save()/restartAll() inline in view code. Factored out here
    /// so the first-run setup wizard can do the exact same thing without
    /// duplicating that assembly logic.
    @discardableResult
    func addTCPClient(name: String, address: String, port: String) -> Connection {

        var connections = load()
        let connection = Connection(name: name, address: address, port: port, type: .tcpClient)
        connections.append(connection)
        save(connections)

        return connection
    }
}
