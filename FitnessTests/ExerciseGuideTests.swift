import UIKit
import XCTest
@testable import Fitness

final class ExerciseGuideTests: XCTestCase {
    @MainActor
    func testEveryBuiltInExerciseHasArabicInstructionsAndLoadableOfflineImages() throws {
        XCTAssertEqual(SeedCatalog.entries.count, 66)
        for entry in SeedCatalog.entries {
            let id = SeedCatalog.stableID(namespace: 1, code: entry.code)
            let guide = try XCTUnwrap(ExerciseGuides.guide(for: id), "Missing guide for exercise \(entry.code)")
            XCTAssertEqual(guide.id, id)
            XCTAssertFalse(guide.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertNotNil(guide.caption.range(of: "\\p{Arabic}", options: .regularExpression))
            XCTAssertNil(guide.caption.range(of: "[A-Za-z]", options: .regularExpression))
            XCTAssertEqual(guide.assetNames, [String(format: "exercise_%03d", entry.code)],
                           "Each exercise must resolve its single start/end illustration canvas")
            for assetName in guide.assetNames {
                XCTAssertFalse(assetName.isEmpty)
                let image = try XCTUnwrap(UIImage(named: assetName, in: .main, compatibleWith: nil),
                                          "Missing offline asset \(assetName) for exercise \(entry.code)")
                XCTAssertGreaterThan(image.size.width, 0)
                XCTAssertGreaterThan(image.size.height, 0)
            }
        }
    }

    @MainActor
    func testUnknownAndCustomExercisesDoNotReceiveUnrelatedBuiltInImages() {
        let unknownID = SeedCatalog.stableID(namespace: 99, code: 1)
        XCTAssertNil(ExerciseGuides.guide(for: unknownID))
        let custom = Exercise(name: "تمرين خاص", isCustom: true)
        XCTAssertNil(ExerciseGuides.guide(for: custom.id))
    }

    @MainActor
    func testRenamingABuiltInExercisePreservesItsOriginalGuideImages() throws {
        let id = SeedCatalog.stableID(namespace: 1, code: 1)
        let exercise = Exercise(id: id, name: "ضغط الصدر بالبار")
        let original = try XCTUnwrap(ExerciseGuides.guide(for: exercise.id))
        exercise.name = "تمرين الصدر المفضل"
        let renamed = try XCTUnwrap(ExerciseGuides.guide(for: exercise.id))
        XCTAssertEqual(exercise.name, "تمرين الصدر المفضل")
        XCTAssertEqual(renamed.id, original.id)
        XCTAssertEqual(renamed.assetNames, original.assetNames)
        XCTAssertEqual(renamed.caption, original.caption)
    }
}
