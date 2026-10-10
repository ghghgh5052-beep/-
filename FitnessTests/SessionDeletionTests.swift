import Foundation
import SwiftData
import XCTest
@testable import Fitness

final class SessionDeletionTests: XCTestCase {
    @MainActor func testDeletesOnlySelectedSessionAndAllItsChildren() throws {
        let context = try makeContext()
        let first = addSession(context, weight: 50), second = addSession(context, weight: 60)
        let plan = WorkoutPlan(name: "خطتي")
        context.insert(plan); context.insert(BodyMetric(weightKg: 75)); context.insert(TrainingProfile())
        try context.save()
        XCTAssertTrue(try SessionDeletionService.delete(sessionID: first.id, context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id), [second.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).map(\.sessionID), [second.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<LoggedSet>()).map(\.weightKg), [60])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutPlan>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetric>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingProfile>()), 1)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor func testRemovingEarlierBestCreatesCorrectRecordsForSurvivingSession() throws {
        let context = try makeContext()
        let best = addSession(context, weight: 100, date: Date(timeIntervalSince1970: 10))
        let later = addSession(context, weight: 80, date: Date(timeIntervalSince1970: 20))
        try context.save(); try PRService.rebuild(context: context)
        XCTAssertFalse(try context.fetch(FetchDescriptor<PersonalRecord>()).contains { $0.sessionID == later.id && $0.kindRaw == "weight" })
        try SessionDeletionService.delete(sessionID: best.id, context: context)
        let records = try context.fetch(FetchDescriptor<PersonalRecord>())
        XCTAssertEqual(records.count, 3)
        XCTAssertTrue(records.allSatisfy { $0.sessionID == later.id })
        XCTAssertEqual(records.first { $0.kindRaw == "weight" }?.value, 80)
        XCTAssertEqual(try SmartTrainingStore.snapshot(context: context).history.map(\.weightKg), [80])
    }

    @MainActor func testDeletingLastSessionLeavesNoPRsOrTrainingHistory() throws {
        let context = try makeContext()
        let session = addSession(context, weight: 100)
        try context.save(); try PRService.rebuild(context: context)
        try SessionDeletionService.delete(sessionID: session.id, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 0)
        XCTAssertTrue(try SmartTrainingStore.snapshot(context: context).history.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 0)
    }

    @MainActor func testFailedCommitRollsBackDeletionAndPRRebuildButPreservesUnrelatedEdits() throws {
        enum Failure: Error { case diskFull }
        let context = try makeContext()
        let session = addSession(context, weight: 80)
        try context.save(); try PRService.rebuild(context: context)
        let original = Set(try context.fetch(FetchDescriptor<PersonalRecord>()).map(\.id))
        context.insert(BodyMetric(weightKg: 77))
        XCTAssertThrowsError(try SessionDeletionService.delete(sessionID: session.id, context: context) { _ in throw Failure.diskFull })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 1)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<PersonalRecord>()).map(\.id)), original)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyMetric>()).first?.weightKg, 77)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor func testDuplicateUUIDSessionsAreRemovedAndRepeatedDeleteIsSafe() throws {
        let context = try makeContext()
        let session = addSession(context, weight: 50)
        context.insert(WorkoutSession(id: session.id, title: "نسخة مكررة", statusRaw: "completed"))
        try context.save()
        XCTAssertTrue(try SessionDeletionService.delete(sessionID: session.id, context: context))
        XCTAssertFalse(try SessionDeletionService.delete(sessionID: session.id, context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 0)
    }

    @MainActor func testDiscardActiveAndPausedSessionsClearsRestStateAndDoesNotRecord() async throws {
        let context = try makeContext()
        let coordinator = WorkoutCoordinator(settings: AppSettings())
        for pause in [false, true] {
            coordinator.start(day: nil, context: context)
            let id = try XCTUnwrap(coordinator.activeSessionID)
            let movement = SessionExercise(sessionID: id, name: "ضغط الصدر")
            context.insert(movement)
            context.insert(LoggedSet(sessionExerciseID: movement.id, weightKg: 80, reps: 10, isCompleted: true))
            try context.save()
            if pause { coordinator.pause(context: context) }
            // Recover a persisted rest deadline without requesting notification permission.
            UserDefaults.standard.set(id.uuidString, forKey: "restSessionID")
            UserDefaults.standard.set(Date.now.addingTimeInterval(90), forKey: "restDeadline")
            if !pause {
                coordinator.recover(context: context)
                XCTAssertNotNil(coordinator.restDeadline)
            }
            let deleted = await coordinator.deleteSession(id: id, context: context)
            XCTAssertTrue(deleted)
            XCTAssertNil(coordinator.activeSessionID)
            XCTAssertNil(coordinator.restDeadline)
            XCTAssertNil(UserDefaults.standard.object(forKey: "restSessionID"))
            XCTAssertNil(UserDefaults.standard.object(forKey: "restDeadline"))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 0)
            coordinator.recover(context: context)
            XCTAssertNil(coordinator.activeSessionID)
        }
    }

    @MainActor func testDeletionPersistsWhenStoreIsReopened() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Deletion.store")
        try autoreleasepool {
            let result = try PersistenceController.makeContainer(storeURL: url)
            let context = ModelContext(result.container)
            let session = addSession(context, weight: 100)
            try context.save(); try PRService.rebuild(context: context)
            try SessionDeletionService.delete(sessionID: session.id, context: context)
        }
        let reopened = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(reopened.container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 0)
    }

    @MainActor private func makeContext() throws -> ModelContext {
        ModelContext(try PersistenceController.makeContainer(inMemory: true).container)
    }

    @MainActor private func addSession(_ context: ModelContext, weight: Double, date: Date = .now) -> WorkoutSession {
        let exerciseID = SeedCatalog.stableID(namespace: 1, code: 1)
        if (try? context.fetchCount(FetchDescriptor<Exercise>())) == 0 {
            context.insert(Exercise(id: exerciseID, name: "ضغط الصدر بالبار"))
        }
        let session = WorkoutSession(start: date, end: date.addingTimeInterval(60), statusRaw: "completed")
        let movement = SessionExercise(sessionID: session.id, exerciseID: exerciseID, name: "ضغط الصدر بالبار")
        context.insert(session); context.insert(movement)
        context.insert(LoggedSet(sessionExerciseID: movement.id, weightKg: weight, reps: 10,
                                 isCompleted: true, completedAt: date))
        return session
    }
}
