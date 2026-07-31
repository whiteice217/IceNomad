//
//  RNodeBLEManager.swift
//  IceNomad
//
//  CoreBluetooth transport for a real RNode device, using the Nordic
//  UART Service RNode firmware actually exposes over BLE — confirmed
//  against the firmware source (BLESerial.h in
//  github.com/markqvist/RNode_Firmware): service
//  6e400001-b5a3-f393-e0a9-e50e24dcca9e, with the device's "RX"
//  characteristic (...0002) being what WE write to (send data to the
//  radio) and its "TX" characteristic (...0003) being what WE subscribe
//  to (receive data from the radio) — named from the device's own
//  point of view, so they're swapped relative to our side.
//
//  One shared instance handles both scanning (for pairing) and the
//  single active connection (for actually running an interface), since
//  CoreBluetooth only allows one CBCentralManager to usefully own BLE
//  state at a time. CBCentralManagerDelegate/CBPeripheralDelegate
//  conformance lives on a private NSObject proxy rather than on this
//  class directly, so the public, @Published-carrying ObservableObject
//  doesn't itself need to inherit NSObject.
//

import Foundation
import Combine
import CoreBluetooth


struct DiscoveredRNode: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}


final class RNodeBLEManager: ObservableObject {

    static let shared = RNodeBLEManager()

    fileprivate static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    fileprivate static let rxCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // we write here
    fileprivate static let txCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // we subscribe here

    @Published fileprivate(set) var isScanning = false
    @Published fileprivate(set) var discovered: [DiscoveredRNode] = []
    @Published fileprivate(set) var isBluetoothReady = false

    /// Fires with raw bytes as they arrive from the connected peripheral's
    /// TX characteristic — the caller (RNodeInterface) runs these through
    /// RNodeKISS.FrameParser itself, since this class only knows Bluetooth.
    var onReceive: ((Data) -> Void)?
    var onConnectionStateChanged: ((Bool) -> Void)?

    private var central: CBCentralManager!
    private lazy var delegateProxy = DelegateProxy(owner: self)

    fileprivate var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    fileprivate var connectedPeripheral: CBPeripheral?
    fileprivate var rxCharacteristic: CBCharacteristic? // write target
    fileprivate var txCharacteristic: CBCharacteristic? // notify source

    private var pendingConnectIdentifier: UUID?
    fileprivate var maxWriteLength = 20 // conservative default until negotiated


    private init() {
        central = CBCentralManager(delegate: delegateProxy, queue: .main)
    }


    // MARK: - Scanning (pairing UI)

    func startScan() {

        discovered.removeAll()
        discoveredPeripherals.removeAll()

        guard central.state == .poweredOn else {
            return
        }

        isScanning = true
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }


    func stopScan() {

        isScanning = false
        central.stopScan()
    }


    // MARK: - Connecting (running an interface)

    /// Connects to a specific, previously-paired device by its
    /// CBPeripheral identifier (persisted in RNodeConfig). If it isn't
    /// already known to CoreBluetooth (app relaunch), we ask the system
    /// for it directly rather than needing a fresh scan.
    func connect(identifier: UUID) {

        pendingConnectIdentifier = identifier

        if let peripheral = discoveredPeripherals[identifier] {
            central.connect(peripheral, options: nil)
            return
        }

        let known = central.retrievePeripherals(withIdentifiers: [identifier])

        guard let peripheral = known.first else {
            onConnectionStateChanged?(false)
            return
        }

        discoveredPeripherals[identifier] = peripheral
        peripheral.delegate = delegateProxy
        central.connect(peripheral, options: nil)
    }


    func disconnect() {

        pendingConnectIdentifier = nil

        if let connectedPeripheral {
            central.cancelPeripheralConnection(connectedPeripheral)
        }

        connectedPeripheral = nil
        rxCharacteristic = nil
        txCharacteristic = nil
    }


    // MARK: - Sending

    func send(_ data: Data) {

        guard let peripheral = connectedPeripheral, let rxCharacteristic else {
            return
        }

        // BLE writes are capped by the negotiated MTU — chunk anything
        // larger rather than silently truncating or failing.
        var offset = data.startIndex

        while offset < data.endIndex {

            let end = data.index(offset, offsetBy: maxWriteLength, limitedBy: data.endIndex) ?? data.endIndex
            let chunk = Data(data[offset..<end])

            peripheral.writeValue(chunk, for: rxCharacteristic, type: .withoutResponse)

            offset = end
        }
    }
}


/// Forwards CoreBluetooth's Objective-C delegate callbacks to the owning
/// RNodeBLEManager — kept separate so RNodeBLEManager itself can stay a
/// plain (non-NSObject) ObservableObject.
private final class DelegateProxy: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    unowned let owner: RNodeBLEManager

    init(owner: RNodeBLEManager) {
        self.owner = owner
    }


    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

        owner.isBluetoothReady = central.state == .poweredOn

        if central.state != .poweredOn {
            owner.isScanning = false
        }
    }


    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {

        owner.discoveredPeripherals[peripheral.identifier] = peripheral

        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown RNode"

        if let index = owner.discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
            owner.discovered[index] = DiscoveredRNode(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        } else {
            owner.discovered.append(DiscoveredRNode(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
        }
    }


    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {

        owner.connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([RNodeBLEManager.serviceUUID])
    }


    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {

        owner.connectedPeripheral = nil
        owner.onConnectionStateChanged?(false)
    }


    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {

        owner.connectedPeripheral = nil
        owner.rxCharacteristic = nil
        owner.txCharacteristic = nil
        owner.onConnectionStateChanged?(false)
    }


    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {

        guard let service = peripheral.services?.first(where: { $0.uuid == RNodeBLEManager.serviceUUID }) else {
            owner.onConnectionStateChanged?(false)
            return
        }

        peripheral.discoverCharacteristics([RNodeBLEManager.rxCharacteristicUUID, RNodeBLEManager.txCharacteristicUUID], for: service)
    }


    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {

        guard let characteristics = service.characteristics else {
            owner.onConnectionStateChanged?(false)
            return
        }

        for characteristic in characteristics {

            if characteristic.uuid == RNodeBLEManager.rxCharacteristicUUID {
                owner.rxCharacteristic = characteristic
            }

            if characteristic.uuid == RNodeBLEManager.txCharacteristicUUID {
                owner.txCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        owner.maxWriteLength = peripheral.maximumWriteValueLength(for: .withoutResponse)

        if owner.rxCharacteristic != nil, owner.txCharacteristic != nil {
            owner.onConnectionStateChanged?(true)
        }
    }


    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {

        guard characteristic.uuid == RNodeBLEManager.txCharacteristicUUID, let data = characteristic.value else {
            return
        }

        owner.onReceive?(data)
    }
}
