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

        // Try 2: Images subdirectory (SPM .copy() resources)
        if let imageURL = bundle.url(forResource: name, withExtension: ext, subdirectory: "Images"),
           let nsImage = NSImage(contentsOf: imageURL) {
            logger.debug("Loaded image '\(name)' from Images subdirectory")
            return nsImage
        }

        // Try 3: Direct bundle resource
        if let imageURL = bundle.url(forResource: name, withExtension: ext),
           let nsImage = NSImage(contentsOf: imageURL) {
            logger.debug("Loaded image '\(name)' from bundle root")
            return nsImage
        }

        logger.warning("Failed to load image '\(name)' from any source")
        return nil
    }
}
