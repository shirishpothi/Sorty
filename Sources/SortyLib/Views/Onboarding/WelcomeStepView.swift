//
//  WelcomeStepView.swift
//  Sorty
//
//  Welcome step of the onboarding flow
//

import SwiftUI
import AppKit

public struct WelcomeStepView: View {
    @State private var hasAppeared = false
    @State private var featuresAppeared = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // App icon and title
            VStack(spacing: 24) {
                // Use the application icon directly which is safer than bundle loading
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                    .scaleEffect(hasAppeared ? 1 : 0.5)
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: hasAppeared)
                
                VStack(spacing: 12) {
                    Text("Welcome to Sorty")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
                    
                    Text("AI-powered file organization for your Mac")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 15)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                }
            }
            
            Spacer()
                .frame(height: 48)
            
            // Key features
            VStack(alignment: .leading, spacing: 16) {
                WelcomeFeatureRow(
                    icon: "wand.and.stars",
                    iconColor: .purple,
                    title: "Smart Organization",
                    description: "AI analyzes your files and creates a logical folder structure"
                )
                .opacity(featuresAppeared ? 1 : 0)
                .offset(x: featuresAppeared ? 0 : -30)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: featuresAppeared)
                
                WelcomeFeatureRow(
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "Privacy Focused",
                    description: "File names and metadata are sent to AI for organization - file contents stay on your Mac unless Deep Scan is enabled"
                )
                .opacity(featuresAppeared ? 1 : 0)
                .offset(x: featuresAppeared ? 0 : -30)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: featuresAppeared)
                
                WelcomeFeatureRow(
                    icon: "arrow.uturn.backward.circle.fill",
                    iconColor: .blue,
                    title: "Fully Reversible",
                    description: "Every change can be undone with a single click",
                    badge: "Beta"
                )
                .opacity(featuresAppeared ? 1 : 0)
                .offset(x: featuresAppeared ? 0 : -30)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6), value: featuresAppeared)
                
                WelcomeFeatureRow(
                    icon: "person.crop.circle.badge.checkmark",
                    iconColor: .orange,
                    title: "Custom Workflows",
                    description: "Create personas tailored to your specific organization needs"
                )
                .opacity(featuresAppeared ? 1 : 0)
                .offset(x: featuresAppeared ? 0 : -30)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.7), value: featuresAppeared)
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 60)
            
            Spacer()
                .frame(height: 32)
            
            // Important notice
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 18))
                
                Text("Before organizing, always ensure you have backups of important files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer() // Push content to left
            }
            .padding(16)
            .frame(maxWidth: 500)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.05))
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
            .opacity(featuresAppeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.8), value: featuresAppeared)
            
            Spacer()
        }
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                withAnimation {
                    featuresAppeared = true
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome Step")
    }
}

// MARK: - Welcome Feature Row

struct WelcomeFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    var badge: String? = nil
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    
                    if let badge = badge {
                        Text(badge.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    WelcomeStepView()
}
