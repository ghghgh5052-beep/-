import Foundation
import SwiftData
import XCTest
@testable import Fitness

final class BackupTests: XCTestCase {
    @MainActor
    func testJSONPreservesMillisecondsAndReadsLegacyWholeSecondDates() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let updated = Date(timeIntervalSince1970: 1_700_000_001.456)
        context.insert(BodyMetric(date: date, weightKg: 80, updatedAt: updated))
        let backup = try BackupService.decode(BackupService.encode(context: context))
        let metric = try XCTUnwrap(backup.metrics.first)
        XCTAssertEqual(metric.date.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(metric.updatedAt.timeIntervalSince1970, updated.timeIntervalSince1970, accuracy: 0.001)
        let legacy = JSONEncoder()
        legacy.dateEncodingStrategy = .iso8601
        let legacyBackup = try BackupService.decode(legacy.encode(BackupService.envelope(context: context)))
        XCTAssertEqual(legacyBackup.metrics.first?.weightKg, 80)
    }

    @MainActor
    func testFullJSONBackupRoundTripsPhotosAndEveryEntityAndMergesIdempotently() throws {
        let source = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(source)
        let fixture = populate(context)
        try context.save()
        let data = try BackupService.encode(context: context)
        let backup = try BackupService.decode(data)
        XCTAssertEqual(backup.exercises.count, 1)
        XCTAssertEqual(backup.plans.count, 1)
        XCTAssertEqual(backup.days.count, 1)
        XCTAssertEqual(backup.planExercises.count, 1)
        XCTAssertEqual(backup.sessions.count, 1)
        XCTAssertEqual(backup.sessionExercises.count, 1)
        XCTAssertEqual(backup.sets.count, 1)
        XCTAssertEqual(backup.metrics.count, 1)
        XCTAssertEqual(backup.photos.first?.imageData, fixture.photo)
        XCTAssertEqual(backup.goals.count, 1)
        XCTAssertEqual(backup.reminders.count, 1)
        XCTAssertEqual(backup.preferences.count, 1)
        XCTAssertEqual(backup.records.count, 1)
        XCTAssertEqual(backup.sessions.first?.pauseEventsRaw, "[1700000010,1700000020]")
        XCTAssertEqual(backup.plans.first?.isActive, true)
        let destination = try PersistenceController.makeContainer(inMemory: true).container
        try BackupService.merge(backup, container: destination)
        try BackupService.merge(backup, container: destination)
        let restored = try BackupService.envelope(context: ModelContext(destination))
        XCTAssertEqual(restored.totalCount, backup.totalCount)
        XCTAssertEqual(restored.photos.first?.imageData, fixture.photo)
        XCTAssertEqual(restored.sets.first?.sessionExerciseID, fixture.movementID)
    }

    @MainActor
    func testMissingReferencesRejectWholeImportBeforeMutation() throws {
        let source = try PersistenceController.makeContainer(inMemory: true).container
        let sourceContext = ModelContext(source)
        _ = populate(sourceContext)
        try sourceContext.save()
        var broken = try BackupService.envelope(context: sourceContext)
        broken.sets[0].sessionExerciseID = UUID()
        let destination = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(destination)
        context.insert(BodyMetric(weightKg: 99))
        try context.save()
        XCTAssertThrowsError(try BackupService.merge(broken, container: destination)) { error in
            guard let backupError = error as? BackupError, case .missingReferences = backupError else {
                return XCTFail("Expected missing reference error")
            }
        }
        let restored = try BackupService.envelope(context: ModelContext(destination))
        XCTAssertEqual(restored.totalCount, 1)
        XCTAssertEqual(restored.metrics.first?.weightKg, 99)
    }

    @MainActor
    func testImportedPreferenceUpdatesAlreadyLoadedVisibleContext() throws {
        let id = UUID()
        let source = try PersistenceController.makeContainer(inMemory: true).container
        let sourceContext = ModelContext(source)
        sourceContext.insert(UserPreferences(id: id, weightUnit: "lb", updatedAt: Date(timeIntervalSince1970: 20)))
        try sourceContext.save()
        let backup = try BackupService.envelope(context: sourceContext)
        let destination = try PersistenceController.makeContainer(inMemory: true).container
        let visible = destination.mainContext
        visible.insert(UserPreferences(id: id, weightUnit: "kg", updatedAt: Date(timeIntervalSince1970: 10)))
        try visible.save()
        let before = try XCTUnwrap(visible.fetch(FetchDescriptor<UserPreferences>()).first)
        XCTAssertEqual(before.weightUnit, "kg")
        try BackupService.merge(backup, context: visible)
        let after = try XCTUnwrap(visible.fetch(FetchDescriptor<UserPreferences>()).first)
        XCTAssertEqual(after.weightUnit, "lb")
    }

    @MainActor
    func testCSVPreservesQuotedArabicNewlinesAllWorkoutScalarsAndBodyMetrics() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let fixture = populate(context)
        let data = try CSVService.encode(context: context)
        let backup = try CSVService.decode(data)
        XCTAssertEqual(backup.exercises.first?.name, "ضغط \"الصدر\"، بالبار\nقبضة متوسطة")
        XCTAssertEqual(backup.sessions.first?.notes, "السطر الأول, فاصلة\r\nالسطر الثاني")
        XCTAssertEqual(backup.sessions.first?.pauseEventsRaw, "[1700000010,1700000020]")
        XCTAssertEqual(backup.sessions.first?.accumulatedPause, 10)
        XCTAssertEqual(backup.sessions.first?.planDayID, fixture.dayID)
        XCTAssertEqual(backup.sessions.first?.healthExported, true)
        XCTAssertEqual(backup.sessionExercises.first?.groupID, "مجموعة, مشتركة")
        XCTAssertEqual(backup.sets.first?.rpe, 8.5)
        XCTAssertEqual(backup.sets.first?.kindRaw, "drop")
        XCTAssertEqual(backup.sets.first?.weightKg, 75.5)
        XCTAssertEqual(backup.metrics.first?.fatPercent, 15)
        XCTAssertEqual(backup.metrics.first?.thighCm, 58)
        XCTAssertTrue(backup.plans.isEmpty)
        XCTAssertTrue(backup.photos.isEmpty)
        let restored = try PersistenceController.makeContainer(inMemory: true).container
        try BackupService.merge(backup, container: restored)
        XCTAssertEqual(try ModelContext(restored).fetchCount(FetchDescriptor<LoggedSet>()), 1)
    }

    @MainActor
    func testCSVFormulaProtectionIsReversibleIncludingExistingApostrophe() throws {
        let container = try PersistenceController.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        let exercise = Exercise(name: "=1+1", notes: "'ملاحظة تبدأ بعلامة", mediaURL: "\t@مثال")
        context.insert(exercise)
        let data = try CSVService.encode(context: context)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"'=1+1\""))
        XCTAssertTrue(text.contains("\"''ملاحظة تبدأ بعلامة\""))
        let backup = try CSVService.decode(data)
        XCTAssertEqual(backup.exercises.first?.name, exercise.name)
        XCTAssertEqual(backup.exercises.first?.notes, exercise.notes)
        XCTAssertEqual(backup.exercises.first?.mediaURL, exercise.mediaURL)
    }

    @MainActor
    func testCSVMalformedQuoteInvalidNumberAndMissingMovementAreRejected() throws {
        let malformed = Data("نوع السجل,المعرّف\r\n\"جلسة,معرّف".utf8)
        XCTAssertThrowsError(try CSVService.decode(malformed))
        let setID = UUID(), movementID = UUID()
        let missing = Data("نوع السجل,المعرّف,حركة الجلسة,الوزن بالكجم,التكرارات\r\nمجموعة,\(setID),\(movementID),50,10\r\n".utf8)
        XCTAssertThrowsError(try CSVService.decode(missing))
        let invalid = Data("نوع السجل,المعرّف,تاريخ القياس,الوزن بالكجم\r\nقياس,\(UUID()),2024-01-01T00:00:00Z,ليس رقمًا\r\n".utf8)
        XCTAssertThrowsError(try CSVService.decode(invalid))
    }

    @MainActor
    private func populate(_ context: ModelContext) -> (photo: Data, movementID: UUID, dayID: UUID) {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let exercise = Exercise(name: "ضغط \"الصدر\"، بالبار\nقبضة متوسطة", primaryMuscleRaw: "صدر",
                                equipmentRaw: "بار", notes: "تمرين مخصص", isFavorite: true, isCustom: true, updatedAt: date)
        let plan = WorkoutPlan(name: "خطة شخصية", cycleWeeks: 4, deloadEvery: 4,
                               programStart: date, isActive: true, updatedAt: date)
        let day = PlanDay(planID: plan.id, weekday: 7, title: "الدفع", updatedAt: date)
        let planned = PlanExercise(dayID: day.id, exerciseID: exercise.id, updatedAt: date)
        let session = WorkoutSession(planDayID: day.id, title: "الدفع", start: date,
            end: date.addingTimeInterval(600), accumulatedPause: 10, pauseEventsRaw: "[1700000010,1700000020]",
            notes: "السطر الأول, فاصلة\r\nالسطر الثاني", statusRaw: "completed", healthExported: true, updatedAt: date)
        let movement = SessionExercise(sessionID: session.id, exerciseID: exercise.id, name: exercise.name,
            notes: "ملاحظة الحركة", groupID: "مجموعة, مشتركة", restSeconds: 120, updatedAt: date)
        let set = LoggedSet(sessionExerciseID: movement.id, weightKg: 75.5, reps: 10, rpe: 8.5,
            kindRaw: "drop", isCompleted: true, completedAt: date.addingTimeInterval(60), updatedAt: date)
        let metric = BodyMetric(date: date, weightKg: 80, fatPercent: 15, chestCm: 101,
            waistCm: 82, armCm: 35, hipsCm: 98, thighCm: 58, updatedAt: date)
        let photo = Data([0, 1, 2, 127, 255])
        context.insert(exercise); context.insert(plan); context.insert(day); context.insert(planned)
        context.insert(session); context.insert(movement); context.insert(set); context.insert(metric)
        context.insert(ProgressPhoto(date: date, imageData: photo, notes: "صورة خاصة", updatedAt: date))
        context.insert(FitnessGoal(title: "هدفي", kindRaw: "lift", targetValue: 100, exerciseID: exercise.id,
                                  createdAt: date, updatedAt: date))
        context.insert(WorkoutReminder(updatedAt: date))
        context.insert(UserPreferences(updatedAt: date))
        context.insert(PersonalRecord(exerciseID: exercise.id, sessionID: session.id, setID: set.id,
            kindRaw: "weight", value: 75.5, weightKg: 75.5, achievedAt: date, updatedAt: date))
        return (photo, movement.id, day.id)
    }
}
