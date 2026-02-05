//
//  CompletionStepView.swift
//  Sorty
//
//  Completion step of the onboarding flow
//

import SwiftUI

public struct CompletionStepView: View {
    let onFinish: () -> Void
    
    @State private var hasAppeared = false
    @State private var showConfetti = false
    @State private var exitProgress: CGFloat = 0
    
    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    public var body: some View {
        ZStack {
            VStack(spacing: 40) {
                Spacer()
                
                // Success icon
                ZStack {
                    // Animated rings
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(Color.green.opacity(0.2 - Double(index) * 0.05), lineWidth: 2)
                            .frame(width: CGFloat(140 + index * 30), height: CGFloat(140 + index * 30))
                            .scaleEffect(showConfetti ? 1.2 : 0.8)
                            .opacity(showConfetti ? 0 : 1)
                            .animation(
                                .easeOut(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.3),
                                value: showConfetti
                            )
                    }
                    
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 140, height: 140)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: hasAppeared)
                }
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.5)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: hasAppeared)
                
                // Title and message
                VStack(spacing: 16) {
                    Text("Sorty is Ready!")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    
                    Text("You're all set to start organizing your files with AI.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
                
                // Quick tips
                VStack(spacing: 12) {
                    QuickTipRow(icon: "folder.badge.plus", text: "Drag any folder to organize it")
                    QuickTipRow(icon: "keyboard", text: "Press ⌘O to open a folder")
                    QuickTipRow(icon: "arrow.uturn.backward", text: "All changes can be undone")
                    QuickTipRow(icon: "gearshape", text: "Customize everything in Settings")
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                
                // Start button
                Button {
                    startTransition()
                } label: {
                    HStack(spacing: 8) {
                        Text("Start Using Sorty")
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                    }
                }
                .buttonStyle(.onboardingPill)
                .keyboardShortcut(.defaultAction)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
                .scaleEffect(1 + exitProgress * 0.05)
                
                Spacer()
            }
            .padding(.horizontal, 60)
            .scaleEffect(1 - exitProgress * 0.03)
            .opacity(1 - exitProgress)
            .blur(radius: exitProgress * 2)
        }
        .onAppear {
            withAnimation { hasAppeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showConfetti = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completion Step")
    }
    
    private func startTransition() {
        HapticFeedbackManager.shared.success()
        
        withAnimation(.easeOut(duration: 0.5)) {
            exitProgress = 1
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            onFinish()
        }
    }
}

struct QuickTipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    CompletionStepView(onFinish: {})
}
