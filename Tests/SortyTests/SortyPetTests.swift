import XCTest
@testable import SortyLib

final class SortyPetTests: XCTestCase {
    func testManifestDecodesSortySpecificStates() throws {
        let data = """
        {
          "id": "sorty",
          "displayName": "Sorty",
          "version": 1,
          "states": ["ready", "organizing", "renaming", "duplicates", "failed"],
          "atlas": {
            "imageName": "spritesheet.png",
            "cellWidth": 192,
            "cellHeight": 208,
            "framesPerState": 6,
            "framesPerSecond": 8,
            "states": {
              "ready": { "row": 1, "frames": 6 },
              "organizing": { "row": 2, "frames": 6 },
              "renaming": { "row": 3, "frames": 6 },
              "duplicates": { "row": 5, "frames": 6 },
              "failed": { "row": 9, "frames": 6 }
            }
          }
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(SortyPetManifest.self, from: data)

        XCTAssertEqual(manifest.id, "sorty")
        XCTAssertEqual(manifest.displayName, "Sorty")
        XCTAssertTrue(manifest.states.contains(.renaming))
        XCTAssertTrue(manifest.states.contains(.duplicates))
        XCTAssertEqual(manifest.atlas?.imageName, "spritesheet.png")
        XCTAssertEqual(manifest.atlas?.cellWidth, 192)
        XCTAssertEqual(manifest.atlas?.state(.renaming)?.row, 3)
        XCTAssertEqual(manifest.atlas?.state(.failed)?.frames, 6)
        XCTAssertNil(manifest.atlas?.state(.completed))
    }

    func testManifestAllowsStaticOnlyFallbackWhenAtlasIsMissing() throws {
        let data = """
        {
          "id": "sorty",
          "displayName": "Sorty",
          "version": 1,
          "states": ["ready", "failed"]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(SortyPetManifest.self, from: data)

        XCTAssertNil(manifest.atlas)
        XCTAssertTrue(manifest.states.contains(.ready))
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
