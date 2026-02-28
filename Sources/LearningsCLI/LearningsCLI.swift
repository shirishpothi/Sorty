//
//  main.swift
//  LearningsCLI
//
//  CLI tool for The Learnings feature - manage profile, view status, and export data
//  Enhanced with comprehensive commands and better output formatting
//

import Foundation
import SortyLib

@main
@MainActor
struct LearningsCLI {
    static func main() async {
        let args = CommandLine.arguments
        
        guard args.count > 1 else {
            printUsage()
            exit(0)
        }
        
        let command = args[1]
        let manager = LearningsManager()
        
        switch command {
        case "--status", "status":
            await printStatus(manager: manager)
            
        case "--stats", "stats":
            await printDetailedStats(manager: manager)
            
        case "--export", "export":
            if args.count > 3 {
                print("Too many arguments for export. Usage: learnings export <json|summary>")
                exit(1)
            }
            let format = args.count > 2 ? args[2].lowercased() : "json"
            guard ["json", "summary"].contains(format) else {
                print("Invalid export format: \(format)")
                print("Usage: learnings export <json|summary>")
                exit(1)
            }
            await exportProfile(manager: manager, format: format)
            
        case "--clear", "clear":
            await clearData(manager: manager)
            
        case "--withdraw", "withdraw":
            await withdrawConsent(manager: manager)
            
        case "--info", "info":
            printInfo()
            
        case "--help", "-h", "help":
            printUsage()
            
        default:
            print("Unknown command: \(command)")
            printUsage()
            exit(1)
        }
        
        exit(0)
    }
    
    static func printUsage() {
        print("""
        \u{001B}[1mLearnings CLI\u{001B}[0m - Manage your organization learning profile
        
        \u{001B}[1mUSAGE:\u{001B}[0m
          learnings <command> [options]
        
        \u{001B}[1mCOMMANDS:\u{001B}[0m
          status      Show current learning status and basic stats
          stats       Show detailed statistics and learned patterns
          export      Export profile data (format: json|summary)
          clear       Delete all learning data (requires confirmation)
          withdraw    Pause learning without deleting data
          info        Show system information
          help        Show this help message
        
        \u{001B}[1mEXAMPLES:\u{001B}[0m
          learnings status
          learnings stats
          learnings export json
          learnings clear
        
        \u{001B}[1mNOTES:\u{001B}[0m
          - Full profile access requires biometric authentication in the main app
          - Some commands show limited info when accessed via CLI
          - Use 'sorty learnings' to open the Learnings dashboard
        """)
    }
    
    static func printStatus(manager: LearningsManager) async {
        print("\n\u{001B}[1m═══════════════════════════════════\u{001B}[0m")
        print("\u{001B}[1m       THE LEARNINGS - STATUS       \u{001B}[0m")
        print("\u{001B}[1m═══════════════════════════════════\u{001B}[0m\n")
        
        let setupComplete = !manager.requiresInitialSetup
        let consentGranted = manager.consentManager.hasConsented
        
        // Status indicators
        if setupComplete && consentGranted {
            print("  ✅ Status: \u{001B}[32mActive\u{001B}[0m")
        } else if setupComplete && !consentGranted {
            print("  ⏸️  Status: \u{001B}[33mPaused\u{001B}[0m (consent withdrawn)")
        } else {
            print("  ⚠️  Status: \u{001B}[33mNot Set Up\u{001B}[0m")
        }
        
        print("  🔒 Authentication: Required (Touch ID / Passcode)")
        print("  📁 Storage: Encrypted (.learning file)")
        
        if let consentDate = manager.consentManager.consentDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            print("  📅 Since: \(formatter.string(from: consentDate))")
        }
        
        print("\n  \u{001B}[2mNote: Use the main app for full access.\u{001B}[0m\n")
    }
    
    static func printDetailedStats(manager: LearningsManager) async {
        print("\n\u{001B}[1m═══════════════════════════════════\u{001B}[0m")
        print("\u{001B}[1m     THE LEARNINGS - STATISTICS     \u{001B}[0m")
        print("\u{001B}[1m═══════════════════════════════════\u{001B}[0m\n")
        
        // Try to read profile (may fail without biometric auth)
        print("  \u{001B}[2mNote: Detailed stats require authentication in the main app.\u{001B}[0m")
        print("  \u{001B}[2mCLI shows file-level information only.\u{001B}[0m\n")
        
        // Check if profile file exists
        if LearningsFileManager.profileExists {
            print("  📊 Profile: \u{001B}[32mExists\u{001B}[0m")
            print("  🔐 Encryption: \u{001B}[32mEnabled\u{001B}[0m")
        } else {
            print("  📊 Profile: \u{001B}[33mNot Created\u{001B}[0m")
        }
        
        print("\n  \u{001B}[1mTo view detailed stats:\u{001B}[0m")
        print("    1. Open Sorty")
        print("    2. Navigate to The Learnings (⇧⌘L)")
        print("    3. Authenticate with Touch ID / Passcode")
        print("")
    }
    
    static func exportProfile(manager: LearningsManager, format: String) async {
        print("\n\u{001B}[1mExport Learning Profile\u{001B}[0m\n")
        
        if !LearningsFileManager.profileExists {
            print("❌ No profile found. Nothing to export.")
            return
        }
        
        print("⚠️  For security, full profile export is only available in the main app.")
        print("")
        print("To export your learning data:")
        print("  1. Open Sorty")
        print("  2. Navigate to The Learnings (⇧⌘L)")
        print("  3. Authenticate and use the export function")
        print("")
        
        if format == "summary" {
            print("\u{001B}[2mSummary mode would show anonymized statistics.\u{001B}[0m")
        }
    }
    
    static func clearData(manager: LearningsManager) async {
        print("\n\u{001B}[1;31m⚠️  DELETE ALL LEARNING DATA\u{001B}[0m\n")
        print("This will permanently delete:")
        print("  • All learned preferences")
        print("  • Honing answers")
        print("  • Correction history")
        print("  • Inferred rules")
        print("")
        print("This action \u{001B}[1mCANNOT\u{001B}[0m be undone.")
        print("")
        print("Are you sure? Type 'DELETE' to confirm: ", terminator: "")
        
        guard let input = readLine(), input == "DELETE" else {
            print("\n✅ Aborted. No data was deleted.")
            return
        }
        
        print("\nDeleting...")
        
        do {
            try LearningsFileManager.secureDelete()
            print("✅ All learning data has been securely deleted.")
        } catch {
            print("❌ Failed to delete: \(error.localizedDescription)")
        }
    }
    
    static func withdrawConsent(manager: LearningsManager) async {
        print("\n\u{001B}[1mWithdraw Consent\u{001B}[0m\n")
        print("This will:")
        print("  • Stop learning from your behavior")
        print("  • Keep existing data (can be deleted separately)")
        print("  • Allow re-enabling later")
        print("")
        print("Proceed? (y/n): ", terminator: "")
        
        guard let input = readLine(), input.lowercased() == "y" else {
            print("\nAborted.")
            return
        }
        
        await manager.withdrawConsent()
        print("\n✅ Learning paused. Your existing data is preserved.")
        print("   Re-enable in the Learnings dashboard.")
    }
    
    static func printInfo() {
        let buildInfo = runtimeBuildInfo()
        let storagePath = LearningsFileManager.storageDirectoryPath
        let profilePath = "\(storagePath)/\(NSUserName()).learning"
        
        print("\n\u{001B}[1m═══════════════════════════════════\u{001B}[0m")
        print("\u{001B}[1m     THE LEARNINGS - SYSTEM INFO    \u{001B}[0m")
        print("\u{001B}[1m═══════════════════════════════════\u{001B}[0m\n")
        
        print("  📦 Version: \(buildInfo.version) (\(buildInfo.build))")
        print("  🔐 Security: AES-256 + Keychain")
        print("  🔑 Auth: Touch ID / Face ID / Passcode")
        print("  ⏱️  Session Timeout: 5 minutes")
        print("  💾 Storage: \(storagePath)")
        print("  📁 Profile Path: \(profilePath)")
        print("  📄 File Format: .learning (encrypted JSON)")
        print("")
        print("  \u{001B}[1mPrivacy:\u{001B}[0m")
        print("    • All data stored locally")
        print("    • Never sent to external servers")
        print("    • Only used to improve AI suggestions")
        print("    • Can be deleted at any time")
        print("")
    }
    
    static func runtimeBuildInfo() -> (version: String, build: String) {
        let info = Bundle.main.infoDictionary
        
        let version = (info?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (info?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let resolvedVersion = version.flatMap { $0.isEmpty ? nil : $0 } ?? "dev"
        let resolvedBuild = build.flatMap { $0.isEmpty ? nil : $0 } ?? "dev"
        
        return (version: resolvedVersion, build: resolvedBuild)
    }
}
