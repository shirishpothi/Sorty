//
//  InlineLearningMomentView.swift
//  Sorty
//
//  Compact post-organization learning moment — a quick contextual question
//  to refine the user's organization preferences.
//

import SwiftUI

struct InlineLearningMomentView: View {
    let moment: InlineLearningMoment
    let onAnswer: (InlineLearningMomentAnswer?) -> Void
    
    @State private var hoveredOption: String?
    
    var body: some View {
        VStack(spacing: 16) {
            headerRow
            questionText
            optionsList
        }
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 420)
    }
    
    // MARK: - Header
    
    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(.yellow)
            
            Text("Quick Question")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                HapticFeedbackManager.shared.tap()
                onAnswer(nil)
            } label: {
                Text("Skip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                if isHovering { HapticFeedbackManager.shared.selection() }
            }
        }
        .animatedAppearance(delay: 0.05)
    }
    
    // MARK: - Question
    
    private var questionText: some View {
        Text(moment.prompt)
            .font(.body.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animatedAppearance(delay: 0.1)
    }
    
    // MARK: - Options
    
    private var optionsList: some View {
        VStack(spacing: 8) {
            ForEach(Array(moment.options.enumerated()), id: \.element) { index, option in
                optionButton(option: option, index: index)
            }
        }
    }
    
    private func optionButton(option: String, index: Int) -> some View {
        Button {
            HapticFeedbackManager.shared.light()
            let answer = InlineLearningMomentAnswer(
                momentId: moment.id,
                sessionId: moment.sessionId,
                selectedOption: option
            )
            onAnswer(answer)
        } label: {
            HStack(spacing: 10) {
                Text(option)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if hoveredOption == option {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hoveredOption == option
                          ? Color.accentColor.opacity(0.08)
                          : Color.secondary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredOption = isHovering ? option : nil
            }
            if isHovering { HapticFeedbackManager.shared.selection() }
        }
        .animatedAppearance(delay: 0.15 + Double(index) * 0.05)
    }
}
