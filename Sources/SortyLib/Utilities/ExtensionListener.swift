//
//  ExtensionListener.swift
//  Sorty
//
//  Listens for Finder extension notifications
//

import Foundation
import SwiftUI
import Combine

@MainActor
public class ExtensionListener: ObservableObject {
    @Published public var incomingURL: URL?
    
    public init() {
        ExtensionCommunication.setupNotificationObserver { @MainActor [weak self] url in
            self?.incomingURL = url
        }
    }
}

