import XCTest
@testable import SortyLib

final class SortyPetTests: XCTestCase {
    func testManifestDecodesSortySpecificStates() throws {
        let data = """
        {
          "id": "sorty",
          "displayName": "Sorty",
          "version": 1,
          "states": ["ready", "organizing", "renaming", "duplicates", "failed"]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(SortyPetManifest.self, from: data)

        XCTAssertEqual(manifest.id, "sorty")
        XCTAssertEqual(manifest.displayName, "Sorty")
        XCTAssertTrue(manifest.states.contains(.renaming))
        XCTAssertTrue(manifest.states.contains(.duplicates))
    }

    func testOrganizationStateMappingUsesModeSpecificAnimations() {
        XCTAssertEqual(SortyPetAnimationState.organizationState(.idle, mode: .organize), .ready)
        XCTAssertEqual(SortyPetAnimationState.organizationState(.idle, mode: .renameOnly), .renaming)
        XCTAssertEqual(SortyPetAnimationState.organizationState(.organizing, mode: .organize), .organizing)
        XCTAssertEqual(SortyPetAnimationState.organizationState(.organizing, mode: .renameOnly), .renaming)
        XCTAssertEqual(SortyPetAnimationState.organizationState(.applying, mode: .organizeAndRename), .applying)
    }

    func testDuplicateStateMappingUsesDuplicateAnimation() {
        XCTAssertEqual(SortyPetAnimationState.duplicateState(.idle), .ready)
        XCTAssertEqual(SortyPetAnimationState.duplicateState(.preparing), .duplicates)
        XCTAssertEqual(SortyPetAnimationState.duplicateState(.scanning(progress: 0.4)), .duplicates)
        XCTAssertEqual(SortyPetAnimationState.duplicateState(.completed(count: 2)), .completed)
        XCTAssertEqual(SortyPetAnimationState.duplicateState(.failed("No access")), .failed)
    }
}
