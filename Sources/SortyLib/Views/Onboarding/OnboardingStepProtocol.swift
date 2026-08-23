//
//  OnboardingStepProtocol.swift
//  Sorty
//
//  Protocol for onboarding step views
//

import SwiftUI

public struct OnboardingStepValidationResult: Equatable, Sendable {
    public let canAdvance: Bool
    public let message: String?

    public init(canAdvance: Bool, message: String? = nil) {
        self.canAdvance = canAdvance
        self.message = message
    }

    public static let valid = OnboardingStepValidationResult(canAdvance: true)

    public static func blocked(_ message: String) -> OnboardingStepValidationResult {
        OnboardingStepValidationResult(canAdvance: false, message: message)
    }
}

public struct OnboardingStepValidationContext: Equatable, Sendable {
    public let providerSetupStatus: ProviderSetupStatus
    public let hasRequiredPermissions: Bool

    public init(
        providerSetupStatus: ProviderSetupStatus,
        hasRequiredPermissions: Bool
    ) {
        self.providerSetupStatus = providerSetupStatus
        self.hasRequiredPermissions = hasRequiredPermissions
    }
}
