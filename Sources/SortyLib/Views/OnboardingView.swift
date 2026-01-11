//
//  OnboardingView.swift
//  Sorty
//
//  Animated onboarding flow for first-time users
//

import SwiftUI

public struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var isAnimating = false
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "wand.and.stars",
            iconColor: .purple,
            title: "Welcome to Sorty",
            subtitle: "AI-powered file organization for macOS",
            description: "Sorty uses artificial intelligence to analyze your files and organize them into meaningful, semantically-named folders."
        ),
        OnboardingPage(
            icon: "folder.badge.gearshape",
            iconColor: .blue,
            title: "Smart Organization",
            subtitle: "Drop a folder and watch the magic happen",
            description: "Simply drag and drop any folder, and Sorty will analyze file contents, names, and context to suggest an intelligent folder structure."
        ),
        OnboardingPage(
            icon: "person.crop.circle.badge.checkmark",
            iconColor: .teal,
            title: "Personalized Experience",
            subtitle: "Create custom AI personas for different workflows",
            description: "Whether you're a developer, photographer, or student—create personas that understand your unique organization needs."
        ),
        OnboardingPage(
            icon: "brain.head.profile",
            iconColor: .indigo,
            title: "The Learnings Profile",
            subtitle: "Your personal AI organizer that gets smarter",
            description: "Sorty learns from your corrections and preferences over time, creating a unique organization model tailored just for you."
        ),
        OnboardingPage(
            icon: "arrow.uturn.backward.circle",
            iconColor: .orange,
            title: "Safe & Reversible",
            subtitle: "Preview before applying, undo anytime",
            description: "Every organization can be previewed, edited, and fully reversed. Your files are always safe with comprehensive rollback support."
        )
    ]
    
    public init(hasCompletedOnboarding: Binding<Bool>) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
    }
    
    public var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                navigationControls
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Onboarding")
        .accessibilityIdentifier("OnboardingView")
    }
    
    private var pageContent: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                OnboardingPageView(page: page, isActive: currentPage == index)
                    .tag(index)
            }
        }
        .tabViewStyle(.automatic)
        .animation(.pageTransition, value: currentPage)
    }
    
    private var navigationControls: some View {
        HStack(spacing: 16) {
            if currentPage > 0 {
                Button {
                    HapticFeedbackManager.shared.selection()
                    withAnimation(.pageTransition) {
                        currentPage -= 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                    }
                    .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityIdentifier("OnboardingBackButton")
            }
            
            Spacer()
            
            pageIndicator
            
            Spacer()
            
            if currentPage < pages.count - 1 {
                Button {
                    HapticFeedbackManager.shared.selection()
                    withAnimation(.pageTransition) {
                        currentPage += 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityIdentifier("OnboardingNextButton")
            } else {
                Button {
                    HapticFeedbackManager.shared.success()
                    withAnimation(.pageTransition) {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Get Started")
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14))
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("OnboardingGetStartedButton")
            }
        }
    }
    
    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == currentPage ? 10 : 8, height: index == currentPage ? 10 : 8)
                    .animation(.subtleBounce, value: currentPage)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentPage + 1) of \(pages.count)")
    }
}

struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool
    
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 20
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            AnimatedIcon(
                systemName: page.icon,
                color: page.iconColor,
                isActive: isActive
            )
            .frame(width: 120, height: 120)
            
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(textOpacity)
            .offset(y: textOffset)
            
            Text(page.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(textOpacity)
                .offset(y: textOffset)
            
            Spacer()
        }
        .padding(.horizontal, 60)
        .onChange(of: isActive) { _, newValue in
            if newValue {
                animateIn()
            } else {
                resetAnimation()
            }
        }
        .onAppear {
            if isActive {
                animateIn()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title). \(page.subtitle). \(page.description)")
    }
    
    private func animateIn() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9).delay(0.2)) {
            textOpacity = 1.0
            textOffset = 0
        }
    }
    
    private func resetAnimation() {
        iconScale = 0.5
        iconOpacity = 0
        textOpacity = 0
        textOffset = 20
    }
}

struct AnimatedIcon: View {
    let systemName: String
    let color: Color
    let isActive: Bool
    
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            
            Circle()
                .fill(color.opacity(0.1))
                .scaleEffect(scale * 0.9)
                .opacity(opacity)
            
            Image(systemName: systemName)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(color)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                animateIn()
            } else {
                resetAnimation()
            }
        }
        .onAppear {
            if isActive {
                animateIn()
            }
        }
    }
    
    private func animateIn() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            scale = 1.0
            opacity = 1.0
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.1)) {
            ringScale = 1.0
            ringOpacity = 1.0
        }
    }
    
    private func resetAnimation() {
        scale = 0.5
        opacity = 0
        ringScale = 0.8
        ringOpacity = 0
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
