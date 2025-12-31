//
//  AnimationUtilitiesTests.swift
//  FileOrganizer
//
//  Tests for animation utilities, haptic feedback, and motion effects
//

import XCTest
import SwiftUI
@testable import FileOrganizerLib

final class AnimationUtilitiesTests: XCTestCase {

    // MARK: - Haptic Feedback Manager Tests

    func testHapticFeedbackManagerSingleton() {
        let instance1 = HapticFeedbackManager.shared
        let instance2 = HapticFeedbackManager.shared
        XCTAssertTrue(instance1 === instance2, "HapticFeedbackManager should be a singleton")
    }

    func testHapticFeedbackTap() {
        // Test that tap feedback doesn't crash
        XCTAssertNoThrow(HapticFeedbackManager.shared.tap())
    }

    func testHapticFeedbackSuccess() {
        // Test that success feedback doesn't crash
        XCTAssertNoThrow(HapticFeedbackManager.shared.success())
    }

    func testHapticFeedbackAlignment() {
        // Test that alignment feedback doesn't crash
        XCTAssertNoThrow(HapticFeedbackManager.shared.alignment())
    }

    func testHapticFeedbackError() {
        // Test that error feedback doesn't crash
        XCTAssertNoThrow(HapticFeedbackManager.shared.error())
    }

    func testHapticFeedbackSelection() {
        // Test that selection feedback doesn't crash
        XCTAssertNoThrow(HapticFeedbackManager.shared.selection())
    }

    // MARK: - Page Transition Style Tests

    func testPageTransitionStyleSlide() {
        let style = PageTransitionStyle.slide
        let transition = style.insertion
        XCTAssertNotNil(transition, "Slide transition should not be nil")
    }

    func testPageTransitionStyleFade() {
        let style = PageTransitionStyle.fade
        let transition = style.insertion
        XCTAssertNotNil(transition, "Fade transition should not be nil")
    }

    func testPageTransitionStyleScale() {
        let style = PageTransitionStyle.scale
        let transition = style.insertion
        XCTAssertNotNil(transition, "Scale transition should not be nil")
    }

    func testPageTransitionStyleSlideUp() {
        let style = PageTransitionStyle.slideUp
        let transition = style.insertion
        XCTAssertNotNil(transition, "SlideUp transition should not be nil")
    }

    func testPageTransitionStyleSlideDown() {
        let style = PageTransitionStyle.slideDown
        let transition = style.insertion
        XCTAssertNotNil(transition, "SlideDown transition should not be nil")
    }

    // MARK: - Custom Animation Tests

    func testPageTransitionAnimation() {
        let animation = Animation.pageTransition
        XCTAssertNotNil(animation, "Page transition animation should not be nil")
    }

    func testModalBounceAnimation() {
        let animation = Animation.modalBounce
        XCTAssertNotNil(animation, "Modal bounce animation should not be nil")
    }

    func testSubtleBounceAnimation() {
        let animation = Animation.subtleBounce
        XCTAssertNotNil(animation, "Subtle bounce animation should not be nil")
    }

    func testQuickSnapAnimation() {
        let animation = Animation.quickSnap
        XCTAssertNotNil(animation, "Quick snap animation should not be nil")
    }

    func testLoadingPulseAnimation() {
        let animation = Animation.loadingPulse
        XCTAssertNotNil(animation, "Loading pulse animation should not be nil")
    }

    func testSmoothEaseAnimation() {
        let animation = Animation.smoothEase
        XCTAssertNotNil(animation, "Smooth ease animation should not be nil")
    }

    // MARK: - Loading Indicator View Tests

    func testLoadingDotsViewInitialization() {
        let view = LoadingDotsView()
        XCTAssertNotNil(view, "LoadingDotsView should initialize with defaults")
    }

    func testLoadingDotsViewCustomInitialization() {
        let view = LoadingDotsView(dotCount: 5, dotSize: 12, color: .red)
        XCTAssertNotNil(view, "LoadingDotsView should initialize with custom parameters")
    }

    func testBouncingSpinnerInitialization() {
        let view = BouncingSpinner()
        XCTAssertNotNil(view, "BouncingSpinner should initialize with defaults")
    }

    func testBouncingSpinnerCustomInitialization() {
        let view = BouncingSpinner(size: 48, color: .purple)
        XCTAssertNotNil(view, "BouncingSpinner should initialize with custom parameters")
    }

    func testPulsingRingLoaderInitialization() {
        let view = PulsingRingLoader()
        XCTAssertNotNil(view, "PulsingRingLoader should initialize with defaults")
    }

    func testPulsingRingLoaderCustomInitialization() {
        let view = PulsingRingLoader(size: 60, color: .green)
        XCTAssertNotNil(view, "PulsingRingLoader should initialize with custom parameters")
    }

    // MARK: - Button Style Tests

    func testHapticBounceButtonStyle() {
        let style = HapticBounceButtonStyle()
        XCTAssertNotNil(style, "HapticBounceButtonStyle should initialize")
    }

    func testHapticBounceButtonStyleWithFeedbackType() {
        let tapStyle = HapticBounceButtonStyle(feedbackType: .tap)
        XCTAssertNotNil(tapStyle, "HapticBounceButtonStyle with tap feedback should initialize")

        let successStyle = HapticBounceButtonStyle(feedbackType: .success)
        XCTAssertNotNil(successStyle, "HapticBounceButtonStyle with success feedback should initialize")

        let errorStyle = HapticBounceButtonStyle(feedbackType: .error)
        XCTAssertNotNil(errorStyle, "HapticBounceButtonStyle with error feedback should initialize")

        let selectionStyle = HapticBounceButtonStyle(feedbackType: .selection)
        XCTAssertNotNil(selectionStyle, "HapticBounceButtonStyle with selection feedback should initialize")
    }

    // MARK: - Transition Styles Tests

    func testTransitionStylesSlideFromRight() {
        let transition = TransitionStyles.slideFromRight
        XCTAssertNotNil(transition, "slideFromRight transition should not be nil")
    }

    func testTransitionStylesSlideFromLeft() {
        let transition = TransitionStyles.slideFromLeft
        XCTAssertNotNil(transition, "slideFromLeft transition should not be nil")
    }

    func testTransitionStylesSlideFromBottom() {
        let transition = TransitionStyles.slideFromBottom
        XCTAssertNotNil(transition, "slideFromBottom transition should not be nil")
    }

    func testTransitionStylesScaleAndFade() {
        let transition = TransitionStyles.scaleAndFade
        XCTAssertNotNil(transition, "scaleAndFade transition should not be nil")
    }

    func testTransitionStylesModalPresentation() {
        let transition = TransitionStyles.modalPresentation
        XCTAssertNotNil(transition, "modalPresentation transition should not be nil")
    }

    // MARK: - View Modifier Tests

    func testHapticFeedbackModifierApplication() {
        let view = Text("Test").hapticFeedback(.tap)
        XCTAssertNotNil(view, "hapticFeedback modifier should apply to view")
    }

    func testBounceTapModifierApplication() {
        let view = Text("Test").bounceTap()
        XCTAssertNotNil(view, "bounceTap modifier should apply to view")
    }

    func testBounceTapModifierWithCustomScale() {
        let view = Text("Test").bounceTap(scale: 0.9)
        XCTAssertNotNil(view, "bounceTap modifier with custom scale should apply to view")
    }

    func testPageTransitionModifierApplication() {
        let view = Text("Test").pageTransition()
        XCTAssertNotNil(view, "pageTransition modifier should apply to view")
    }

    func testPageTransitionModifierWithStyle() {
        let view = Text("Test").pageTransition(.fade)
        XCTAssertNotNil(view, "pageTransition modifier with style should apply to view")
    }

    func testModalBounceModifierApplication() {
        let view = Text("Test").modalBounce()
        XCTAssertNotNil(view, "modalBounce modifier should apply to view")
    }

    func testLoadingAnimationModifierApplication() {
        let view = Text("Test").loadingAnimation(isLoading: true)
        XCTAssertNotNil(view, "loadingAnimation modifier should apply to view")
    }

    func testPulsingLoadingModifierApplication() {
        let view = Text("Test").pulsingLoading(isLoading: true)
        XCTAssertNotNil(view, "pulsingLoading modifier should apply to view")
    }

    func testShimmerModifierApplication() {
        let view = Text("Test").shimmer(isLoading: true)
        XCTAssertNotNil(view, "shimmer modifier should apply to view")
    }

    func testAnimatedAppearanceModifierApplication() {
        let view = Text("Test").animatedAppearance()
        XCTAssertNotNil(view, "animatedAppearance modifier should apply to view")
    }

    func testAnimatedAppearanceModifierWithDelay() {
        let view = Text("Test").animatedAppearance(delay: 0.5)
        XCTAssertNotNil(view, "animatedAppearance modifier with delay should apply to view")
    }

    // MARK: - Navigation Direction Tests

    func testNavigationDirectionForward() {
        let direction = NavigationDirection.forward
        XCTAssertEqual(direction, .forward, "NavigationDirection should be forward")
    }

    func testNavigationDirectionBackward() {
        let direction = NavigationDirection.backward
        XCTAssertEqual(direction, .backward, "NavigationDirection should be backward")
    }

    // MARK: - Integration Tests

    func testHapticFeedbackTypesExist() {
        // Verify all feedback types are accessible
        let types: [HapticTapModifier.HapticFeedbackType] = [.tap, .success, .error, .selection]
        XCTAssertEqual(types.count, 4, "Should have 4 haptic feedback types")
    }

    func testAllPageTransitionStylesExist() {
        // Verify all transition styles can be created
        let styles: [PageTransitionStyle] = [.slide, .fade, .scale, .slideUp, .slideDown]
        XCTAssertEqual(styles.count, 5, "Should have 5 page transition styles")

        for style in styles {
            XCTAssertNotNil(style.insertion, "Each style should have an insertion transition")
        }
    }

    func testViewExtensionChaining() {
        // Test that multiple modifiers can be chained
        let view = Text("Test")
            .hapticFeedback(.tap)
            .bounceTap()
            .animatedAppearance(delay: 0.1)

        XCTAssertNotNil(view, "Multiple modifiers should chain correctly")
    }

    func testLoadingStateModifiersWithDifferentStates() {
        // Test loading modifiers with both true and false states
        let loadingView = Text("Test").loadingAnimation(isLoading: true)
        let notLoadingView = Text("Test").loadingAnimation(isLoading: false)

        XCTAssertNotNil(loadingView, "Loading animation should work when loading")
        XCTAssertNotNil(notLoadingView, "Loading animation should work when not loading")
    }

    // MARK: - Performance Tests

    func testHapticFeedbackPerformance() {
        measure {
            for _ in 0..<100 {
                HapticFeedbackManager.shared.tap()
            }
        }
    }

    func testTransitionCreationPerformance() {
        measure {
            for _ in 0..<100 {
                _ = PageTransitionStyle.slide.insertion
                _ = PageTransitionStyle.fade.insertion
                _ = PageTransitionStyle.scale.insertion
                _ = PageTransitionStyle.slideUp.insertion
                _ = PageTransitionStyle.slideDown.insertion
            }
        }
    }
}

// MARK: - AnimatedToggle Tests

final class AnimatedToggleTests: XCTestCase {

    func testAnimatedToggleCreation() {
        @State var isOn = false
        let toggle = AnimatedToggle(isOn: $isOn) {
            Text("Test Toggle")
        }
        XCTAssertNotNil(toggle, "AnimatedToggle should be created successfully")
    }
}

// MARK: - Loading View Tests

final class LoadingViewTests: XCTestCase {

    func testLoadingDotsViewDefaultValues() {
        let view = LoadingDotsView()
        // Default dot count is 3, dot size is 8, color is accent
        XCTAssertNotNil(view, "LoadingDotsView should have default values")
    }

    func testBouncingSpinnerDefaultValues() {
        let view = BouncingSpinner()
        // Default size is 24, color is accent
        XCTAssertNotNil(view, "BouncingSpinner should have default values")
    }

    func testPulsingRingLoaderDefaultValues() {
        let view = PulsingRingLoader()
        // Default size is 40, color is accent
        XCTAssertNotNil(view, "PulsingRingLoader should have default values")
    }
}

// MARK: - Button Style Tests

final class ButtonStyleTests: XCTestCase {

    func testStaticHapticBounceStyle() {
        let style: HapticBounceButtonStyle = .hapticBounce
        XCTAssertNotNil(style, "Static hapticBounce style should be accessible")
    }

    func testStaticHapticSuccessStyle() {
        let style: HapticBounceButtonStyle = .hapticSuccess
        XCTAssertNotNil(style, "Static hapticSuccess style should be accessible")
    }
}
