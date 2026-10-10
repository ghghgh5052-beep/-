import Foundation
import SwiftData
import XCTest
@testable import Fitness

final class SmartAdjustmentTests: XCTestCase {
    @MainActor
    func testApplyingAdviceChangesOnlyPendingWorkingSetsAndPreservesHistory() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let session = WorkoutSession()
        let exercise = SessionExercise(sessionID: session.id,
            exerciseID: SeedCatalog.stableID(namespace: 1, code: 1))
        let other = SessionExercise(sessionID: session.id)
        context.insert(session); context.insert(exercise); context.insert(other)
        let pending = LoggedSet(sessionExerciseID: exercise.id, weightKg: 40, reps: 8, rpe: 6)
        let completed = LoggedSet(sessionExerciseID: exercise.id, weightKg: 42.5, reps: 9,
            rpe: 8, isCompleted: true)
        let warmup = LoggedSet(sessionExerciseID: exercise.id, weightKg: 20, reps: 12, kindRaw: "warmup")
        let drop = LoggedSet(sessionExerciseID: exercise.id, weightKg: 30, reps: 15, kindRaw: "drop")
        let unrelated = LoggedSet(sessionExerciseID: other.id, weightKg: 15, reps: 10)
        for set in [pending, completed, warmup, drop, unrelated] { context.insert(set) }
        try context.save()
        try SmartWorkoutAdjustments.apply(exercise: exercise, reps: 10, weightKg: 45, context: context)
        XCTAssertEqual(pending.weightKg, 45)
        XCTAssertEqual(pending.reps, 10)
        XCTAssertNil(pending.rpe)
        XCTAssertFalse(pending.isCompleted)
        XCTAssertEqual(completed.weightKg, 42.5)
        XCTAssertEqual(completed.reps, 9)
        XCTAssertEqual(completed.rpe, 8)
        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(warmup.weightKg, 20)
        XCTAssertEqual(warmup.reps, 12)
        XCTAssertEqual(drop.weightKg, 30)
        XCTAssertEqual(drop.reps, 15)
        XCTAssertEqual(unrelated.weightKg, 15)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 5)
    }

    @MainActor
    func testPausedCompletedAndInvalidAdviceCannotMutateSets() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let session = WorkoutSession(statusRaw: "paused")
        let exercise = SessionExercise(sessionID: session.id,
            exerciseID: SeedCatalog.stableID(namespace: 1, code: 1))
        let set = LoggedSet(sessionExerciseID: exercise.id, weightKg: 40, reps: 8)
        context.insert(session); context.insert(exercise); context.insert(set)
        try context.save()
        XCTAssertThrowsError(try SmartWorkoutAdjustments.apply(exercise: exercise, reps: 10, weightKg: 45, context: context))
        session.statusRaw = "completed"
        try context.save()
        XCTAssertThrowsError(try SmartWorkoutAdjustments.apply(exercise: exercise, reps: 10, weightKg: 45, context: context))
        session.statusRaw = "active"
        try context.save()
        for invalid in [Double.nan, .infinity, -1, 2_001, 0] {
            XCTAssertThrowsError(try SmartWorkoutAdjustments.apply(exercise: exercise, reps: 10, weightKg: invalid, context: context))
        }
        XCTAssertThrowsError(try SmartWorkoutAdjustments.apply(exercise: exercise, reps: 0, weightKg: 45, context: context))
        XCTAssertEqual(set.weightKg, 40)
        XCTAssertEqual(set.reps, 8)
        set.isCompleted = true
        try context.save()
        XCTAssertThrowsError(try SmartWorkoutAdjustments.apply(exercise: exercise, reps: 10, weightKg: 45, context: context))
        XCTAssertEqual(set.weightKg, 40)
    }

    @MainActor
    func testBodyweightAdviceCanClearAnAdditionalLoadAndNilDoesNotInventOne() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let session = WorkoutSession()
        let exercise = SessionExercise(sessionID: session.id,
            exerciseID: SeedCatalog.stableID(namespace: 1, code: 8))
        let set = LoggedSet(sessionExerciseID: exercise.id, weightKg: 10, reps: 8)
        context.insert(session); context.insert(exercise); context.insert(set)
        try context.save()
        try SmartWorkoutAdjustments.apply(exercise: exercise, reps: 10, weightKg: nil, context: context)
        XCTAssertEqual(set.weightKg, 10)
        XCTAssertEqual(set.reps, 10)
        try SmartWorkoutAdjustments.apply(exercise: exercise, reps: 12, weightKg: 0, context: context)
        XCTAssertEqual(set.weightKg, 0)
        XCTAssertEqual(set.reps, 12)
    }
}
