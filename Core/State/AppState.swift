//
//  AppState.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//

import SwiftUI
import Combine

enum AppPhase {
    case loading
    case ready
}

final class AppState: ObservableObject {
    @Published var phase: AppPhase = .loading
    
    func start() {
        // simulate network checks for now
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.phase = .ready
        }
    }
}
