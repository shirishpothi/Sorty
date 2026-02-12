//
//  SortyResources.swift
//  Sorty
//
//  Robust resource bundle accessor with multi-layer detection
//  Handles SPM, xcodebuild, and direct swift build scenarios
//

import Foundation
import AppKit
import os.log

public enum SortyResources {
    private static let logger = Logger(subsystem: "com.sorty.app", category: "Resources")

    /// The resource bundle for SortyLib resources.
    /// Uses multi-layer detection to find resources in various build scenarios:
    /// 1. Class-based bundle lookup (works in most contexts)
    /// 2. Dynamic SPM bundle discovery (fallback for SPM builds)
    /// 3. Main bundle (final fallback, works when build scripts copy resources)
    public static let bundle: Bundle = {
        let detectedBundle = detectResourceBundle()
        logger.debug("Resource bundle resolved to: \(detectedBundle.bundlePath)")
        return detectedBundle
    }()

    /// Whether the bundle was resolved via the asset catalog (compiled .car file)
    /// This is true when running from an Xcode-built app with proper asset catalog compilation
    public static var usesCompiledAssetCatalog: Bool {
        // Check for .car file in the bundle's Resources directory
        if let resourceURL = bundle.resourceURL {
            let carPath = resourceURL.appendingPathComponent("Assets.car").path
            return FileManager.default.fileExists(atPath: carPath)
        }
        return false
    }

    /// Detects the appropriate resource bundle using multiple strategies
    private static func detectResourceBundle() -> Bundle {
        // Strategy 0: SwiftPM module bundle (most reliable for SPM resources)
        #if SWIFT_PACKAGE
        if hasResources(in: Bundle.module) {
            logger.debug("Using Bundle.module for SPM resources")
            return Bundle.module
        }
        #endif

        // Strategy 1: Class-based bundle lookup (most reliable for frameworks)
        // This finds the bundle containing the SortyResources type itself
        let classBundle = Bundle(for: BundleLocator.self)
        if classBundle != Bundle.main && classBundle.bundleIdentifier != nil {
            // Verify it has resources
            if hasResources(in: classBundle) {
                logger.debug("Using class-based bundle lookup")
                return classBundle
            }
        }

        // Strategy 2: Dynamic SPM bundle discovery via path lookup
        if let spmBundle = findSPMBundle() {
            logger.debug("Using dynamic SPM bundle discovery")
            return spmBundle
        }

        // Strategy 3: Main bundle (final fallback)
        // This works when build scripts copy resources to the app bundle
        logger.debug("Using Bundle.main as fallback")
        return Bundle.main
    }

    /// Checks if a bundle appears to have Sorty resources
    private static func hasResources(in bundle: Bundle) -> Bool {
        // Check for Images directory
        if let imagesURL = bundle.resourceURL?.appendingPathComponent("Images"),
           FileManager.default.fileExists(atPath: imagesURL.path) {
            return true
        }

        // Check for audio resources copied via SPM (.copy)
        if let resourceURL = bundle.resourceURL {
            let wavAtRoot = resourceURL.appendingPathComponent("OnboardingSound.wav").path
            let wavInResources = resourceURL.appendingPathComponent("Resources/OnboardingSound.wav").path
            let resourcesDir = resourceURL.appendingPathComponent("Resources").path
            if FileManager.default.fileExists(atPath: wavAtRoot) ||
                FileManager.default.fileExists(atPath: wavInResources) ||
                FileManager.default.fileExists(atPath: resourcesDir) {
                return true
            }
        }

        // Check for SPM bundle structure
        if bundle.bundlePath.contains("Sorty_SortyLib.bundle") {
            return true
        }

        // Check for Assets.car (compiled asset catalog)
        if let resourceURL = bundle.resourceURL,
           FileManager.default.fileExists(atPath: resourceURL.appendingPathComponent("Assets.car").path) {
            return true
        }

        return false
    }

    /// Attempts to find the SPM-generated resource bundle dynamically
    private static func findSPMBundle() -> Bundle? {
        // Try to locate the SPM bundle relative to the executable
        let mainBundle = Bundle.main

        // Look for Sorty_SortyLib.bundle in various locations
        let possiblePaths = [
            // Direct sibling of executable
            mainBundle.bundleURL.appendingPathComponent("Sorty_SortyLib.bundle"),
            // In Resources directory
            mainBundle.resourceURL?.appendingPathComponent("Sorty_SortyLib.bundle"),
            // In Frameworks
            mainBundle.bundleURL.appendingPathComponent("Frameworks/Sorty_SortyLib.bundle"),
            // In PlugIns
            mainBundle.bundleURL.appendingPathComponent("PlugIns/Sorty_SortyLib.bundle"),
        ].compactMap { $0 }

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                if let bundle = Bundle(url: path) {
                    return bundle
                }
            }
        }

        return nil
    }

    /// Helper class for bundle location via class-based lookup
    private final class BundleLocator {}

    /// Loads an image from the resource bundle, trying multiple sources
    /// - Parameters:
    ///   - name: The image name (without extension)
    ///   - extension: The file extension (default: "png")
    /// - Returns: NSImage if found, nil otherwise
    public static func image(named name: String, withExtension ext: String = "png") -> NSImage? {
        // Try 1: Asset catalog (if compiled .car exists)
        if usesCompiledAssetCatalog {
            if let nsImage = bundle.image(forResource: name) {
                logger.debug("Loaded image '\(name)' from asset catalog")
                return nsImage
            }
        }
        
        // Try 2: Direct bundle resource lookup (works for Xcode builds with asset catalog)
        if let nsImage = bundle.image(forResource: name) {
            logger.debug("Loaded image '\(name)' from bundle resource")
            return nsImage
        }

        // Try 3: Main bundle fallback (covers app-level asset catalogs)
        if bundle != Bundle.main, let nsImage = Bundle.main.image(forResource: name) {
            logger.debug("Loaded image '\(name)' from main bundle")
            return nsImage
        }

        // Try 4: Images subdirectory (SPM .copy() resources)
        if let imageURL = bundle.url(forResource: name, withExtension: ext, subdirectory: "Images"),
           let nsImage = NSImage(contentsOf: imageURL) {
            logger.debug("Loaded image '\(name)' from Images subdirectory")
            return nsImage
        }

        // Try 5: Direct bundle resource with extension
        if let imageURL = bundle.url(forResource: name, withExtension: ext),
           let nsImage = NSImage(contentsOf: imageURL) {
            logger.debug("Loaded image '\(name)' from bundle root")
            return nsImage
        }

        // Try 6: Bundle image resource helper (covers non-asset bundled images)
        if let imageURL = bundle.urlForImageResource(name),
           let nsImage = NSImage(contentsOf: imageURL) {
            logger.debug("Loaded image '\(name)' via urlForImageResource")
            return nsImage
        }
        
        // Try 7: Look in Resources/Assets.xcassets imageset directories (development fallback)
        // This handles the case where Xcode hasn't compiled the asset catalog yet
        let extensions = ["png", "svg", "pdf"]
        let basePaths = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Resources/Assets.xcassets/\(name).imageset"),
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Assets.xcassets/\(name).imageset"),
            // Also try from source root during development
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Assets.xcassets/\(name).imageset")
        ]
        
        for basePath in basePaths {
            for fileExt in extensions {
                let path = basePath.appendingPathComponent("\(name).\(fileExt)")
                if FileManager.default.fileExists(atPath: path.path),
                   let nsImage = NSImage(contentsOf: path) {
                    logger.debug("Loaded image '\(name)' from Assets.xcassets imageset at \(path.path)")
                    return nsImage
                }
            }
        }

        logger.warning("Failed to load image '\(name)' from any source")
        return nil
    }

    public static func urlForCopiedResource(named fileName: String) -> URL? {
        if let url = bundle.url(forResource: fileName, withExtension: nil) { return url }
        if let url = bundle.url(forResource: fileName, withExtension: nil, subdirectory: "Resources") { return url }

        let nameWithoutExt = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        if !ext.isEmpty, let url = bundle.url(forResource: nameWithoutExt, withExtension: ext) { return url }

        guard let resourceURL = bundle.resourceURL else { return nil }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.lastPathComponent == fileName {
                return url
            }
        }
        return nil
    }

    public static func onboardingSoundURL() -> URL? {
        urlForCopiedResource(named: "OnboardingSound.wav")
    }

    public static func finalOnboardingSoundURL() -> URL? {
        urlForCopiedResource(named: "Final Onboarding.wav")
    }

    /// Loads a robust NSImage for the menu bar item, bypassing asset catalog complexity
    /// and providing a guaranteed fallback to an SF Symbol.
    public static func menuBarNSImage() -> NSImage {
        // Try direct file-based loading from the bundle first (most reliable for SPM/macOS 15)
        if let url = bundle.url(forResource: "SortyMascotTemplate", withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            return img
        }
        
        // Fallback to name-based lookup
        if let img = image(named: "SortyMascotTemplate", withExtension: "svg") {
            img.isTemplate = true
            return img
        }
        
        // Final fallback: standard SF Symbol
        let symbol = NSImage(systemSymbolName: "folder.fill.badge.gearshape", accessibilityDescription: "Sorty")!
        symbol.isTemplate = true
        return symbol
    }
}
