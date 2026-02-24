import XCTest
@testable import SortyLib

final class VisionRecommendationBannerTests: XCTestCase {
    func testBannerShowsEnableVisionActionWhenVisionIsSupportedButDisabled() {
        let state = VisionRecommendationBannerState(
            imageCount: 8,
            isVisionEnabled: false,
            supportsVision: true,
            isDismissed: false
        )

        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.recommendedAction, .enableVision)
    }

    func testBannerShowsSwitchModelActionWhenModelDoesNotSupportVision() {
        let state = VisionRecommendationBannerState(
            imageCount: 3,
            isVisionEnabled: true,
            supportsVision: false,
            isDismissed: false
        )

        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.recommendedAction, .switchModel)
    }

    func testDismissHidesBanner() {
        var state = VisionRecommendationBannerState(
            imageCount: 10,
            isVisionEnabled: false,
            supportsVision: true,
            isDismissed: false
        )

        XCTAssertTrue(state.isVisible)
        state.dismiss()
        XCTAssertFalse(state.isVisible)
    }
}
