import XCTest
@testable import SortyLib

final class SortyPetTests: XCTestCase {
    func testManifestDecodesCodexPetContract() throws {
        let data = """
        {
          "id": "sorty",
          "displayName": "Sorty",
          "description": "A focused Sorty companion.",
          "spritesheetPath": "spritesheet.webp",
          "states": ["idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running", "review"],
          "atlas": {
            "imageName": "spritesheet.webp",
            "cellWidth": 192,
            "cellHeight": 208,
            "framesPerState": 8,
            "framesPerSecond": 8,
            "states": {
              "idle": { "row": 0, "frames": 8 },
              "running-right": { "row": 1, "frames": 8 },
              "running-left": { "row": 2, "frames": 8 },
              "waving": { "row": 3, "frames": 8 },
              "jumping": { "row": 4, "frames": 8 },
              "failed": { "row": 5, "frames": 8 },
              "waiting": { "row": 6, "frames": 8 },
              "running": { "row": 7, "frames": 8 },
              "review": { "row": 8, "frames": 8 }
            }
          }
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(SortyPetManifest.self, from: data)

        XCTAssertEqual(manifest.id, "sorty")
        XCTAssertEqual(manifest.displayName, "Sorty")
        XCTAssertEqual(manifest.spritesheetPath, "spritesheet.webp")
        XCTAssertTrue(manifest.states.contains("running"))
        XCTAssertTrue(manifest.states.contains("review"))
        XCTAssertEqual(manifest.atlas?.imageName, "spritesheet.webp")
        XCTAssertEqual(manifest.atlas?.cellWidth, 192)
        XCTAssertEqual(manifest.atlas?.framesPerState, 8)
        XCTAssertEqual(manifest.atlas?.state(.running)?.row, 7)
        XCTAssertEqual(manifest.atlas?.state(.failed)?.frames, 8)
    }

    func testManifestAllowsStaticOnlyFallbackWhenAtlasIsMissing() throws {
        let data = """
        {
          "id": "sorty",
          "displayName": "Sorty",
          "states": ["idle", "failed"]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(SortyPetManifest.self, from: data)

        XCTAssertNil(manifest.atlas)
        XCTAssertTrue(manifest.states.contains("idle"))
    }

    func testSortyStatesMapOntoCodexAtlasRows() {
        let atlas = SortyPetAtlas(
            imageName: "spritesheet.webp",
            cellWidth: 192,
            cellHeight: 208,
            framesPerState: 8,
            framesPerSecond: 8,
            states: [
                "idle": SortyPetAtlasState(row: 0, frames: 8),
                "waving": SortyPetAtlasState(row: 3, frames: 8),
                "jumping": SortyPetAtlasState(row: 4, frames: 8),
                "failed": SortyPetAtlasState(row: 5, frames: 8),
                "waiting": SortyPetAtlasState(row: 6, frames: 8),
                "running": SortyPetAtlasState(row: 7, frames: 8),
                "review": SortyPetAtlasState(row: 8, frames: 8)
            ]
        )

        XCTAssertEqual(atlas.state(.idle)?.row, 0)
        XCTAssertEqual(atlas.state(.waving)?.row, 3)
        XCTAssertEqual(atlas.state(.jumping)?.row, 4)
        XCTAssertEqual(atlas.state(.failed)?.row, 5)
        XCTAssertEqual(atlas.state(.waiting)?.row, 6)
        XCTAssertEqual(atlas.state(.running)?.row, 7)
        XCTAssertEqual(atlas.state(.review)?.row, 8)
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
