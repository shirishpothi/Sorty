//
//  FeatureFlags.swift
//  Sorty
//
//  Created on Sun Jan 25 2026
//

import Foundation

@MainActor
public enum FeatureFlags {
    /// Legacy preference for Finder Integration.
    ///
    /// Finder Integration is a core app feature. The key remains for migration and
    /// older installs that may have written it, but new installs default to enabled.
    public static var finderSyncEnabled: Bool {
        if UserDefaults.standard.object(forKey: "finderIntegrationEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "finderIntegrationEnabled")
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

    /// Controls whether the recovered shader gallery is available from the Help menu.
    ///
    /// Hidden by default. Enable via Terminal:
    /// ```
    /// defaults write com.sorty.app.feature-flags shadersEnabled -bool true
    /// ```
    /// Hide it again:
    /// ```
    /// defaults write com.sorty.app.feature-flags shadersEnabled -bool false
    /// ```
    public static var shadersEnabled: Bool {
        if let override = UserDefaults(suiteName: "com.sorty.app.feature-flags")?
            .object(forKey: "shadersEnabled") as? Bool
        {
            return override
        }
        return UserDefaults.standard.bool(forKey: "shadersEnabled")
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

    /// Controls whether in-app links and buttons supporting the developer are shown.
    ///
    /// Shown by default. Hide them via Terminal:
    /// ```
    /// defaults -container com.sorty.app write com.sorty.app supportDeveloperEnabled -bool false
    /// ```
    /// Show them again:
    /// ```
    /// defaults -container com.sorty.app write com.sorty.app supportDeveloperEnabled -bool true
    /// ```
    public static var supportDeveloperEnabled: Bool {
        if UserDefaults.standard.object(forKey: "supportDeveloperEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "supportDeveloperEnabled")
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
