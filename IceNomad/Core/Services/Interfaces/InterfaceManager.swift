//
//  InterfaceManager.swift
//  IceNomad
//

import Foundation
import Combine


class InterfaceManager: ObservableObject {
    
    
    // MARK: - Properties
    
    private let packetParser = PacketParser()
    
    @Published private(set) var interfaces: [ReticulumInterface] = []
    
    @Published var connectionStates: [String: Bool] = [:]
    
    @Published var receivedPacketCount: Int = 0
    
    
    // MARK: - Init
    
    init() {
        
        packetParser.onFrameReceived = { frame in
            
            DispatchQueue.main.async {
                
                PeerStore.shared.handle(frame: frame)
            }
        }
    }
    
    
    
    // MARK: - Load Interfaces
    
    func loadInterfaces() {
        
        interfaces.removeAll()
        
        print("Loading interfaces...")
        
        let connections = ConnectionStorage.shared.load()
        
        
        for connection in connections {
            
            switch connection.type {
                
                
            // MARK: TCP Client
                
            case .tcpClient:
                
                let tcp = TCPClient(
                    name: connection.name,
                    address: connection.address,
                    port: connection.port
                )
                
                
                tcp.onReceive = { [weak self] data in
                    
                    DispatchQueue.main.async {
                        
                        self?.receivedPacketCount += 1
                        
                        self?.packetParser.receive(data)
                    }
                }
                
                
                tcp.onStatusChanged = { [weak self] connected in
                    
                    DispatchQueue.main.async {
                        
                        self?.connectionStates[connection.name] = connected
                        
                        print(
                            connected ?
                            "🟢 \(connection.name) connected" :
                            "🔴 \(connection.name) disconnected"
                        )
                    }
                }
                
                
                interfaces.append(tcp)
                
                
                
            // MARK: RNode
                
            case .rNode:
                
                guard let config = connection.rnodeConfig else {
                    continue
                }
                
                
                let rnode = RNodeInterface(
                    config: config
                )
                
                
                rnode.onReceive = { [weak self] data in
                    
                    DispatchQueue.main.async {
                        
                        self?.receivedPacketCount += 1
                        
                        self?.packetParser.receive(data)
                    }
                }
                
                
                interfaces.append(rnode)
            }
        }
        
        
        print("Loaded interfaces:", interfaces.count)
    }
    
    
    
    // MARK: - Interface Control
    
    func startAll() {
        
        for interface in interfaces {
            
            print("Starting:", interface.name)
            
            interface.start()
        }
    }
    
    
    func stopAll() {
        
        for interface in interfaces {
            
            interface.stop()
        }
    }
    
    
    
    // MARK: - Restart
    
    func restartAll() {
        
        print("Restarting interfaces...")
        
        stopAll()
        
        loadInterfaces()
        
        startAll()
    }
}
