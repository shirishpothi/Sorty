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
    @Published public var incomingAction = "organize"
    nonisolated(unsafe) private var notificationObserver: NSObjectProtocol?

    public init() {
        notificationObserver = ExtensionCommunication.setupNotificationObserver { @MainActor [weak self] url, action in
            self?.incomingAction = action
            self?.incomingURL = url
        }

        if let pending = ExtensionCommunication.receiveFromExtension() {
            incomingAction = pending.action
            incomingURL = pending.url
        }
    }

    deinit {
        if let notificationObserver {
            ExtensionCommunication.removeNotificationObserver(notificationObserver)
        }
    }
}
