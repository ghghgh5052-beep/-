import Foundation
import SwiftData
import XCTest
@testable import Fitness

final class TrainingEnhancementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDoubleProgressionRequiresEverySetAndRecordedEffort() {
        let session = UUID(), exercise = UUID()
        let history = (0..<3).map { _ in TrainingSetHistory(sessionID: session, exerciseID: exercise, date: now.addingTimeInterval(-86_400), weightKg: 40, reps: 12, rpe: 8) }
        let accepted = DoubleProgressionEngine.decide(history: history, lower: 8, upper: 12, targetSets: 3, increment: 2.5, difficult: false, now: now)
        XCTAssertEqual(accepted.weightKg, 42.5); XCTAssertEqual(accepted.reps, 8)
        let incomplete = DoubleProgressionEngine.decide(history: Array(history.prefix(2)), lower: 8, upper: 12, targetSets: 3, increment: 2.5, difficult: false, now: now)
        XCTAssertEqual(incomplete.weightKg, 40)
        let missingRPE = history.map { TrainingSetHistory(sessionID: $0.sessionID, exerciseID: $0.exerciseID, date: $0.date, weightKg: $0.weightKg, reps: $0.reps) }
        XCTAssertEqual(DoubleProgressionEngine.decide(history: missingRPE, lower: 8, upper: 12, targetSets: 3, increment: 2.5, difficult: false, now: now).weightKg, 40)
    }

    func testDifficultFeedbackAndTrainingBreakNeverIncreaseLoad() {
        let history = [TrainingSetHistory(sessionID: UUID(), exerciseID: UUID(), date: now.addingTimeInterval(-86_400), weightKg: 50, reps: 12, rpe: 7)]
        XCTAssertEqual(DoubleProgressionEngine.decide(history: history, lower: 8, upper: 12, targetSets: 1, increment: 5, difficult: true, now: now).weightKg, 50)
        let paused = DoubleProgressionEngine.decide(history: history, lower: 8, upper: 12, targetSets: 1, increment: 5, difficult: false, now: now.addingTimeInterval(30 * 86_400))
        XCTAssertEqual(paused.weightKg, 50); XCTAssertEqual(paused.reps, 8)
    }

    func testAlternativesRequirePatternMuscleEquipmentAndDifficulty() {
        let source = trainingExercise(1), matching = trainingExercise(2), wrongPattern = trainingExercise(13)
        let available: Set<TrainingEquipment> = [.dumbbell, .bench]
        let result = ExerciseAlternativesEngine.alternatives(to: source, candidates: [source, matching, wrongPattern], available: available, avoided: [])
        XCTAssertEqual(result.map(\.id), [matching.id])
        XCTAssertTrue(ExerciseAlternativesEngine.alternatives(to: source, candidates: [matching], available: [.bodyweight], avoided: []).isEmpty)
        XCTAssertTrue(ExerciseAlternativesEngine.alternatives(to: source, candidates: [matching], available: available, avoided: [matching.id]).isEmpty)
    }

    func testWeeklyComparisonUsesLocalWeekAndSameElapsedDays() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600) ?? .current; calendar.firstWeekday = 7
        let current = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12)) ?? now
        let start = calendar.dateInterval(of: .weekOfYear, for: current)?.start ?? current
        let previous = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let a = UUID(), b = UUID(), later = UUID(), exercise = UUID()
        let sessions = [ReportSession(id: a, date: start), ReportSession(id: b, date: previous), ReportSession(id: later, date: previous.addingTimeInterval(6 * 86_400))]
        let sets = [ReportSet(sessionID: a, exerciseID: exercise, name: "صدر", weight: 55, reps: 8, mode: "reps", convention: "total"), ReportSet(sessionID: b, exerciseID: exercise, name: "صدر", weight: 50, reps: 10, mode: "reps", convention: "total")]
        let report = WeeklyReportEngine.make(sessions: sessions, sets: sets, now: current, calendar: calendar)
        XCTAssertEqual(report.currentSessions, 1); XCTAssertEqual(report.previousSessions, 1)
        XCTAssertEqual(report.currentVolume, 440); XCTAssertEqual(report.previousVolume, 500)
        XCTAssertEqual(report.lifts.first?.currentWeight, 55); XCTAssertEqual(report.lifts.first?.previousWeight, 50)
    }

    func testReportNeverComparesDifferentLoadConventionsOrCardioAsLifting() {
        var calendar = Calendar(identifier: .gregorian); calendar.firstWeekday = 7
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let previous = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let a = UUID(), b = UUID(), exercise = UUID()
        let sets = [ReportSet(sessionID: a, exerciseID: exercise, name: "دمبل", weight: 20, reps: 10, mode: "reps", convention: "perHand"), ReportSet(sessionID: b, exerciseID: exercise, name: "دمبل", weight: 40, reps: 10, mode: "reps", convention: "total"), ReportSet(sessionID: a, exerciseID: UUID(), name: "مشي", weight: 100, reps: 60, mode: "distance", convention: "total")]
        let report = WeeklyReportEngine.make(sessions: [ReportSession(id: a, date: start), ReportSession(id: b, date: previous)], sets: sets, now: now, calendar: calendar)
        XCTAssertEqual(report.currentVolume, 200); XCTAssertEqual(report.lifts.count, 1); XCTAssertEqual(report.lifts.first?.comparable, false)
    }

    @MainActor func testEditingAndExcludingUpdatesHistoryAndRecordsWithoutDeletingSets() throws {
        let context = try makeContext()
        let session = fixture(context, weight: 50)
        try context.save(); try PRService.rebuild(context: context)
        let set = try XCTUnwrap(context.fetch(FetchDescriptor<LoggedSet>()).first)
        let edit = SessionSetEdit(id: set.id, weightKg: 60, reps: 8, rpe: 8, kindRaw: "working", seconds: 0, distanceMeters: 0, assistanceKg: 0, modeRaw: "reps", conventionRaw: "total")
        try TrainingEnhancementStore.edit(session: session, title: "تعديل", start: session.start, duration: 60, notes: "ملاحظة", excluded: false, edits: [edit], context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersonalRecord>()).first { $0.kindRaw == "weight" }?.value, 60)
        XCTAssertEqual(set.completedAt, session.end)
        try TrainingEnhancementStore.edit(session: session, title: "تجريبية", start: session.start, duration: 60, notes: "", excluded: true, edits: [edit], context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 0)
        XCTAssertTrue(try SmartTrainingStore.snapshot(context: context).history.isEmpty)
        try TrainingEnhancementStore.edit(session: session, title: "احتساب", start: session.start, duration: 60, notes: "", excluded: false, edits: [edit], context: context)
        XCTAssertEqual(try SmartTrainingStore.snapshot(context: context).history.count, 1)
    }

    @MainActor func testFailedSessionEditRollsBackValuesAndRecords() throws {
        enum Failure: Error { case diskFull }
        let context = try makeContext(), session = fixture(context, weight: 50)
        try context.save(); try PRService.rebuild(context: context)
        let before = Set(try context.fetch(FetchDescriptor<PersonalRecord>()).map(\.id))
        XCTAssertThrowsError(try TrainingEnhancementStore.edit(session: session, title: "تجريبية", start: session.start, duration: 60, notes: "", excluded: true, edits: [], context: context, commit: { _ in throw Failure.diskFull }))
        XCTAssertEqual(session.statusRaw, "completed")
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<PersonalRecord>()).map(\.id)), before)
    }

    @MainActor func testTimedAndAssistedMeasurementsDoNotBecomeWeightRecords() throws {
        let context = try makeContext(), session = fixture(context, weight: 100)
        let set = try XCTUnwrap(context.fetch(FetchDescriptor<LoggedSet>()).first)
        context.insert(SetMeasurement(setID: set.id, modeRaw: "assisted", assistanceKg: 100))
        context.insert(SessionFeedback(sessionID: session.id, difficulty: 3, energy: 1, fatigueRaw: "chest"))
        try context.save(); try PRService.rebuild(context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 0)
        XCTAssertTrue(try SmartTrainingStore.snapshot(context: context).history.isEmpty)
        try SessionDeletionService.delete(sessionID: session.id, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetMeasurement>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionFeedback>()), 0)
    }

    @MainActor func testReplacementPreservesIdentityAndUsesOnlyReplacementHistory() throws {
        let context = try makeContext()
        let source = Exercise(id: SeedCatalog.stableID(namespace: 1, code: 1), name: "بار")
        let replacement = Exercise(id: SeedCatalog.stableID(namespace: 1, code: 2), name: "دمبل")
        context.insert(source); context.insert(replacement)
        let old = WorkoutSession(start: now, end: now.addingTimeInterval(60), statusRaw: "completed")
        let prior = SessionExercise(sessionID: old.id, exerciseID: replacement.id)
        context.insert(old); context.insert(prior)
        context.insert(LoggedSet(sessionExerciseID: prior.id, weightKg: 15, reps: 12, isCompleted: true))
        let active = WorkoutSession(), item = SessionExercise(exerciseID: source.id, groupID: "دائرة")
        item.sessionID = active.id; context.insert(active); context.insert(item)
        let pending = LoggedSet(sessionExerciseID: item.id, weightKg: 100, reps: 5)
        context.insert(pending); try context.save()
        try TrainingEnhancementStore.replace(item: item, with: replacement, context: context)
        XCTAssertEqual(item.exerciseID, replacement.id); XCTAssertEqual(item.groupID, "دائرة")
        XCTAssertEqual(pending.weightKg, 15); XCTAssertEqual(pending.reps, 12)
        pending.isCompleted = true; try context.save()
        XCTAssertThrowsError(try TrainingEnhancementStore.replace(item: item, with: source, context: context))
    }

    @MainActor func testNewDetailsRoundTripJSONCSVAndPlaceProfilesStayIndependent() throws {
        let context = try makeContext(), session = fixture(context, weight: 0)
        let set = try XCTUnwrap(context.fetch(FetchDescriptor<LoggedSet>()).first)
        set.reps = 0
        context.insert(SetMeasurement(setID: set.id, modeRaw: "distance", seconds: 600, distanceMeters: 1_500))
        context.insert(SessionFeedback(sessionID: session.id, difficulty: 2, energy: 3, fatigueRaw: "calves"))
        context.insert(ExercisePreference(exerciseID: SeedCatalog.stableID(namespace: 1, code: 1), avoid: true))
        context.insert(ProgressionProgram(exerciseID: SeedCatalog.stableID(namespace: 1, code: 1)))
        try SmartTrainingStore.savePreferences(TrainingPreferences(goal: .strength, equipment: [.barbell, .bench, .rack]), context: context, key: TrainingPlace.gym.rawValue)
        try SmartTrainingStore.savePreferences(TrainingPreferences(goal: .fitness, equipment: [.bodyweight]), context: context, key: TrainingPlace.home.rawValue)
        XCTAssertEqual(try SmartTrainingStore.loadPreferences(context: context, key: TrainingPlace.gym.rawValue).goal, .strength)
        XCTAssertEqual(try SmartTrainingStore.loadPreferences(context: context, key: TrainingPlace.home.rawValue).goal, .fitness)
        let backup = try BackupService.decode(BackupService.encode(context: context))
        XCTAssertEqual(backup.formatVersion, 3); XCTAssertEqual(backup.measurements.first?.distanceMeters, 1_500)
        XCTAssertEqual(backup.trainingProfiles.count, 2); XCTAssertEqual(backup.feedback.count, 1)
        let restored = try makeContext(); try BackupService.merge(backup, context: restored)
        XCTAssertEqual(try restored.fetch(FetchDescriptor<SetMeasurement>()).first?.seconds, 600)
        let csv = try CSVService.decode(CSVService.encode(context: context))
        XCTAssertEqual(csv.measurements.first?.distanceMeters, 1_500); XCTAssertEqual(csv.feedback.first?.energy, 3)
        XCTAssertEqual(csv.sets.first?.reps, 0)
    }

    @MainActor func testMigrationFromV3PreservesStoreAndAddsOptionalDetails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("V3.store"), id = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: FitnessSchemaV3.self)
            let config = ModelConfiguration("Fitness", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            context.insert(WorkoutSession(id: id, title: "السجل السابق", statusRaw: "completed"))
            context.insert(TrainingProfile(goalRaw: "strength")); try context.save()
        }
        let result = try PersistenceController.makeContainer(storeURL: url)
        let context = ModelContext(result.container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.id, id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingProfile>()).first?.goalRaw, "strength")
        context.insert(SessionFeedback(sessionID: id, difficulty: 2)); try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionFeedback>()), 1)
    }

    func testWeeklyReportHandlesTwoYearsOfHistoryWithoutRescanningEverySession() {
        let exercise = UUID()
        let sessions = (0..<730).map { ReportSession(id: UUID(), date: now.addingTimeInterval(-Double($0) * 86_400)) }
        let sets = sessions.flatMap { session in (0..<30).map { _ in ReportSet(sessionID: session.id, exerciseID: exercise, name: "صدر", weight: 50, reps: 10, mode: "reps", convention: "total") } }
        var calendar = Calendar(identifier: .gregorian); calendar.firstWeekday = 7
        let report = WeeklyReportEngine.make(sessions: sessions, sets: sets, now: now.addingTimeInterval(1), calendar: calendar, completedWeek: true)
        XCTAssertEqual(report.currentSessions, 7); XCTAssertEqual(report.currentSets, 210); XCTAssertEqual(report.currentVolume, 105_000)
    }

    @MainActor private func makeContext() throws -> ModelContext { ModelContext(try PersistenceController.makeContainer(inMemory: true).container) }
    @MainActor private func fixture(_ context: ModelContext, weight: Double) -> WorkoutSession {
        let exercise = Exercise(id: SeedCatalog.stableID(namespace: 1, code: 1), name: "ضغط الصدر")
        let date = Date.now.addingTimeInterval(-3_600)
        let session = WorkoutSession(start: date, end: date.addingTimeInterval(60), statusRaw: "completed")
        let movement = SessionExercise(sessionID: session.id, exerciseID: exercise.id, name: exercise.name)
        context.insert(exercise); context.insert(session); context.insert(movement)
        context.insert(LoggedSet(sessionExerciseID: movement.id, weightKg: weight, reps: 10, rpe: 8, isCompleted: true, completedAt: session.end))
        return session
    }
    private func trainingExercise(_ code: Int) -> TrainingExercise {
        let id = SeedCatalog.stableID(namespace: 1, code: code)
        guard let metadata = SmartExerciseMetadata.forBuiltInID(id) else { return TrainingExercise(id: id, name: "", primaryMuscles: [], secondaryMuscles: [], requiredEquipment: [], movementPattern: .core) }
        return TrainingExercise(id: id, name: "تمرين", primaryMuscles: metadata.primaryMuscles, secondaryMuscles: metadata.secondaryMuscles, requiredEquipment: metadata.requiredEquipment, movementPattern: metadata.movementPattern, mode: metadata.mode, difficulty: metadata.difficulty)
    }
}
