//
//  EnvironmentValues.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.10.
//

import SwiftUI

struct CapturedURLKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

struct CaptureURLKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var capturedURL: URL? {
        get { self[CapturedURLKey.self] }
        set { self[CapturedURLKey.self] = newValue }
    }
    
    var captureURL: () -> Void {
        get { self[CaptureURLKey.self] }
        set { self[CaptureURLKey.self] = newValue }
    }
}
