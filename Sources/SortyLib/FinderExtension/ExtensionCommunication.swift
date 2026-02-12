//
//  ExtensionCommunication.swift
//  Sorty
//
//  Finder integration without code signing
//  Uses URL schemes, Services menu, and AppleScript for integration
//

import Foundation
import AppKit

public struct ExtensionCommunication {
    private static let appGroupIdentifier = "group.com.sorty.app"
    private static let directoryKey = "selectedDirectory"
    public static let notificationName = Notification.Name("SortyDirectorySelected")
    
    // MARK: - URL Scheme Handling
    
    /// Handle incoming URL schemes: sorty://organize?path=/path/to/folder
    public static func handleURL(_ url: URL) -> URL? {
        guard url.scheme == "sorty" else { return nil }
        
        switch url.host {
        case "organize":
            // sorty://organize?path=/path/to/folder
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let pathItem = components.queryItems?.first(where: { $0.name == "path" }),
               let path = pathItem.value?.removingPercentEncoding {
                return URL(fileURLWithPath: path)
            }
            
        case "scan":
            // sorty://scan?path=/path/to/folder
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let pathItem = components.queryItems?.first(where: { $0.name == "path" }),
               let path = pathItem.value?.removingPercentEncoding {
                return URL(fileURLWithPath: path)
            }
            
        case "open":
            // sorty://open?path=/path/to/folder
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let pathItem = components.queryItems?.first(where: { $0.name == "path" }),
               let path = pathItem.value?.removingPercentEncoding {
                return URL(fileURLWithPath: path)
            }
            
        default:
            // Legacy: sorty:///path/to/folder (path in URL path component)
            if !url.path.isEmpty && url.path != "/" {
                return URL(fileURLWithPath: url.path)
            }
        }
        
        return nil
    }
    
    /// Generate a URL scheme command for organizing a given path
    public static func urlForOrganizing(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "sorty"
        components.host = "organize"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }
    
    /// Generate a URL scheme command for scanning a given path
    public static func urlForScanning(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "sorty"
        components.host = "scan"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }
    
    // MARK: - App Group Communication (for sandboxed extensions)
    
    public static func sendDirectoryToApp(_ directoryURL: URL) {
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.set(directoryURL.path, forKey: directoryKey)
            sharedDefaults.synchronize()
        }
        
        let notificationCenter = DistributedNotificationCenter.default()
        notificationCenter.post(
            name: notificationName,
            object: nil,
            userInfo: ["path": directoryURL.path]
        )
    }
    
    public static func receiveFromExtension() -> URL? {
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           let path = sharedDefaults.string(forKey: directoryKey) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
    
    public static func setupNotificationObserver(handler: @escaping @Sendable @MainActor (URL) -> Void) {
        let notificationCenter = DistributedNotificationCenter.default()
        notificationCenter.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let path = userInfo["path"] as? String {
                let url = URL(fileURLWithPath: path)
                Task { @MainActor in
                    handler(url)
                }
            }
        }
    }
    
    // MARK: - Quick Action Installation
    
    /// Install the Quick Action workflow to ~/Library/Services
    public static func installQuickAction() -> (success: Bool, message: String) {
        let workflowName = "Organize with Sorty.workflow"
        
        // Create the workflow directory structure
        let servicesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services")
        let workflowDir = servicesDir.appendingPathComponent(workflowName)
        let contentsDir = workflowDir.appendingPathComponent("Contents")
        
        do {
            // Create directories
            try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
            
            // Create Info.plist
            let infoPlist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>NSServices</key>
                <array>
                    <dict>
                        <key>NSMenuItem</key>
                        <dict>
                            <key>default</key>
                            <string>Organize with Sorty</string>
                        </dict>
                        <key>NSMessage</key>
                        <string>runWorkflowAsService</string>
                        <key>NSSendFileTypes</key>
                        <array>
                            <string>public.folder</string>
                            <string>public.item</string>
                        </array>
                    </dict>
                </array>
            </dict>
            </plist>
            """
            try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
            
            // Create document.wflow (Automator workflow)
            let workflowPlist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>AMApplicationBuild</key>
                <string>523</string>
                <key>AMApplicationVersion</key>
                <string>2.10</string>
                <key>AMDocumentVersion</key>
                <string>2</string>
                <key>actions</key>
                <array>
                    <dict>
                        <key>action</key>
                        <dict>
                            <key>AMAccepts</key>
                            <dict>
                                <key>Container</key>
                                <string>List</string>
                                <key>Optional</key>
                                <true/>
                                <key>Types</key>
                                <array>
                                    <string>com.apple.cocoa.path</string>
                                    <string>com.apple.cocoa.url</string>
                                    <string>public.item</string>
                                    <string>public.folder</string>
                                </array>
                            </dict>
                            <key>AMActionVersion</key>
                            <string>1.0.2</string>
                            <key>AMApplication</key>
                            <array>
                                <string>Automator</string>
                            </array>
                            <key>AMCategory</key>
                            <string>AMCategoryUtilities</string>
                            <key>AMIconName</key>
                            <string>Run Script</string>
                            <key>AMName</key>
                            <string>Run Shell Script</string>
                            <key>AMParameters</key>
                            <dict>
                                <key>COMMAND_STRING</key>
                                <string>for f in "$@"; do if [[ "$f" == file://* ]]; then f=$(/usr/bin/python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))" "$f" 2>/dev/null || echo "$f" | sed 's|^file://||'); fi; if [ -f "$f" ]; then f="$(dirname "$f")"; fi; encoded=$(/usr/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$f" 2>/dev/null || printf '%s' "$f" | sed 's/ /%20/g; s/!/%21/g; s/#/%23/g; s/\\$/%24/g; s/&amp;/%26/g; s/(/%28/g; s/)/%29/g'); open "sorty://organize?path=$encoded"; done</string>
                                <key>CheckedForUserDefaultShell</key>
                                <true/>
                                <key>inputMethod</key>
                                <integer>1</integer>
                                <key>shell</key>
                                <string>/bin/zsh</string>
                                <key>source</key>
                                <string></string>
                            </dict>
                            <key>AMProvides</key>
                            <dict>
                                <key>Container</key>
                                <string>List</string>
                                <key>Types</key>
                                <array>
                                    <string>com.apple.cocoa.path</string>
                                </array>
                            </dict>
                            <key>AMRequiredResources</key>
                            <array/>
                            <key>ActionBundlePath</key>
                            <string>/System/Library/Automator/Run Shell Script.action</string>
                            <key>ActionName</key>
                            <string>Run Shell Script</string>
                            <key>ActionParameters</key>
                            <dict>
                                <key>COMMAND_STRING</key>
                                <string>for f in "$@"; do if [[ "$f" == file://* ]]; then f=$(/usr/bin/python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))" "$f" 2>/dev/null || echo "$f" | sed 's|^file://||'); fi; if [ -f "$f" ]; then f="$(dirname "$f")"; fi; encoded=$(/usr/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$f" 2>/dev/null || printf '%s' "$f" | sed 's/ /%20/g; s/!/%21/g; s/#/%23/g; s/\\$/%24/g; s/&amp;/%26/g; s/(/%28/g; s/)/%29/g'); open "sorty://organize?path=$encoded"; done</string>
                                <key>CheckedForUserDefaultShell</key>
                                <true/>
                                <key>inputMethod</key>
                                <integer>1</integer>
                                <key>shell</key>
                                <string>/bin/zsh</string>
                                <key>source</key>
                                <string></string>
                            </dict>
                            <key>BundleIdentifier</key>
                            <string>com.apple.RunShellScript</string>
                            <key>CFBundleVersion</key>
                            <string>1.0.2</string>
                            <key>CanShowSelectedItemsWhenRun</key>
                            <false/>
                            <key>CanShowWhenRun</key>
                            <true/>
                            <key>Category</key>
                            <array>
                                <string>AMCategoryUtilities</string>
                            </array>
                            <key>Class Name</key>
                            <string>RunShellScriptAction</string>
                            <key>InputUUID</key>
                            <string>3B7E9A4E-8F2C-4D1B-9A3E-5C6D7E8F9A0B</string>
                            <key>Keywords</key>
                            <array>
                                <string>Shell</string>
                                <string>Script</string>
                                <string>Command</string>
                                <string>Run</string>
                                <string>Unix</string>
                            </array>
                            <key>OutputUUID</key>
                            <string>4C8F0B5F-9A3D-5E2C-0B4F-6D7E8F9A0B1C</string>
                            <key>UUID</key>
                            <string>5D9A1C6A-0B4E-6F3D-1C5A-7E8F9A0B1C2D</string>
                            <key>UnlocalizedApplications</key>
                            <array>
                                <string>Automator</string>
                            </array>
                            <key>arguments</key>
                            <dict>
                                <key>0</key>
                                <dict>
                                    <key>default value</key>
                                    <integer>1</integer>
                                    <key>name</key>
                                    <string>inputMethod</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>0</string>
                                </dict>
                                <key>1</key>
                                <dict>
                                    <key>default value</key>
                                    <string></string>
                                    <key>name</key>
                                    <string>source</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>1</string>
                                </dict>
                                <key>2</key>
                                <dict>
                                    <key>default value</key>
                                    <false/>
                                    <key>name</key>
                                    <string>CheckedForUserDefaultShell</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>2</string>
                                </dict>
                                <key>3</key>
                                <dict>
                                    <key>default value</key>
                                    <string></string>
                                    <key>name</key>
                                    <string>COMMAND_STRING</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>3</string>
                                </dict>
                                <key>4</key>
                                <dict>
                                    <key>default value</key>
                                    <string>/bin/sh</string>
                                    <key>name</key>
                                    <string>shell</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>4</string>
                                </dict>
                            </dict>
                            <key>isViewVisible</key>
                            <integer>1</integer>
                            <key>location</key>
                            <string>309.000000:253.000000</string>
                            <key>nibPath</key>
                            <string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
                        </dict>
                        <key>isViewVisible</key>
                        <integer>1</integer>
                    </dict>
                </array>
                <key>connectors</key>
                <dict/>
                <key>workflowMetaData</key>
                <dict>
                    <key>serviceInputTypeIdentifier</key>
                    <string>com.apple.Automator.fileSystemObject</string>
                    <key>serviceApplicationPath</key>
                    <string>/System/Library/CoreServices/Finder.app</string>
                    <key>workflowTypeIdentifier</key>
                    <string>com.apple.Automator.servicesMenu</string>
                </dict>
            </dict>
            </plist>
            """
            try workflowPlist.write(to: contentsDir.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
            
            // Refresh services
            NSUpdateDynamicServices()
            
            return (true, "Quick Action installed! Right-click any folder in Finder to use 'Organize with Sorty'.")
            
        } catch {
            return (false, "Installation failed: \(error.localizedDescription)")
        }
    }
    
    /// Check if Quick Action is installed
    public static func isQuickActionInstalled() -> Bool {
        let workflowPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services/Organize with Sorty.workflow")
        return FileManager.default.fileExists(atPath: workflowPath.path)
    }
    
    // MARK: - Quick Scan Action Installation
    
    /// Install a "Scan with Sorty" Quick Action workflow to ~/Library/Services
    public static func installQuickScanAction() -> (success: Bool, message: String) {
        let workflowName = "Scan with Sorty.workflow"
        
        let servicesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services")
        let workflowDir = servicesDir.appendingPathComponent(workflowName)
        let contentsDir = workflowDir.appendingPathComponent("Contents")
        
        do {
            try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
            
            let infoPlist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>NSServices</key>
                <array>
                    <dict>
                        <key>NSMenuItem</key>
                        <dict>
                            <key>default</key>
                            <string>Scan with Sorty</string>
                        </dict>
                        <key>NSMessage</key>
                        <string>runWorkflowAsService</string>
                        <key>NSSendFileTypes</key>
                        <array>
                            <string>public.folder</string>
                            <string>public.item</string>
                        </array>
                    </dict>
                </array>
            </dict>
            </plist>
            """
            try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
            
            let shellCommand = """
            for f in "$@"; do if [[ "$f" == file://* ]]; then f=$(/usr/bin/python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))" "$f" 2>/dev/null || echo "$f" | sed 's|^file://||'); fi; if [ -f "$f" ]; then f="$(dirname "$f")"; fi; encoded=$(/usr/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$f" 2>/dev/null || printf '%s' "$f" | sed 's/ /%20/g; s/!/%21/g; s/#/%23/g; s/\\$/%24/g; s/&amp;/%26/g; s/(/%28/g; s/)/%29/g'); open "sorty://scan?path=$encoded"; done
            """
            
            let workflowPlist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>AMApplicationBuild</key>
                <string>523</string>
                <key>AMApplicationVersion</key>
                <string>2.10</string>
                <key>AMDocumentVersion</key>
                <string>2</string>
                <key>actions</key>
                <array>
                    <dict>
                        <key>action</key>
                        <dict>
                            <key>AMAccepts</key>
                            <dict>
                                <key>Container</key>
                                <string>List</string>
                                <key>Optional</key>
                                <true/>
                                <key>Types</key>
                                <array>
                                    <string>com.apple.cocoa.path</string>
                                    <string>com.apple.cocoa.url</string>
                                    <string>public.item</string>
                                    <string>public.folder</string>
                                </array>
                            </dict>
                            <key>AMActionVersion</key>
                            <string>1.0.2</string>
                            <key>AMApplication</key>
                            <array>
                                <string>Automator</string>
                            </array>
                            <key>AMCategory</key>
                            <string>AMCategoryUtilities</string>
                            <key>AMIconName</key>
                            <string>Run Script</string>
                            <key>AMName</key>
                            <string>Run Shell Script</string>
                            <key>AMParameters</key>
                            <dict>
                                <key>COMMAND_STRING</key>
                                <string>\(shellCommand)</string>
                                <key>CheckedForUserDefaultShell</key>
                                <true/>
                                <key>inputMethod</key>
                                <integer>1</integer>
                                <key>shell</key>
                                <string>/bin/zsh</string>
                                <key>source</key>
                                <string></string>
                            </dict>
                            <key>AMProvides</key>
                            <dict>
                                <key>Container</key>
                                <string>List</string>
                                <key>Types</key>
                                <array>
                                    <string>com.apple.cocoa.path</string>
                                </array>
                            </dict>
                            <key>AMRequiredResources</key>
                            <array/>
                            <key>ActionBundlePath</key>
                            <string>/System/Library/Automator/Run Shell Script.action</string>
                            <key>ActionName</key>
                            <string>Run Shell Script</string>
                            <key>ActionParameters</key>
                            <dict>
                                <key>COMMAND_STRING</key>
                                <string>\(shellCommand)</string>
                                <key>CheckedForUserDefaultShell</key>
                                <true/>
                                <key>inputMethod</key>
                                <integer>1</integer>
                                <key>shell</key>
                                <string>/bin/zsh</string>
                                <key>source</key>
                                <string></string>
                            </dict>
                            <key>BundleIdentifier</key>
                            <string>com.apple.RunShellScript</string>
                            <key>CFBundleVersion</key>
                            <string>1.0.2</string>
                            <key>CanShowSelectedItemsWhenRun</key>
                            <false/>
                            <key>CanShowWhenRun</key>
                            <true/>
                            <key>Category</key>
                            <array>
                                <string>AMCategoryUtilities</string>
                            </array>
                            <key>Class Name</key>
                            <string>RunShellScriptAction</string>
                            <key>InputUUID</key>
                            <string>6A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D</string>
                            <key>Keywords</key>
                            <array>
                                <string>Shell</string>
                                <string>Script</string>
                                <string>Command</string>
                                <string>Run</string>
                                <string>Unix</string>
                            </array>
                            <key>OutputUUID</key>
                            <string>7B2C3D4E-5F6A-7B8C-9D0E-1F2A3B4C5D6E</string>
                            <key>UUID</key>
                            <string>8C3D4E5F-6A7B-8C9D-0E1F-2A3B4C5D6E7F</string>
                            <key>UnlocalizedApplications</key>
                            <array>
                                <string>Automator</string>
                            </array>
                            <key>arguments</key>
                            <dict>
                                <key>0</key>
                                <dict>
                                    <key>default value</key>
                                    <integer>1</integer>
                                    <key>name</key>
                                    <string>inputMethod</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>0</string>
                                </dict>
                                <key>1</key>
                                <dict>
                                    <key>default value</key>
                                    <string></string>
                                    <key>name</key>
                                    <string>source</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>1</string>
                                </dict>
                                <key>2</key>
                                <dict>
                                    <key>default value</key>
                                    <false/>
                                    <key>name</key>
                                    <string>CheckedForUserDefaultShell</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>2</string>
                                </dict>
                                <key>3</key>
                                <dict>
                                    <key>default value</key>
                                    <string></string>
                                    <key>name</key>
                                    <string>COMMAND_STRING</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>3</string>
                                </dict>
                                <key>4</key>
                                <dict>
                                    <key>default value</key>
                                    <string>/bin/sh</string>
                                    <key>name</key>
                                    <string>shell</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>4</string>
                                </dict>
                            </dict>
                            <key>isViewVisible</key>
                            <integer>1</integer>
                            <key>location</key>
                            <string>309.000000:253.000000</string>
                            <key>nibPath</key>
                            <string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
                        </dict>
                        <key>isViewVisible</key>
                        <integer>1</integer>
                    </dict>
                </array>
                <key>connectors</key>
                <dict/>
                <key>workflowMetaData</key>
                <dict>
                    <key>serviceInputTypeIdentifier</key>
                    <string>com.apple.Automator.fileSystemObject</string>
                    <key>serviceApplicationPath</key>
                    <string>/System/Library/CoreServices/Finder.app</string>
                    <key>workflowTypeIdentifier</key>
                    <string>com.apple.Automator.servicesMenu</string>
                </dict>
            </dict>
            </plist>
            """
            try workflowPlist.write(to: contentsDir.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
            
            NSUpdateDynamicServices()
            
            return (true, "Quick Scan Action installed! Right-click any folder in Finder to use 'Scan with Sorty'.")
            
        } catch {
            return (false, "Installation failed: \(error.localizedDescription)")
        }
    }
    
    /// Check if Quick Scan Action is installed
    public static func isQuickScanActionInstalled() -> Bool {
        let workflowPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services/Scan with Sorty.workflow")
        return FileManager.default.fileExists(atPath: workflowPath.path)
    }
    
    /// Uninstall the Quick Scan Action
    public static func uninstallQuickScanAction() -> Bool {
        let workflowPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services/Scan with Sorty.workflow")
        
        do {
            try FileManager.default.removeItem(at: workflowPath)
            NSUpdateDynamicServices()
            return true
        } catch {
            return false
        }
    }
    
    /// Uninstall the Quick Action
    public static func uninstallQuickAction() -> Bool {
        let workflowPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services/Organize with Sorty.workflow")

        do {
            try FileManager.default.removeItem(at: workflowPath)
            NSUpdateDynamicServices()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Quick Preview Action Installation

    /// Install a "Preview with Sorty" Quick Action workflow to ~/Library/Services
    public static func installQuickPreviewAction() -> (success: Bool, message: String) {
        let workflowName = "Preview with Sorty.workflow"

        let servicesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services")
        let workflowDir = servicesDir.appendingPathComponent(workflowName)
        let contentsDir = workflowDir.appendingPathComponent("Contents")

        do {
            try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

            let infoPlist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>NSServices</key>
                <array>
                    <dict>
                        <key>NSMenuItem</key>
                        <dict>
                            <key>default</key>
                            <string>Preview with Sorty</string>
                        </dict>
                        <key>NSMessage</key>
                        <string>runWorkflowAsService</string>
                        <key>NSSendFileTypes</key>
                        <array>
                            <string>public.folder</string>
                            <string>public.item</string>
                        </array>
                    </dict>
                </array>
            </dict>
            </plist>
            """
            try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

            let shellCommand = """
            for f in "$@"; do if [[ "$f" == file://* ]]; then f=$(/usr/bin/python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(urllib.parse.urlparse(sys.argv[1]).path))" "$f" 2>/dev/null || echo "$f" | sed 's|^file://||'); fi; if [ -f "$f" ]; then f="$(dirname "$f")"; fi; encoded=$(/usr/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$f" 2>/dev/null || printf '%s' "$f" | sed 's/ /%20/g; s/!/%21/g; s/#/%23/g; s/\\$/%24/g; s/&amp;/%26/g; s/(/%28/g; s/)/%29/g'); open "sorty://scan?path=$encoded&amp;preview=true"; done
            """

            let workflowPlist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>AMApplicationBuild</key>
                <string>523</string>
                <key>AMApplicationVersion</key>
                <string>2.10</string>
                <key>AMDocumentVersion</key>
                <string>2</string>
                <key>actions</key>
                <array>
                    <dict>
                        <key>action</key>
                        <dict>
                            <key>AMAccepts</key>
                            <dict>
                                <key>Container</key>
                                <string>List</string>
                                <key>Optional</key>
                                <true/>
                                <key>Types</key>
                                <array>
                                    <string>com.apple.cocoa.path</string>
                                    <string>com.apple.cocoa.url</string>
                                    <string>public.item</string>
                                    <string>public.folder</string>
                                </array>
                            </dict>
                            <key>AMActionVersion</key>
                            <string>1.0.2</string>
                            <key>AMApplication</key>
                            <array>
                                <string>Automator</string>
                            </array>
                            <key>AMCategory</key>
                            <string>AMCategoryUtilities</string>
                            <key>AMIconName</key>
                            <string>Run Script</string>
                            <key>AMName</key>
                            <string>Run Shell Script</string>
                            <key>AMParameters</key>
                            <dict>
                                <key>COMMAND_STRING</key>
                                <string>\(shellCommand)</string>
                                <key>CheckedForUserDefaultShell</key>
                                <true/>
                                <key>inputMethod</key>
                                <integer>1</integer>
                                <key>shell</key>
                                <string>/bin/zsh</string>
                                <key>source</key>
                                <string></string>
                            </dict>
                            <key>AMProvides</key>
                            <dict>
                                <key>Container</key>
                                <string>List</string>
                                <key>Types</key>
                                <array>
                                    <string>com.apple.cocoa.path</string>
                                </array>
                            </dict>
                            <key>AMRequiredResources</key>
                            <array/>
                            <key>ActionBundlePath</key>
                            <string>/System/Library/Automator/Run Shell Script.action</string>
                            <key>ActionName</key>
                            <string>Run Shell Script</string>
                            <key>ActionParameters</key>
                            <dict>
                                <key>COMMAND_STRING</key>
                                <string>\(shellCommand)</string>
                                <key>CheckedForUserDefaultShell</key>
                                <true/>
                                <key>inputMethod</key>
                                <integer>1</integer>
                                <key>shell</key>
                                <string>/bin/zsh</string>
                                <key>source</key>
                                <string></string>
                            </dict>
                            <key>BundleIdentifier</key>
                            <string>com.apple.RunShellScript</string>
                            <key>CFBundleVersion</key>
                            <string>1.0.2</string>
                            <key>CanShowSelectedItemsWhenRun</key>
                            <false/>
                            <key>CanShowWhenRun</key>
                            <true/>
                            <key>Category</key>
                            <array>
                                <string>AMCategoryUtilities</string>
                            </array>
                            <key>Class Name</key>
                            <string>RunShellScriptAction</string>
                            <key>InputUUID</key>
                            <string>9D4E5F6A-7B8C-9D0E-1F2A-3B4C5D6E7F8A</string>
                            <key>Keywords</key>
                            <array>
                                <string>Shell</string>
                                <string>Script</string>
                                <string>Command</string>
                                <string>Run</string>
                                <string>Unix</string>
                            </array>
                            <key>OutputUUID</key>
                            <string>AE5F6A7B-8C9D-0E1F-2A3B-4C5D6E7F8A9B</string>
                            <key>UUID</key>
                            <string>BF6A7B8C-9D0E-1F2A-3B4C-5D6E7F8A9B0C</string>
                            <key>UnlocalizedApplications</key>
                            <array>
                                <string>Automator</string>
                            </array>
                            <key>arguments</key>
                            <dict>
                                <key>0</key>
                                <dict>
                                    <key>default value</key>
                                    <integer>1</integer>
                                    <key>name</key>
                                    <string>inputMethod</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>0</string>
                                </dict>
                                <key>1</key>
                                <dict>
                                    <key>default value</key>
                                    <string></string>
                                    <key>name</key>
                                    <string>source</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>1</string>
                                </dict>
                                <key>2</key>
                                <dict>
                                    <key>default value</key>
                                    <false/>
                                    <key>name</key>
                                    <string>CheckedForUserDefaultShell</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>2</string>
                                </dict>
                                <key>3</key>
                                <dict>
                                    <key>default value</key>
                                    <string></string>
                                    <key>name</key>
                                    <string>COMMAND_STRING</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>3</string>
                                </dict>
                                <key>4</key>
                                <dict>
                                    <key>default value</key>
                                    <string>/bin/sh</string>
                                    <key>name</key>
                                    <string>shell</string>
                                    <key>required</key>
                                    <string>0</string>
                                    <key>type</key>
                                    <string>0</string>
                                    <key>uuid</key>
                                    <string>4</string>
                                </dict>
                            </dict>
                            <key>isViewVisible</key>
                            <integer>1</integer>
                            <key>location</key>
                            <string>309.000000:253.000000</string>
                            <key>nibPath</key>
                            <string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
                        </dict>
                        <key>isViewVisible</key>
                        <integer>1</integer>
                    </dict>
                </array>
                <key>connectors</key>
                <dict/>
                <key>workflowMetaData</key>
                <dict>
                    <key>serviceInputTypeIdentifier</key>
                    <string>com.apple.Automator.fileSystemObject</string>
                    <key>serviceApplicationPath</key>
                    <string>/System/Library/CoreServices/Finder.app</string>
                    <key>workflowTypeIdentifier</key>
                    <string>com.apple.Automator.servicesMenu</string>
                </dict>
            </dict>
            </plist>
            """
            try workflowPlist.write(to: contentsDir.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)

            NSUpdateDynamicServices()

            return (true, "Preview Action installed! Right-click any folder in Finder to use 'Preview with Sorty'.")

        } catch {
            return (false, "Installation failed: \(error.localizedDescription)")
        }
    }

    /// Check if Quick Preview Action is installed
    public static func isQuickPreviewActionInstalled() -> Bool {
        let workflowPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services/Preview with Sorty.workflow")
        return FileManager.default.fileExists(atPath: workflowPath.path)
    }

    /// Uninstall the Quick Preview Action
    public static func uninstallQuickPreviewAction() -> Bool {
        let workflowPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services/Preview with Sorty.workflow")

        do {
            try FileManager.default.removeItem(at: workflowPath)
            NSUpdateDynamicServices()
            return true
        } catch {
            return false
        }
    }

    /// Uninstall all Quick Action workflows
    public static func uninstallAllQuickActions() -> (success: Bool, removed: Int) {
        let workflows = [
            "Organize with Sorty.workflow",
            "Scan with Sorty.workflow",
            "Preview with Sorty.workflow"
        ]

        var removedCount = 0
        let servicesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services")

        for workflow in workflows {
            let workflowPath = servicesDir.appendingPathComponent(workflow)
            if FileManager.default.fileExists(atPath: workflowPath.path) {
                do {
                    try FileManager.default.removeItem(at: workflowPath)
                    removedCount += 1
                } catch {
                    // Continue trying other workflows
                }
            }
        }

        if removedCount > 0 {
            NSUpdateDynamicServices()
        }

        return (removedCount > 0, removedCount)
    }

    // MARK: - AppleScript Integration
    
    /// Generate AppleScript for organizing a folder
    public static func appleScriptForOrganizing() -> String {
        return """
        on run {input, parameters}
            repeat with theItem in input
                set thePath to POSIX path of theItem
                set encodedPath to do shell script "/usr/bin/python3 -c \\"import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))\\" " & quoted form of thePath & " 2>/dev/null || printf '%s' " & quoted form of thePath & " | sed 's/ /%20/g; s/!/%21/g; s/#/%23/g; s/\\\\$/%24/g; s/&/%26/g; s/(/%28/g; s/)/%29/g'"
                do shell script "open 'sorty://organize?path=" & encodedPath & "'"
            end repeat
            return input
        end run
        """
    }
    
    /// Open Finder Extension preferences
    public static func openFinderExtensionSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preferences.extensions?Extensions")
        if let url = url {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Keyboard Shortcut Registration
    
    /// Register a global keyboard shortcut for quick organize
    public static func registerGlobalShortcut() {
        // Note: Requires accessibility permissions
        // This is a placeholder - actual implementation would use Carbon APIs or MASShortcut
    }
    
    // MARK: - Finder Integration Status
    
    public struct FinderIntegrationStatus {
        public let quickActionInstalled: Bool
        public let quickScanActionInstalled: Bool
        public let quickPreviewActionInstalled: Bool
        public let toolbarAppInstalled: Bool
        public let finderSyncEnabled: Bool
        public let menuBarEnabled: Bool

        public var overallStatus: String {
            if quickActionInstalled || quickScanActionInstalled || quickPreviewActionInstalled || toolbarAppInstalled {
                return "Active"
            }
            return "Not Configured"
        }

        public var integrationCount: Int {
            [quickActionInstalled, quickScanActionInstalled, quickPreviewActionInstalled, toolbarAppInstalled, finderSyncEnabled, menuBarEnabled]
                .filter { $0 }.count
        }
    }

    /// Get current integration status
    public static func getIntegrationStatus() -> FinderIntegrationStatus {
        let finderSyncEnabled = UserDefaults.standard.bool(forKey: "enableFinderSyncExtension")

        return FinderIntegrationStatus(
            quickActionInstalled: isQuickActionInstalled(),
            quickScanActionInstalled: isQuickScanActionInstalled(),
            quickPreviewActionInstalled: isQuickPreviewActionInstalled(),
            toolbarAppInstalled: FinderToolbarHelper.isToolbarAppInstalled(),
            finderSyncEnabled: finderSyncEnabled,
            menuBarEnabled: UserDefaults.standard.bool(forKey: "showMenuBarExtra")
        )
    }
    
    // MARK: - Complete Setup
    
    /// Install all recommended Finder integrations
    public static func installAllIntegrations() -> [(name: String, success: Bool, message: String)] {
        var results: [(name: String, success: Bool, message: String)] = []

        // 1. Quick Action
        let quickActionResult = installQuickAction()
        results.append(("Quick Action", quickActionResult.success, quickActionResult.message))

        // 2. Quick Scan Action
        let quickScanResult = installQuickScanAction()
        results.append(("Quick Scan Action", quickScanResult.success, quickScanResult.message))

        // 3. Quick Preview Action
        let quickPreviewResult = installQuickPreviewAction()
        results.append(("Quick Preview Action", quickPreviewResult.success, quickPreviewResult.message))

        // 4. Toolbar App - Removed due to dependency issues
        // let toolbarResult = FinderToolbarHelper.createToolbarApp()
        // results.append(("Toolbar Button", toolbarResult.success, toolbarResult.message))

        return results
    }
    
    /// Get instructions for manual Finder toolbar setup
    public static func getToolbarInstructions() -> String {
        return """
        To add Sorty to your Finder toolbar:
        
        1. Click "Install Toolbar Button" below
        2. A Finder window will open showing the helper app
        3. Hold Command (⌘) and drag "Organize with Sorty" to your Finder toolbar
        4. Click the button anytime to organize the current folder!
        
        Alternative: Right-click on any folder and select "Organize with Sorty" from the context menu.
        """
    }
}
