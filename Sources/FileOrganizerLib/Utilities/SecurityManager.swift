//
//  SecurityManager.swift
//  FileOrganizer
//
//  Manages biometric authentication and secure access to sensitive features.
//  Enhanced with session timeout and password fallback for Learnings feature.
//

import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
public class SecurityManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published public var isUnlocked: Bool = false
    @Published public var biometryType: LABiometryType = .none
    @Published public var error: String?
    @Published public var authenticationMethod: AuthenticationMethod = .none
    
    // MARK: - Session Management
    
    /// Session timeout duration (5 minutes)
    public var sessionTimeoutInterval: TimeInterval = 300
    
    private var lastAuthenticationTime: Date?
    private var sessionTimer: Timer?
    
    /// Whether the session has timed out
    public var isSessionExpired: Bool {
        guard let lastAuth = lastAuthenticationTime else { return true }
        return Date().timeIntervalSince(lastAuth) > sessionTimeoutInterval
    }
    
    // MARK: - Init
    
    public init() {
        checkBiometryType()
    }
    
    // MARK: - Authentication Methods
    
    public enum AuthenticationMethod: String, CaseIterable {
        case none = "None"
        case biometric = "Biometric"
        case password = "Password"
    }
    
    /// Checks what kind of biometry is available on the device
    public func checkBiometryType() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometryType = context.biometryType
        } else {
            biometryType = .none
            print("Biometry not available: \(error?.localizedDescription ?? "Unknown error")")
        }
    }
    
    /// Display name for the available biometry type
    public var biometryDisplayName: String {
        switch biometryType {
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Password"
        @unknown default:
            return "Biometric"
        }
    }
    
    /// Requests authentication specifically for Learnings access
    /// Uses biometrics if available, falls back to system password
    public func authenticateForLearningsAccess() async {
        // Check if session is still valid
        if !isSessionExpired && isUnlocked {
            refreshSession()
            return
        }
        
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        
        let reason = "Authenticate to access your personal organization learnings."
        
        // Try biometrics first, then fall back to password
        let policy: LAPolicy = biometryType != .none 
            ? .deviceOwnerAuthenticationWithBiometrics 
            : .deviceOwnerAuthentication
        
        var authError: NSError?
        guard context.canEvaluatePolicy(policy, error: &authError) else {
            // If biometrics not available, try password-only
            await authenticateWithPassword(reason: reason)
            return
        }
        
        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            if success {
                self.isUnlocked = true
                self.error = nil
                self.authenticationMethod = biometryType != .none ? .biometric : .password
                self.lastAuthenticationTime = Date()
                startSessionTimer()
                print("SecurityManager: Authentication successful via \(authenticationMethod.rawValue)")
            }
        } catch let error as LAError {
            switch error.code {
            case .userFallback:
                // User chose password fallback
                await authenticateWithPassword(reason: reason)
            case .userCancel:
                self.error = "Authentication cancelled"
                self.isUnlocked = false
            default:
                self.error = "Authentication failed: \(error.localizedDescription)"
                self.isUnlocked = false
            }
        } catch {
            self.error = "Authentication failed: \(error.localizedDescription)"
            self.isUnlocked = false
        }
    }
    
    /// Authenticate using system password (fallback for non-biometric devices)
    private func authenticateWithPassword(reason: String) async {
        let context = LAContext()
        
        // Use deviceOwnerAuthentication which allows password
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            self.error = "No authentication method available on this device."
            self.isUnlocked = false
            return
        }
        
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                self.isUnlocked = true
                self.error = nil
                self.authenticationMethod = .password
                self.lastAuthenticationTime = Date()
                startSessionTimer()
                print("SecurityManager: Authentication successful via password")
            }
        } catch {
            self.error = "Password authentication failed: \(error.localizedDescription)"
            self.isUnlocked = false
        }
    }
    
    /// Legacy authenticate method - uses biometrics only
    public func authenticate() async {
        await authenticateForLearningsAccess()
    }
    
    /// Locks the secure features again
    public func lock() {
        isUnlocked = false
        lastAuthenticationTime = nil
        authenticationMethod = .none
        stopSessionTimer()
        print("SecurityManager: Session locked")
    }
    
    /// Refresh the session timer (call on user activity)
    public func refreshSession() {
        lastAuthenticationTime = Date()
    }
    
    // MARK: - Session Timer
    
    private func startSessionTimer() {
        stopSessionTimer()
        
        // Check session every 30 seconds
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSessionTimeout()
            }
        }
    }
    
    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }
    
    private func checkSessionTimeout() {
        if isSessionExpired && isUnlocked {
            lock()
            print("SecurityManager: Session timed out after \(sessionTimeoutInterval) seconds")
        }
    }
}
