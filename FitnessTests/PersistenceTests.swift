import Foundation
import SwiftData
import XCTest
@testable import Fitness

final class PersistenceTests: XCTestCase {
    @MainActor
    func testMigrationPreservesUUIDReferencesAndSessionData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Migration.store")
        let exerciseID = UUID(), sessionID = UUID(), sessionExerciseID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: FitnessSchemaV1.self)
            let configuration = ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(Exercise(id: exerciseID, name: "القرفصاء بالبار"))
            context.insert(WorkoutSession(id: sessionID, title: "الأرجل", notes: "محفوظ", statusRaw: "completed"))
            context.insert(SessionExercise(id: sessionExerciseID, sessionID: sessionID, exerciseID: exerciseID,
                                           name: "القرفصاء بالبار"))
            context.insert(LoggedSet(sessionExerciseID: sessionExerciseID, weightKg: 100, reps: 5,
                                     isCompleted: true))
            context.insert(BodyMetric(weightKg: 75.2, waistCm: 80))
            try context.save()
        }
        let result = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(result.container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).first?.id, exerciseID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.notes, "محفوظ")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).first?.sessionID, sessionID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LoggedSet>()).first?.weightKg, 100)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyMetric>()).first?.weightKg, 75.2)
        context.insert(PersonalRecord(exerciseID: exerciseID, kindRaw: "weight", value: 100))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 1)
    }

    @MainActor
    func testConflictsRetainCompleteNewestRecordAndOneSettingsSingleton() throws {
        let result = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(result.container)
        let id = UUID()
        context.insert(Exercise(id: id, name: "قديم", notes: "قديم", updatedAt: Date(timeIntervalSince1970: 10)))
        context.insert(Exercise(id: id, name: "جديد", primaryMuscleRaw: "ظهر", notes: "ملاحظات كاملة",
                                isFavorite: true, updatedAt: Date(timeIntervalSince1970: 20)))
        context.insert(UserPreferences(weightUnit: "kg", updatedAt: Date(timeIntervalSince1970: 10)))
        context.insert(UserPreferences(weightUnit: "lb", updatedAt: Date(timeIntervalSince1970: 20)))
        try context.save()
        XCTAssertEqual(try PersistenceController.reconcile(context: context), 2)
        let survivor = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first)
        XCTAssertEqual(survivor.name, "جديد")
        XCTAssertEqual(survivor.notes, "ملاحظات كاملة")
        XCTAssertEqual(survivor.primaryMuscleRaw, "ظهر")
        XCTAssertTrue(survivor.isFavorite)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserPreferences>()).first?.weightUnit, "lb")
        XCTAssertEqual(try PersistenceController.reconcile(context: context), 0)
    }

    @MainActor
    func testSeedIDsAreStableAndSeedingPreservesEdits() throws {
        let result = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(result.container)
        let suite = "FitnessTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try SeedCatalog.seedIfNeeded(context: context, defaults: defaults)
        XCTAssertGreaterThanOrEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 50)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutPlan>()), 3)
        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first)
        exercise.notes = "عدّلت هذا التمرين"
        exercise.updatedAt = Date()
        try context.save()
        let count = try context.fetchCount(FetchDescriptor<Exercise>())
        defaults.removeObject(forKey: "fitness.catalog.seeded.v1")
        try SeedCatalog.seedIfNeeded(context: context, defaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), count)
        XCTAssertEqual(exercise.notes, "عدّلت هذا التمرين")
        XCTAssertEqual(SeedCatalog.stableID(namespace: 1, code: 1), SeedCatalog.stableID(namespace: 1, code: 1))
        for entry in SeedCatalog.entries {
            XCTAssertNil(entry.name.range(of: "[A-Za-z]", options: .regularExpression))
        }
    }

    @MainActor
    func testPRHistoryRebuildIsIdempotentAndIgnoresUnfinishedWorkouts() throws {
        let result = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(result.container)
        let exercise = Exercise(name: "ضغط الصدر")
        let completed = WorkoutSession(statusRaw: "completed")
        let active = WorkoutSession()
        let completedExercise = SessionExercise(sessionID: completed.id, exerciseID: exercise.id)
        let activeExercise = SessionExercise(sessionID: active.id, exerciseID: exercise.id)
        context.insert(exercise); context.insert(completed); context.insert(active)
        context.insert(completedExercise); context.insert(activeExercise)
        context.insert(LoggedSet(sessionExerciseID: completedExercise.id, weightKg: 100, reps: 5,
                                isCompleted: true, completedAt: Date(timeIntervalSince1970: 10)))
        context.insert(LoggedSet(sessionExerciseID: activeExercise.id, weightKg: 200, reps: 5,
                                isCompleted: true, completedAt: Date(timeIntervalSince1970: 20)))
        try context.save()
        XCTAssertEqual(try PRService.rebuild(context: context), 3)
        let ids = Set(try context.fetch(FetchDescriptor<PersonalRecord>()).map(\.id))
        XCTAssertEqual(try PRService.rebuild(context: context), 3)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<PersonalRecord>()).map(\.id)), ids)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersonalRecord>()).first { $0.kindRaw == "weight" }?.value, 100)
    }

    @MainActor
    func testCloudFallbackHasVisibleWarningWithoutReplacingStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Local.store")
        try autoreleasepool {
            let local = try PersistenceController.makeContainer(storeURL: url)
            let context = ModelContext(local.container)
            context.insert(BodyMetric(weightKg: 77))
            try context.save()
        }
        let fallback = try PersistenceController.makeContainer(useCloudKit: true, storeURL: url,
                                                               cloudKitContainerIdentifier: "")
        XCTAssertEqual(fallback.syncMode, .local)
        XCTAssertNotNil(fallback.warning)
        XCTAssertEqual(try ModelContext(fallback.container).fetch(FetchDescriptor<BodyMetric>()).first?.weightKg, 77)
    }
}
