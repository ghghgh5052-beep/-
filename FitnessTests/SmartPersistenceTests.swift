import Foundation
import SwiftData
import XCTest
@testable import Fitness

final class SmartPersistenceTests: XCTestCase {
    @MainActor
    func testV2DiskMigrationPreservesHistoryUUIDsAndPersonalRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Fitness.store")
        let exerciseID = SeedCatalog.stableID(namespace: 1, code: 1)
        let sessionID = UUID(), movementID = UUID(), setID = UUID(), recordID = UUID(), metricID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try autoreleasepool {
            let schema = Schema(versionedSchema: FitnessSchemaV2.self)
            let configuration = ModelConfiguration("Fitness", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(Exercise(id: exerciseID, name: "ضغط الصدر بالبار", notes: "ملاحظاتي"))
            context.insert(WorkoutSession(id: sessionID, title: "جلسة محفوظة", start: date,
                end: date.addingTimeInterval(600), notes: "سجل قديم", statusRaw: "completed"))
            context.insert(SessionExercise(id: movementID, sessionID: sessionID,
                exerciseID: exerciseID, name: "ضغط الصدر بالبار"))
            context.insert(LoggedSet(id: setID, sessionExerciseID: movementID, weightKg: 60, reps: 8,
                rpe: 8, isCompleted: true, completedAt: date.addingTimeInterval(120)))
            context.insert(PersonalRecord(id: recordID, exerciseID: exerciseID, sessionID: sessionID,
                setID: setID, kindRaw: "weight", value: 60, weightKg: 60, achievedAt: date))
            context.insert(BodyMetric(id: metricID, date: date, weightKg: 81.5, waistCm: 84))
            try context.save()
        }
        let migrated = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(migrated.container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).first?.id, exerciseID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).first?.notes, "ملاحظاتي")
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.id, sessionID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.notes, "سجل قديم")
        let movement = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first)
        XCTAssertEqual(movement.id, movementID)
        XCTAssertEqual(movement.sessionID, sessionID)
        XCTAssertEqual(movement.exerciseID, exerciseID)
        let set = try XCTUnwrap(context.fetch(FetchDescriptor<LoggedSet>()).first)
        XCTAssertEqual(set.id, setID)
        XCTAssertEqual(set.sessionExerciseID, movementID)
        XCTAssertEqual(set.weightKg, 60)
        XCTAssertEqual(set.rpe, 8)
        let record = try XCTUnwrap(context.fetch(FetchDescriptor<PersonalRecord>()).first)
        XCTAssertEqual(record.id, recordID)
        XCTAssertEqual(record.sessionID, sessionID)
        XCTAssertEqual(record.setID, setID)
        XCTAssertEqual(record.value, 60)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BodyMetric>()).first?.id, metricID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingProfile>()), 0)
        XCTAssertEqual(try SmartTrainingStore.loadPreferences(context: context).durationMinutes, 45)
        try SmartTrainingStore.savePreferences(TrainingPreferences(goal: .strength, level: .intermediate,
            equipment: [.bodyweight, .barbell, .bench, .rack], durationMinutes: 60, incrementKg: 1.25), context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingProfile>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersonalRecord>()).first?.id, recordID)
        XCTAssertEqual(try SmartTrainingStore.snapshot(context: context).history.first?.sessionID, sessionID)
    }

    @MainActor
    func testTrainingProfileBackupRoundTripAndLegacyImportPreservePreferences() throws {
        let source = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(source)
        try SmartTrainingStore.savePreferences(TrainingPreferences(goal: .fitness, level: .advanced,
            equipment: [.bodyweight, .dumbbell, .bench], durationMinutes: 30, incrementKg: 0.5), context: context)
        let data = try BackupService.encode(context: context)
        let backup = try BackupService.decode(data)
        XCTAssertEqual(backup.formatVersion, 2)
        XCTAssertEqual(backup.trainingProfiles.count, 1)
        let destination = try PersistenceController.makeContainer(inMemory: true).container
        let visible = ModelContext(destination)
        visible.insert(TrainingProfile(goalRaw: "strength", updatedAt: Date(timeIntervalSince1970: 1)))
        try visible.save()
        try BackupService.merge(backup, context: visible)
        try BackupService.merge(backup, context: visible)
        let restored = try SmartTrainingStore.loadPreferences(context: visible)
        XCTAssertEqual(restored.goal, .fitness)
        XCTAssertEqual(restored.level, .advanced)
        XCTAssertEqual(restored.equipment, [.bodyweight, .dumbbell, .bench])
        XCTAssertEqual(restored.durationMinutes, 30)
        XCTAssertEqual(restored.incrementKg, 0.5)
        XCTAssertEqual(try visible.fetchCount(FetchDescriptor<TrainingProfile>()), 1)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy["formatVersion"] = 1
        legacy.removeValue(forKey: "trainingProfiles")
        let oldBackup = try BackupService.decode(JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(oldBackup.trainingProfiles.isEmpty)
        try BackupService.merge(oldBackup, context: visible)
        XCTAssertEqual(try SmartTrainingStore.loadPreferences(context: visible).goal, .fitness)
        XCTAssertEqual(try visible.fetchCount(FetchDescriptor<TrainingProfile>()), 1)
    }

    @MainActor
    func testInvalidProfileRejectsImportBeforeMutatingExistingData() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        context.insert(BodyMetric(weightKg: 80))
        try SmartTrainingStore.savePreferences(TrainingPreferences(), context: context)
        let before = try BackupService.envelope(context: context)
        var invalid = before
        invalid.trainingProfiles[0].durationMinutes = 5
        XCTAssertThrowsError(try BackupService.merge(invalid, context: context))
        invalid = before
        invalid.trainingProfiles[0].equipmentRaw = "unknown-machine"
        XCTAssertThrowsError(try BackupService.merge(invalid, context: context))
        invalid = before
        invalid.trainingProfiles[0].incrementKg = 11
        XCTAssertThrowsError(try BackupService.merge(invalid, context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyMetric>()), 1)
        XCTAssertEqual(try SmartTrainingStore.loadPreferences(context: context).durationMinutes, 45)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingProfile>()), 1)
    }

    @MainActor
    func testProfileConflictKeepsNewestCompleteSingleton() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        context.insert(TrainingProfile(goalRaw: "strength", durationMinutes: 30,
            updatedAt: Date(timeIntervalSince1970: 10)))
        context.insert(TrainingProfile(goalRaw: "fitness", levelRaw: "advanced", equipmentRaw: "bodyweight,dumbbell",
            durationMinutes: 60, incrementKg: 0.5, updatedAt: Date(timeIntervalSince1970: 20)))
        try context.save()
        XCTAssertEqual(try PersistenceController.reconcile(context: context), 1)
        let preferences = try SmartTrainingStore.loadPreferences(context: context)
        XCTAssertEqual(preferences.goal, .fitness)
        XCTAssertEqual(preferences.level, .advanced)
        XCTAssertEqual(preferences.equipment, [.bodyweight, .dumbbell])
        XCTAssertEqual(preferences.durationMinutes, 60)
        XCTAssertEqual(preferences.incrementKg, 0.5)
        XCTAssertEqual(try PersistenceController.reconcile(context: context), 0)
    }

    @MainActor
    func testSnapshotExcludesUnfinishedWarmupInvalidAndCustomHistoryButRetainsArchivedRecovery() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let bench = Exercise(id: SeedCatalog.stableID(namespace: 1, code: 1), name: "ضغط الصدر")
        let squat = Exercise(id: SeedCatalog.stableID(namespace: 1, code: 29), name: "القرفصاء", isArchived: true)
        let custom = Exercise(name: "تمرين مخصص", isCustom: true)
        context.insert(bench); context.insert(squat); context.insert(custom)
        let finished = WorkoutSession(statusRaw: "completed")
        let active = WorkoutSession()
        let paused = WorkoutSession(statusRaw: "paused")
        context.insert(finished); context.insert(active); context.insert(paused)
        let validMovement = SessionExercise(sessionID: finished.id, exerciseID: bench.id)
        let archivedMovement = SessionExercise(sessionID: finished.id, exerciseID: squat.id)
        let customMovement = SessionExercise(sessionID: finished.id, exerciseID: custom.id)
        let activeMovement = SessionExercise(sessionID: active.id, exerciseID: bench.id)
        let pausedMovement = SessionExercise(sessionID: paused.id, exerciseID: bench.id)
        for movement in [validMovement, archivedMovement, customMovement, activeMovement, pausedMovement] {
            context.insert(movement)
        }
        context.insert(LoggedSet(sessionExerciseID: validMovement.id, weightKg: 40, reps: 10, isCompleted: true))
        context.insert(LoggedSet(sessionExerciseID: validMovement.id, weightKg: 20, reps: 10, kindRaw: "warmup", isCompleted: true))
        context.insert(LoggedSet(sessionExerciseID: validMovement.id, weightKg: 100, reps: 10, isCompleted: false))
        context.insert(LoggedSet(sessionExerciseID: validMovement.id, weightKg: -1, reps: 10, isCompleted: true))
        context.insert(LoggedSet(sessionExerciseID: validMovement.id, weightKg: 40, reps: 0, isCompleted: true))
        context.insert(LoggedSet(sessionExerciseID: validMovement.id, weightKg: 40, reps: 10, rpe: 11, isCompleted: true))
        context.insert(LoggedSet(sessionExerciseID: archivedMovement.id, weightKg: 60, reps: 8, isCompleted: true))
        context.insert(LoggedSet(sessionExerciseID: customMovement.id, weightKg: 70, reps: 10, isCompleted: true))
        context.insert(LoggedSet(sessionExerciseID: activeMovement.id, weightKg: 200, reps: 10, isCompleted: true))
        context.insert(LoggedSet(sessionExerciseID: pausedMovement.id, weightKg: 200, reps: 10, isCompleted: true))
        try context.save()
        let snapshot = try SmartTrainingStore.snapshot(context: context)
        XCTAssertEqual(snapshot.exercises.map(\.id), [bench.id])
        XCTAssertEqual(Set(snapshot.recoveryExercises.map(\.id)), [bench.id, squat.id])
        XCTAssertEqual(snapshot.unsupportedExerciseCount, 1)
        XCTAssertEqual(snapshot.history.count, 2)
        XCTAssertEqual(Set(snapshot.history.map(\.exerciseID)), [bench.id, squat.id])
        XCTAssertTrue(snapshot.history.allSatisfy { $0.sessionID == finished.id && $0.isCompleted })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 3)
    }

    @MainActor
    func testGeneratedPreviewDoesNotPersistUntilStartAndSurvivesReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Fitness.store")
        let exerciseID = SeedCatalog.stableID(namespace: 1, code: 1)
        let sessionID: UUID = try autoreleasepool {
            let container = try PersistenceController.makeContainer(storeURL: url).container
            let context = ModelContext(container)
            context.insert(Exercise(id: exerciseID, name: "ضغط الصدر بالبار"))
            try context.save()
            let snapshot = try SmartTrainingStore.snapshot(context: context)
            _ = SmartTrainingEngine.generate(exercises: snapshot.exercises,
                preferences: TrainingPreferences(equipment: [.bodyweight, .barbell, .bench, .rack]),
                history: snapshot.history, now: .now)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
            let preview = SmartWorkoutPreview(exercises: [TrainingPrescription(exerciseID: exerciseID,
                name: "ضغط الصدر بالبار", sets: 3, reps: 8, weightKg: 42.5, restSeconds: 120,
                reason: "زيادة تدريجية حسب الجولات المكتملة", mode: .reps)], estimatedMinutes: 15,
                warnings: [], titleArabic: "جلسة مقترحة للقوة")
            let coordinator = WorkoutCoordinator(settings: AppSettings())
            coordinator.start(preview: preview, context: context)
            let activeID = try XCTUnwrap(coordinator.activeSessionID)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
            let movement = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first)
            XCTAssertEqual(movement.exerciseID, exerciseID)
            XCTAssertEqual(movement.sessionID, activeID)
            XCTAssertEqual(movement.restSeconds, 120)
            XCTAssertTrue(movement.notes.contains("زيادة تدريجية"))
            let sets = try context.fetch(FetchDescriptor<LoggedSet>())
            XCTAssertEqual(sets.count, 3)
            XCTAssertTrue(sets.allSatisfy { $0.weightKg == 42.5 && $0.reps == 8 && !$0.isCompleted && $0.kindRaw == "working" })
            coordinator.start(preview: preview, context: context)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
            XCTAssertEqual(coordinator.activeSessionID, activeID)
            return activeID
        }
        let reopened = try PersistenceController.makeContainer(storeURL: url).container
        let context = ModelContext(reopened)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.id, sessionID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.statusRaw, "active")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 3)
        let coordinator = WorkoutCoordinator(settings: AppSettings())
        coordinator.recover(context: context)
        XCTAssertEqual(coordinator.activeSessionID, sessionID)
    }

    @MainActor
    func testInvalidOrArchivedGeneratedPrescriptionCreatesNoPartialSession() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let exerciseID = SeedCatalog.stableID(namespace: 1, code: 1)
        let exercise = Exercise(id: exerciseID, name: "ضغط الصدر", isArchived: true)
        context.insert(exercise)
        try context.save()
        let coordinator = WorkoutCoordinator(settings: AppSettings())
        var preview = SmartWorkoutPreview(exercises: [TrainingPrescription(exerciseID: exerciseID,
            name: "ضغط الصدر", sets: 3, reps: 10, weightKg: 40, restSeconds: 90,
            reason: "اقتراح", mode: .reps)], estimatedMinutes: 15, warnings: [], titleArabic: "اقتراح")
        coordinator.start(preview: preview, context: context)
        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertNil(coordinator.activeSessionID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 0)
        exercise.isArchived = false
        try context.save()
        preview = SmartWorkoutPreview(exercises: [TrainingPrescription(exerciseID: exerciseID,
            name: "ضغط الصدر", sets: 3, reps: 10, weightKg: -1, restSeconds: 90,
            reason: "اقتراح", mode: .reps)], estimatedMinutes: 15, warnings: [], titleArabic: "اقتراح")
        coordinator.start(preview: preview, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 0)
    }

    @MainActor
    func testExactCableMachinesRequirePositiveExplicitWeightButAllowUnknownStartingLoad() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        for code in [11, 15] {
            let exerciseID = SeedCatalog.stableID(namespace: 1, code: code)
            context.insert(Exercise(id: exerciseID, name: "تمرين السحب"))
            XCTAssertTrue(SmartTrainingStore.requiresExternalLoad(exerciseID: exerciseID))
        }
        XCTAssertFalse(SmartTrainingStore.requiresExternalLoad(exerciseID: SeedCatalog.stableID(namespace: 1, code: 8)))
        try context.save()
        let coordinator = WorkoutCoordinator(settings: AppSettings())
        for code in [11, 15] {
            let exerciseID = SeedCatalog.stableID(namespace: 1, code: code)
            let zero = SmartWorkoutPreview(exercises: [TrainingPrescription(exerciseID: exerciseID,
                name: "تمرين السحب", sets: 2, reps: 10, weightKg: 0, restSeconds: 90,
                reason: "اقتراح", mode: .reps)], estimatedMinutes: 15, warnings: [], titleArabic: "اقتراح")
            coordinator.start(preview: zero, context: context)
            XCTAssertNil(coordinator.activeSessionID)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 0)
        }
        let exerciseID = SeedCatalog.stableID(namespace: 1, code: 11)
        let unknown = SmartWorkoutPreview(exercises: [TrainingPrescription(exerciseID: exerciseID,
            name: "تمرين السحب", sets: 2, reps: 10, weightKg: nil, restSeconds: 90,
            reason: "اختر وزن البداية بنفسك", mode: .reps)], estimatedMinutes: 15,
            warnings: [], titleArabic: "اقتراح")
        coordinator.start(preview: unknown, context: context)
        XCTAssertNotNil(coordinator.activeSessionID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 2)
    }
}
