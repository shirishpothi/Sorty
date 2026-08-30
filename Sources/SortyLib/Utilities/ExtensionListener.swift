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
    nonisolated(unsafe) private var notificationObserver: NSObjectProtocol?

    public init() {
        notificationObserver = ExtensionCommunication.setupNotificationObserver { @MainActor [weak self] url in
            self?.incomingURL = url
        }

        if let existingURL = ExtensionCommunication.receiveFromExtension() {
            incomingURL = existingURL
        }
    }

    deinit {
        if let notificationObserver {
            ExtensionCommunication.removeNotificationObserver(notificationObserver)
        }
    }
}
