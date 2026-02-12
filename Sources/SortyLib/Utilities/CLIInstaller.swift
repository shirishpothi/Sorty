//
//  CLIInstaller.swift
//  Sorty
//
//  Manages installation of bundled CLI tools from the app bundle
//  Installs 'sorty' and 'learnings' commands to /usr/local/bin or user-local paths
//

import Foundation
import AppKit
import Combine

@MainActor
public final class CLIInstaller: ObservableObject {
    public static let shared = CLIInstaller()
    
    @Published public private(set) var sortyCLIInstalled = false
    @Published public private(set) var learningsCLIInstalled = false
    @Published public private(set) var isInstalling = false
    @Published public private(set) var lastError: String?
    
    private let fileManager = FileManager.default
    
    // Installation paths
    private let systemBinPath = "/usr/local/bin"
    private let userBinPath: String
    
    private init() {
        userBinPath = NSHomeDirectory() + "/.local/bin"
        refreshStatus()
    }
    
    // MARK: - Public API
    
    /// Refresh the installation status of CLI tools
    public func refreshStatus() {
        sortyCLIInstalled = checkSortyCLIInstalled()
        learningsCLIInstalled = checkLearningsCLIInstalled()
    }
    
    /// Install the 'sorty' CLI script
    public func installSortyCLI(useSystemPath: Bool = true) async -> (success: Bool, message: String) {
        isInstalling = true
        defer { 
            isInstalling = false
            refreshStatus()
        }
        
        guard let bundledScript = getBundledSortyScript() else {
            lastError = "Bundled sorty CLI not found in app bundle"
            return (false, lastError!)
        }
        
        let targetPath = useSystemPath ? "\(systemBinPath)/sorty" : "\(userBinPath)/sorty"
        
        do {
            // Create directory if needed (for user path)
            if !useSystemPath {
                try createUserBinDirectoryIfNeeded()
            }
            
            // For system path, we need admin privileges
            if useSystemPath {
                return await installWithAdminPrivileges(source: bundledScript, destination: targetPath, toolName: "sorty")
            } else {
                // User path - direct copy
                try copyAndMakeExecutable(source: bundledScript, destination: targetPath)
                return (true, "Installed sorty CLI to \(targetPath)")
            }
        } catch {
            lastError = error.localizedDescription
            return (false, "Failed to install sorty CLI: \(error.localizedDescription)")
        }
    }
    
    /// Install the 'learnings' CLI binary
    public func installLearningsCLI(useSystemPath: Bool = true) async -> (success: Bool, message: String) {
        isInstalling = true
        defer { 
            isInstalling = false
            refreshStatus()
        }
        
        guard let bundledBinary = getBundledLearningsBinary() else {
            lastError = "Bundled learnings CLI not found in app bundle"
            return (false, lastError!)
        }
        
        let targetPath = useSystemPath ? "\(systemBinPath)/learnings" : "\(userBinPath)/learnings"
        
        do {
            if !useSystemPath {
                try createUserBinDirectoryIfNeeded()
            }
            
            if useSystemPath {
                return await installWithAdminPrivileges(source: bundledBinary, destination: targetPath, toolName: "learnings")
            } else {
                try copyAndMakeExecutable(source: bundledBinary, destination: targetPath)
                return (true, "Installed learnings CLI to \(targetPath)")
            }
        } catch {
            lastError = error.localizedDescription
            return (false, "Failed to install learnings CLI: \(error.localizedDescription)")
        }
    }
    
    /// Install both CLI tools
    public func installAllCLIs(useSystemPath: Bool = true) async -> [(name: String, success: Bool, message: String)] {
        var results: [(name: String, success: Bool, message: String)] = []
        
        let sortyResult = await installSortyCLI(useSystemPath: useSystemPath)
        results.append(("sorty CLI", sortyResult.success, sortyResult.message))
        
        let learningsResult = await installLearningsCLI(useSystemPath: useSystemPath)
        results.append(("learnings CLI", learningsResult.success, learningsResult.message))
        
        return results
    }
    
    /// Uninstall CLI tools
    public func uninstallCLIs() async -> (success: Bool, message: String) {
        var removed: [String] = []
        var errors: [String] = []
        
        // Check both system and user paths
        let paths = [
            "\(systemBinPath)/sorty",
            "\(systemBinPath)/learnings",
            "\(userBinPath)/sorty",
            "\(userBinPath)/learnings"
        ]
        
        for path in paths {
            if fileManager.fileExists(atPath: path) {
                do {
                    if path.hasPrefix(systemBinPath) {
                        // Need admin for system path
                        let script = "do shell script \"rm -f '\(path)'\" with administrator privileges"
                        var error: NSDictionary?
                        if let appleScript = NSAppleScript(source: script) {
                            appleScript.executeAndReturnError(&error)
                            if error == nil {
                                removed.append(path)
                            } else {
                                errors.append("Failed to remove \(path)")
                            }
                        }
                    } else {
                        try fileManager.removeItem(atPath: path)
                        removed.append(path)
                    }
                } catch {
                    errors.append("Failed to remove \(path): \(error.localizedDescription)")
                }
            }
        }
        
        refreshStatus()
        
        if errors.isEmpty {
            return (true, removed.isEmpty ? "No CLI tools were installed" : "Removed: \(removed.joined(separator: ", "))")
        } else {
            return (false, errors.joined(separator: "; "))
        }
    }
    
    /// Get the path to the bundled CLI directory
    public var bundledCLIPath: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("CLI")
    }
    
    /// Check if CLI tools are bundled with the app
    public var hasBundledCLIs: Bool {
        getBundledSortyScript() != nil || getBundledLearningsBinary() != nil
    }
    
    // MARK: - Private Helpers
    
    private func getBundledSortyScript() -> String? {
        // Check in app bundle Resources/CLI/sorty
        if let resourcePath = Bundle.main.resourcePath {
            let path = (resourcePath as NSString).appendingPathComponent("CLI/sorty")
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    private func getBundledLearningsBinary() -> String? {
        // Check in app bundle Resources/CLI/learnings
        if let resourcePath = Bundle.main.resourcePath {
            let path = (resourcePath as NSString).appendingPathComponent("CLI/learnings")
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    private func checkSortyCLIInstalled() -> Bool {
        fileManager.fileExists(atPath: "\(systemBinPath)/sorty") ||
        fileManager.fileExists(atPath: "\(userBinPath)/sorty")
    }
    
    private func checkLearningsCLIInstalled() -> Bool {
        fileManager.fileExists(atPath: "\(systemBinPath)/learnings") ||
        fileManager.fileExists(atPath: "\(userBinPath)/learnings")
    }
    
    private func createUserBinDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: userBinPath) {
            try fileManager.createDirectory(atPath: userBinPath, withIntermediateDirectories: true)
        }
    }
    
    private func copyAndMakeExecutable(source: String, destination: String) throws {
        // Remove existing file if present
        if fileManager.fileExists(atPath: destination) {
            try fileManager.removeItem(atPath: destination)
        }
        
        // Copy file
        try fileManager.copyItem(atPath: source, toPath: destination)
        
        // Make executable
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)
    }
    
    private func installWithAdminPrivileges(source: String, destination: String, toolName: String) async -> (success: Bool, message: String) {
        // Use AppleScript to request admin privileges for installation
        let script = """
        do shell script "mkdir -p '\(systemBinPath)' && cp '\(source)' '\(destination)' && chmod 755 '\(destination)'" with administrator privileges
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                // Check if user cancelled
                if errorMessage.contains("User canceled") || errorMessage.contains("cancelled") {
                    return (false, "Installation cancelled by user")
                }
                return (false, "Failed to install \(toolName): \(errorMessage)")
            }
            
            return (true, "Installed \(toolName) CLI to \(destination)")
        }
        
        return (false, "Failed to create installation script")
    }
    
    /// Get shell configuration hint for adding user bin to PATH
    public var pathConfigurationHint: String {
        """
        To use CLI tools installed to ~/.local/bin, add this to your shell config:
        
        # For zsh (~/.zshrc):
        export PATH="$HOME/.local/bin:$PATH"
        
        # For bash (~/.bashrc or ~/.bash_profile):
        export PATH="$HOME/.local/bin:$PATH"
        
        Then restart your terminal or run: source ~/.zshrc
        """
    }
}
