//
//  OrientationObserver.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI
import UIKit
import Combine

final class OrientationObserver: ObservableObject {
    @Published var isLandscape: Bool = false
    
    init() {
        update()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(update),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }
    
    @objc func update() {
        let orientation = UIDevice.current.orientation
        
        // This avoids weird "face up / face down" states
        if orientation.isLandscape {
            isLandscape = true
        } else if orientation.isPortrait {
            isLandscape = false
        }
    }
}
