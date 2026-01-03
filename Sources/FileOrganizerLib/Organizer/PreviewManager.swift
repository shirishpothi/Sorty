//
//  PreviewManager.swift
//  FileOrganizer
//
//  Manages preview workflow and version tracking
//

import Foundation
import Combine

@MainActor
class PreviewManager: ObservableObject {
    @Published private(set) var previews: [OrganizationPlan] = []
    @Published private(set) var currentPreviewIndex: Int = -1
    @Published private(set) var maxVersions: Int = 5
    
    var currentPreview: OrganizationPlan? {
        guard currentPreviewIndex >= 0 && currentPreviewIndex < previews.count else {
            return nil
        }
        return previews[currentPreviewIndex]
    }
    
    var canRegenerate: Bool {
        previews.count < maxVersions
    }
    
    var previewCount: Int {
        previews.count
    }
    
    func savePreview(_ plan: OrganizationPlan) {
        var newPlan = plan
        newPlan.version = previews.count + 1
        previews.append(newPlan)
        currentPreviewIndex = previews.count - 1
    }
    
    func getPreview(version: Int) -> OrganizationPlan? {
        guard version > 0 && version <= previews.count else {
            return nil
        }
        return previews[version - 1]
    }
    
    func regenerate() async throws -> OrganizationPlan {
        guard let current = currentPreview else {
            throw PreviewError.noCurrentPreview
        }
        
        // Return a new version of the current preview
        // In practice, this would trigger a new AI analysis
        var newPlan = current
        newPlan.version = previews.count + 1
        newPlan.timestamp = Date()
        return newPlan
    }
    
    func clear() {
        previews.removeAll()
        currentPreviewIndex = -1
    }
    
    func selectPreview(version: Int) {
        guard version > 0 && version <= previews.count else {
            return
        }
        currentPreviewIndex = version - 1
    }
}

enum PreviewError: LocalizedError {
    case noCurrentPreview
    case maxVersionsReached
    
    var errorDescription: String? {
        switch self {
        case .noCurrentPreview:
            return "No current preview available"
        case .maxVersionsReached:
            return "Maximum number of preview versions reached"
        }
    }
}



