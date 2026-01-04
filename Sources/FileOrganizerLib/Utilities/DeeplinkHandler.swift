//
//  DeeplinkHandler.swift
//  FileOrganizer
//
//  Handles URL scheme deeplinks for app-wide navigation
//

import Foundation
import Combine
import SwiftUI

// MARK: - Deeplink Types

public enum DeeplinkDestination: Equatable {
    case organize(path: String?, persona: String?, autostart: Bool)
    case duplicates(path: String?, autostart: Bool)
    case learnings(action: LearningsAction?, project: String?)
    case settings(section: String?)
    case help(section: String?)
    case history
    case health
    case persona(action: String?, prompt: String?, generate: Bool)
    case watched(action: String?, path: String?)
    case rules(action: String?, type: String?, pattern: String?)
    
    /// Actions specific to Learnings feature
    public enum LearningsAction: String, Equatable {
        case honing       // Start honing session
        case stats        // Show detailed statistics
        case withdraw     // Withdraw consent (pause learning)
        case export       // Export profile data
        case clear        // Clear all data
    }
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
            let path = queryValue(for: "path")
            let persona = queryValue(for: "persona")
            let autostart = queryValue(for: "autostart") == "true"
            pendingDestination = .organize(path: path, persona: persona, autostart: autostart)
            
        case "duplicates":
            let path = queryValue(for: "path")
            let autostart = queryValue(for: "autostart") == "true"
            pendingDestination = .duplicates(path: path, autostart: autostart)
            
        case "learnings":
            let actionStr = queryValue(for: "action")
            let action = actionStr.flatMap { DeeplinkDestination.LearningsAction(rawValue: $0) }
            pendingDestination = .learnings(action: action, project: queryValue(for: "project"))
            
        case "settings":
            pendingDestination = .settings(section: queryValue(for: "section"))
            
        case "help":
            pendingDestination = .help(section: queryValue(for: "section"))
            
        case "history":
            pendingDestination = .history
            
        case "health":
            pendingDestination = .health
            
        case "persona":
            let action = queryValue(for: "action")
            let prompt = queryValue(for: "prompt")
            let generate = queryValue(for: "generate") == "true"
            pendingDestination = .persona(action: action, prompt: prompt, generate: generate)
            
        case "watched":
            let action = queryValue(for: "action")
            let path = queryValue(for: "path")
            pendingDestination = .watched(action: action, path: path)
            
        case "rules":
            let action = queryValue(for: "action")
            let type = queryValue(for: "type")
            let pattern = queryValue(for: "pattern")
            pendingDestination = .rules(action: action, type: type, pattern: pattern)
            
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
        case .organize(let path, let persona, let autostart):
            components.host = "organize"
            var items: [URLQueryItem] = []
            if let path = path {
                items.append(URLQueryItem(name: "path", value: path))
            }
            if let persona = persona {
                items.append(URLQueryItem(name: "persona", value: persona))
            }
            if autostart {
                items.append(URLQueryItem(name: "autostart", value: "true"))
            }
            if !items.isEmpty { components.queryItems = items }
            
        case .duplicates(let path, let autostart):
            components.host = "duplicates"
            var items: [URLQueryItem] = []
            if let path = path {
                items.append(URLQueryItem(name: "path", value: path))
            }
            if autostart {
                items.append(URLQueryItem(name: "autostart", value: "true"))
            }
            if !items.isEmpty { components.queryItems = items }
            
        case .learnings(let action, let project):
            components.host = "learnings"
            var items: [URLQueryItem] = []
            if let action = action {
                items.append(URLQueryItem(name: "action", value: action.rawValue))
            }
            if let project = project {
                items.append(URLQueryItem(name: "project", value: project))
            }
            if !items.isEmpty { components.queryItems = items }
            
        case .settings(let section):
            components.host = "settings"
            if let section = section {
                components.queryItems = [URLQueryItem(name: "section", value: section)]
            }
            
        case .help(let section):
            components.host = "help"
            if let section = section {
                components.queryItems = [URLQueryItem(name: "section", value: section)]
            }
            
        case .history:
            components.host = "history"
            
        case .health:
            components.host = "health"
            
        case .persona(let action, let prompt, let generate):
            components.host = "persona"
            var items: [URLQueryItem] = []
            if let action = action {
                items.append(URLQueryItem(name: "action", value: action))
            }
            if let prompt = prompt {
                items.append(URLQueryItem(name: "prompt", value: prompt))
            }
            if generate {
                items.append(URLQueryItem(name: "generate", value: "true"))
            }
            if !items.isEmpty { components.queryItems = items }
            
        case .watched(let action, let path):
            components.host = "watched"
            var items: [URLQueryItem] = []
            if let action = action {
                items.append(URLQueryItem(name: "action", value: action))
            }
            if let path = path {
                items.append(URLQueryItem(name: "path", value: path))
            }
            if !items.isEmpty { components.queryItems = items }
            
        case .rules(let action, let type, let pattern):
            components.host = "rules"
            var items: [URLQueryItem] = []
            if let action = action {
                items.append(URLQueryItem(name: "action", value: action))
            }
            if let type = type {
                items.append(URLQueryItem(name: "type", value: type))
            }
            if let pattern = pattern {
                items.append(URLQueryItem(name: "pattern", value: pattern))
            }
            if !items.isEmpty { components.queryItems = items }
        }
        
        return components.url
    }
}
