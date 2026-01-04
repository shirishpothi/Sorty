//
//  LearningsConsentManager.swift
//  FileOrganizer
//
//  Manages user consent for the Learnings feature.
//  Ensures strict opt-in before any data collection.
//

import Foundation
import Combine
import SwiftUI

/// Manages user consent state for the Learnings feature
@MainActor
public class LearningsConsentManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published public private(set) var hasConsented: Bool = false
    @Published public private(set) var consentDate: Date?
    @Published public private(set) var hasCompletedInitialSetup: Bool = false
    
    // MARK: - Private
    
    private let consentKey = "learnings_consent_granted"
    private let consentDateKey = "learnings_consent_date"
    private let setupCompleteKey = "learnings_initial_setup_complete"
    
    private var learningsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FileOrganizer/Learnings")
    }
    
    // MARK: - Init
    
    public init() {
        loadConsentState()
    }
    
    // MARK: - Public API
    
    /// Grant consent with timestamp
    public func grantConsent() {
        let now = Date()
        hasConsented = true
        consentDate = now
        
        UserDefaults.standard.set(true, forKey: consentKey)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: consentDateKey)
        
        print("LearningsConsentManager: Consent granted at \(now)")
    }
    
    /// Revoke consent (stops data collection but keeps existing data)
    public func withdrawConsent() {
        hasConsented = false
        
        UserDefaults.standard.set(false, forKey: consentKey)
        
        print("LearningsConsentManager: Consent withdrawn")
    }
    
    /// Mark initial setup as complete (triggers Touch ID requirement)
    public func completeInitialSetup() {
        hasCompletedInitialSetup = true
        UserDefaults.standard.set(true, forKey: setupCompleteKey)
        
        print("LearningsConsentManager: Initial setup complete, Touch ID will be required")
    }
    
    /// Reset initial setup (for testing or re-onboarding)
    public func resetInitialSetup() {
        hasCompletedInitialSetup = false
        UserDefaults.standard.set(false, forKey: setupCompleteKey)
    }
    
    /// Delete ALL user learning data securely
    public func deleteAllData() async throws {
        let fm = FileManager.default
        
        // Delete .learning files
        if fm.fileExists(atPath: learningsDirectory.path) {
            let files = try fm.contentsOfDirectory(at: learningsDirectory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "learning" {
                try fm.removeItem(at: file)
                print("LearningsConsentManager: Deleted \(file.lastPathComponent)")
            }
        }
        
        // Delete encryption key from Keychain
        _ = KeychainManager.delete(key: "learnings_encryption_key")
        
        // Reset consent state
        withdrawConsent()
        resetInitialSetup()
        consentDate = nil
        
        UserDefaults.standard.removeObject(forKey: consentDateKey)
        
        print("LearningsConsentManager: All data deleted successfully")
    }
    
    /// Check if data collection is allowed
    public var canCollectData: Bool {
        return hasConsented
    }
    
    // MARK: - Private
    
    private func loadConsentState() {
        hasConsented = UserDefaults.standard.bool(forKey: consentKey)
        hasCompletedInitialSetup = UserDefaults.standard.bool(forKey: setupCompleteKey)
        
        if let timestamp = UserDefaults.standard.object(forKey: consentDateKey) as? TimeInterval {
            consentDate = Date(timeIntervalSince1970: timestamp)
        }
    }
}
