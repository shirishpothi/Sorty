//
//  SortyResources.swift
//  Sorty
//
//  Safe resource bundle resolver that works for both SPM and Xcode builds
//

import Foundation

public enum SortyResources {
    private final class Token {}
    
    public static let bundle: Bundle = {
        let primaryCandidates: [Bundle] = [
            .main,
            Bundle(for: Token.self),
        ]
        
        // Look for SwiftPM resource bundle names
        let candidateBundleNames = [
            "Sorty_SortyLib",
            "SortyLib_SortyLib",
            "SortyLib",
        ]
        
        // Search inside candidates for embedded bundles
        for base in primaryCandidates {
            for name in candidateBundleNames {
                if let url = base.url(forResource: name, withExtension: "bundle"),
                   let b = Bundle(url: url) {
                    return b
                }
            }
        }
        
        // Scan all bundles/frameworks for one containing our known resource directory
        let all = Bundle.allBundles + Bundle.allFrameworks
        for b in all {
            if b.url(forResource: "Images", withExtension: nil) != nil {
                return b
            }
        }
        
        return .main
    }()
}
