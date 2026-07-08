//
//  InterfaceManager.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import Foundation
import Combine

class InterfaceManager: ObservableObject {
    
    @Published private(set) var interfaces: [ReticulumInterface] = []
    @Published var connectionStates: [String: Bool] = [:]
    
    @Published var receivedPacketCount: Int = 0
    
    
    // MARK: - Load Interfaces
    
    func loadInterfaces() {
        
        // Remove existing interfaces
        interfaces.removeAll()
        
        
        let connections = ConnectionStorage.shared.load()
        
        
        for connection in connections {
            
            switch connection.type {
                
                
            case .tcpClient:
                
                let tcp = TCPClient(
                    name: connection.name,
                    address: connection.address,
                    port: connection.port
                )
                
                
                // Receive TCP packets
                tcp.onReceive = { [weak self] data in
                    
                    DispatchQueue.main.async {
                        
                        self?.receivedPacketCount += 1
                        
                        print(
                            "TCP received:",
                            data.count,
                            "bytes"
                        )
                        
                        print(data as NSData)
                    }
                }
                
                
                tcp.onStatusChanged = { [weak self, weak tcp] connected in
                    
                    DispatchQueue.main.async {
                        
                        if let name = tcp?.name {
                            
                            self?.connectionStates[name] = connected
                            
                            print(
                                name,
                                "status changed:",
                                connected
                            )
                        }
                    }
                }
                
                interfaces.append(tcp)
                
                
                
            case .rNode:
                
                if let config = connection.rnodeConfig {
                    
                    let rnode = RNodeInterface(
                        config: config
                    )
                    
                    
                    // Receive RNode packets
                    rnode.onReceive = { [weak self] data in
                        
                        DispatchQueue.main.async {
                            
                            self?.receivedPacketCount += 1
                            
                            print(
                                "RNode received:",
                                data.count,
                                "bytes"
                            )
                        }
                    }
                    
                    
                    interfaces.append(rnode)
                }
            }
        }
        
        
        print("Loaded interfaces:", interfaces.count)
    }
    
    
    
    // MARK: - Start Interfaces
    
    func startAll() {
        
        for interface in interfaces {
            
            print("Starting interface:", interface.name)
            
            interface.start()
            
            
            print(
                interface.name,
                "connected:",
                interface.isConnected
            )
        }
    }
    
    
    // MARK: - Stop Interfaces

    func stopAll() {

        print("Stopping all interfaces...")
        
        for interface in interfaces {

            print("Stopping interface:", interface.name)

            interface.stop()
            
            print("Finished stopping:", interface.name)
        }
        
        print("Finished stopping all interfaces")
    }


    // MARK: - Restart Interfaces

    func restartAll() {

        print("Restarting interfaces")

        stopAll()

        loadInterfaces()

        startAll()
    }
}
