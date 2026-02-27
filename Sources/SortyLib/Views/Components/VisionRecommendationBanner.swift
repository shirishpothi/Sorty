//
//  VisionRecommendationBanner.swift
//  Sorty
//
//  Shows a recommendation banner when images are detected but vision is not enabled
//

import SwiftUI

enum VisionRecommendationAction: Equatable {
    case enableVision
    case switchModel
    case none
}

struct VisionRecommendationBannerState {
    var imageCount: Int
    var isVisionEnabled: Bool
    var supportsVision: Bool
    var isDismissed: Bool

    var isVisible: Bool {
        !isDismissed && imageCount > 0 && (!isVisionEnabled || !supportsVision)
    }

    var recommendedAction: VisionRecommendationAction {
        if supportsVision && !isVisionEnabled {
            return .enableVision
        }
        if !supportsVision {
            return .switchModel
        }
        return .none
    }

    mutating func dismiss() {
        isDismissed = true
    }
}

struct VisionRecommendationBanner: View {
    let imageCount: Int
    let currentModel: String
    let currentProvider: AIProvider
    let isVisionEnabled: Bool
    let onEnableVision: () -> Void
    let onSwitchModel: () -> Void
    let onDismiss: () -> Void
    
    @State private var isDismissed = false
    
    private var supportsVision: Bool {
        ModelCatalog.shared.supportsVision(modelId: currentModel, provider: currentProvider)
    }
    
    var body: some View {
        let state = VisionRecommendationBannerState(
            imageCount: imageCount,
            isVisionEnabled: isVisionEnabled,
            supportsVision: supportsVision,
            isDismissed: isDismissed
        )

        if state.isVisible {
            HStack(spacing: 12) {
                Image(systemName: "camera.aperture")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("📸 \(imageCount) images detected")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if state.recommendedAction == .enableVision {
                        Text("Enable AI Vision for content-aware organization")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if state.recommendedAction == .switchModel {
                        Text("Use a vision model like gpt-4o or claude-3-5-sonnet for better results")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if state.recommendedAction == .enableVision {
                    Button("Enable Vision") {
                        onEnableVision()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if state.recommendedAction == .switchModel {
                    Button("Switch Model") {
                        onSwitchModel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDismissed = true
                    }
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        VisionRecommendationBanner(
            imageCount: 23,
            currentModel: "gpt-3.5-turbo",
            currentProvider: .openAI,
            isVisionEnabled: false,
            onEnableVision: {},
            onSwitchModel: {},
            onDismiss: {}
        )
        
        VisionRecommendationBanner(
            imageCount: 15,
            currentModel: "gpt-4o",
            currentProvider: .openAI,
            isVisionEnabled: false,
            onEnableVision: {},
            onSwitchModel: {},
            onDismiss: {}
        )
    }
    .padding()
}
