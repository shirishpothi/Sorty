//
//  DeeplinkHandler.swift
//  FileOrganizer
//
//  Handles URL scheme deeplinks for app-wide navigation
//

import Foundation
import SwiftUI

// MARK: - Deeplink Types

public enum DeeplinkDestination: Equatable {
    case organize(path: String?)
    case duplicates(path: String?)
    case learnings(project: String?)
    case settings
    case help(section: String?)
    case history
    case health
}

// MARK: - Deeplink Handler

@MainActor
public class DeeplinkHandler: ObservableObject {
    public static let shared = DeeplinkHandler()
    
    @Published public var pendingDestination: DeeplinkDestination?
    
    private init() {}
    
    /// Parse a URL into a deeplink destination
    /// URL scheme: fileorganizer://
    /// Examples:
    ///   fileorganizer://organize?path=/Users/foo/Downloads
    ///   fileorganizer://duplicates
    ///   fileorganizer://learnings?project=Photos
    ///   fileorganizer://settings
    ///   fileorganizer://help?section=personas
    public func handle(url: URL) {
        guard url.scheme == "fileorganizer" else { return }
        
        let host = url.host ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        
        func queryValue(for name: String) -> String? {
            queryItems.first { $0.name == name }?.value
        }
        
        switch host {
        case "organize":
            pendingDestination = .organize(path: queryValue(for: "path"))
            
        case "duplicates":
            pendingDestination = .duplicates(path: queryValue(for: "path"))
            
        case "learnings":
            pendingDestination = .learnings(project: queryValue(for: "project"))
            
        case "settings":
            pendingDestination = .settings
            
        case "help":
            pendingDestination = .help(section: queryValue(for: "section"))
            
        case "history":
            pendingDestination = .history
            
        case "health":
            pendingDestination = .health
            
        default:
            DebugLogger.log("Unknown deeplink: \(url)")
        }
    }
    
    /// Clear pending destination after navigation
    public func clearPending() {
        pendingDestination = nil
    }
    
    /// Generate a deeplink URL
    public static func url(for destination: DeeplinkDestination) -> URL? {
        var components = URLComponents()
        components.scheme = "fileorganizer"
        
        switch destination {
        case .organize(let path):
            components.host = "organize"
            if let path = path {
                components.queryItems = [URLQueryItem(name: "path", value: path)]
            }
            
        case .duplicates(let path):
            components.host = "duplicates"
            if let path = path {
                components.queryItems = [URLQueryItem(name: "path", value: path)]
            }
            
        case .learnings(let project):
            components.host = "learnings"
            if let project = project {
                components.queryItems = [URLQueryItem(name: "project", value: project)]
            }
            
        case .settings:
            components.host = "settings"
            
        case .help(let section):
            components.host = "help"
            if let section = section {
                components.queryItems = [URLQueryItem(name: "section", value: section)]
            }
            
        case .history:
            components.host = "history"
            
        case .health:
            components.host = "health"
        }
        
        return components.url
    }
}
