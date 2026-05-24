//
//  FeatureFlags.swift
//  Sorty
//
//  Created on Sun Jan 25 2026
//

import Foundation

@MainActor
public enum FeatureFlags {
    /// Controls whether the Finder Integration section is visible in Settings and the Finder Integration view.
    ///
    /// Disabled by default. Enable via Terminal:
    /// ```
    /// defaults write com.sorty.app finderIntegrationEnabled -bool true
    /// ```
    /// Disable:
    /// ```
    /// defaults write com.sorty.app finderIntegrationEnabled -bool false
    /// ```
    public static var finderSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: "finderIntegrationEnabled")
    }

    /// Controls whether Sparkle checks the nightly update feed instead of the stable feed.
    ///
    /// Disabled by default. Enable via Terminal:
    /// ```
    /// defaults write com.sorty.app nightlyUpdatesEnabled -bool true
    /// ```
    /// Disable:
    /// ```
    /// defaults write com.sorty.app nightlyUpdatesEnabled -bool false
    /// ```
    public static var nightlyUpdatesEnabled: Bool {
        UserDefaults.standard.bool(forKey: SparkleUpdateFeed.nightlyUpdatesEnabledKey)
    }

    /// Controls privacy features like blurring sensitive handles and hiding API keys by default.
    ///
    /// Enabled by default. Disable via Terminal:
    /// ```
    /// defaults write com.sorty.app privacyModeEnabled -bool false
    /// ```
    /// Enable:
    /// ```
    /// defaults write com.sorty.app privacyModeEnabled -bool true
    /// ```
    public static var privacyModeEnabled: Bool {
        if UserDefaults.standard.object(forKey: "privacyModeEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "privacyModeEnabled")
    }

    /// Controls internet network blocking privacy mode.
    ///
    /// Disabled by default. Enable via Terminal:
    /// ```
    /// defaults write com.sorty.app internetPrivacyModeEnabled -bool true
    /// ```
    /// Disable:
    /// ```
    /// defaults write com.sorty.app internetPrivacyModeEnabled -bool false
    /// ```
    public static var internetPrivacyModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)
    }

    /// Controls whether Sorty requires authentication for sensitive actions such as
    /// deleting usage data, changing network privacy mode, and revealing secrets.
    ///
    /// Disabled by default. Enable via Terminal:
    /// ```
    /// defaults write com.sorty.app sensitiveActionAuthenticationEnabled -bool true
    /// ```
    /// Disable:
    /// ```
    /// defaults write com.sorty.app sensitiveActionAuthenticationEnabled -bool false
    /// ```
    public static var sensitiveActionAuthenticationEnabled: Bool {
        UserDefaults.standard.bool(forKey: "sensitiveActionAuthenticationEnabled")
    }

    /// Controls whether Finder file tagging is enabled during organization.
    /// Tags may not apply correctly in all macOS sandboxed environments.
    ///
    /// Disabled by default. Enable via Terminal:
    /// ```
    /// defaults write com.sorty.app fileTaggingEnabled -bool true
    /// ```
    /// Disable:
    /// ```
    /// defaults write com.sorty.app fileTaggingEnabled -bool false
    /// ```
    public static var fileTaggingEnabled: Bool {
        if UserDefaults.standard.object(forKey: "fileTaggingEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "fileTaggingEnabled")
    }

    /// Controls whether advanced/technical notification controls are shown in Settings.
    /// This keeps the default notifications UX focused on the most common user options.
    ///
    /// Disabled by default. Enable via Terminal:
    /// ```
    /// defaults write com.sorty.app advancedNotificationSettingsEnabled -bool true
    /// ```
    /// Disable:
    /// ```
    /// defaults write com.sorty.app advancedNotificationSettingsEnabled -bool false
    /// ```
    public static var advancedNotificationSettingsEnabled: Bool {
        if UserDefaults.standard.object(forKey: "advancedNotificationSettingsEnabled") == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: "advancedNotificationSettingsEnabled")
    }

    /// Controls whether the interactive demo is shown during onboarding.
    ///
    /// Disabled by default. Enable via Terminal:
    /// ```
    /// defaults write com.sorty.app featureDemoEnabled -bool true
    /// ```
    /// Disable:
    /// ```
    /// defaults write com.sorty.app featureDemoEnabled -bool false
    /// ```
    public static var featureDemoEnabled: Bool {
        if UserDefaults.standard.object(forKey: "featureDemoEnabled") == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: "featureDemoEnabled")
    }

    /// Controls whether subscription-based auth methods are available for supported AI providers.
    ///
    /// Enabled by default. Disable via Terminal:
    /// ```
    /// defaults write com.sorty.app subscriptionAuthEnabled -bool false
    /// ```
    /// Re-enable:
    /// ```
    /// defaults write com.sorty.app subscriptionAuthEnabled -bool true
    /// ```
    public static var subscriptionAuthEnabled: Bool {
        if UserDefaults.standard.object(forKey: "subscriptionAuthEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "subscriptionAuthEnabled")
    }

    /// Preview harness mode for rapid development iteration.
    /// When enabled, the app boots with minimal dependencies and mock services.
    ///
    /// Enable via environment variable (set by `make harness`):
    /// ```
    /// SORTY_HARNESS_MODE=1 open Sorty.app
    /// ```
    ///
    /// Target a specific view:
    /// ```
    /// SORTY_HARNESS_VIEW=settings SORTY_HARNESS_MODE=1 open Sorty.app
    /// ```
    public static var harnessMode: Bool {
        ProcessInfo.processInfo.environment["SORTY_HARNESS_MODE"] == "1"
    }

    /// The target view to show in harness mode.
    /// Supported values: "settings", "organize", "learnings", "history", "health"
    public static var harnessView: String? {
        ProcessInfo.processInfo.environment["SORTY_HARNESS_VIEW"]
    }
}
