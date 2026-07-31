//
//  SystemMonitor.swift
//  IceNomad
//
//  Watches for the two OS-level signals iOS actually exposes for "this
//  device is struggling" without needing any special entitlement:
//  memory pressure (the same signal the OS uses to decide when to
//  start killing background apps) and thermal state (the standard
//  proxy for sustained high CPU/GPU usage — iOS throttles rather than
//  reporting raw CPU%, so thermal state is the signal apps are meant
//  to react to). Both log through Log.system so a real dropped-
//  connection or decode-failure investigation can check whether the
//  device was under resource pressure at the time.
//

import Foundation
import OSLog

final class SystemMonitor {

    static let shared = SystemMonitor()

    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var isObservingThermalState = false

    private init() {}


    func start() {

        guard memoryPressureSource == nil else {
            return
        }

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)

        source.setEventHandler { [weak source] in

            guard let event = source?.data else {
                return
            }

            if event.contains(.critical) {
                Log.system.fault("Memory pressure: CRITICAL — the OS may terminate this app soon")
            } else if event.contains(.warning) {
                Log.system.error("Memory pressure: warning")
            }
        }

        source.resume()
        memoryPressureSource = source

        guard !isObservingThermalState else {
            return
        }

        isObservingThermalState = true

        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            SystemMonitor.logThermalState()
        }
    }


    private static func logThermalState() {

        switch ProcessInfo.processInfo.thermalState {

        case .nominal:
            Log.system.notice("Thermal state back to nominal")

        case .fair:
            break // Normal under real load — not worth logging.

        case .serious:
            Log.system.error("Thermal state: serious — sustained high CPU/GPU usage, iOS is throttling")

        case .critical:
            Log.system.fault("Thermal state: critical — iOS is throttling aggressively")

        @unknown default:
            break
        }
    }
}
