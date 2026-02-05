//
//  OnboardingStepProtocol.swift
//  Sorty
//
//  Protocol for onboarding step views
//

import SwiftUI

/// Protocol that all onboarding step views should conform to
/// Provides a common interface for step views to integrate with the main onboarding container
public protocol OnboardingStepView: View {
    /// Optional callback when the step wants to advance to the next step
    var onAdvance: (() -> Void)? { get set }
    
    /// Optional callback when the step wants to go back to the previous step
    var onBack: (() -> Void)? { get set }
}

/// Default implementation for optional callbacks
public extension OnboardingStepView {
    var onAdvance: (() -> Void)? { get { nil } set {} }
    var onBack: (() -> Void)? { get { nil } set {} }
}
