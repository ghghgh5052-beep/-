import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupEnvelope: Codable {
    var formatVersion = 3
    var exportedAt = Date()
    var exercises: [ExerciseRecord]
    var plans: [WorkoutPlanRecord]
    var days: [PlanDayRecord]
    var planExercises: [PlanExerciseRecord]
    var sessions: [WorkoutSessionRecord]
    var sessionExercises: [SessionExerciseRecord]
    var sets: [LoggedSetRecord]
    var metrics: [BodyMetricRecord]
    var photos: [ProgressPhotoRecord]
    var goals: [FitnessGoalRecord]
    var reminders: [WorkoutReminderRecord]
    var preferences: [UserPreferencesRecord]
    var records: [PersonalRecordRecord]
    var trainingProfiles: [TrainingProfileRecord] = []
    var feedback: [SessionFeedbackRecord] = []
    var measurements: [SetMeasurementRecord] = []
    var exercisePreferences: [ExercisePreferenceRecord] = []
    var progressionPrograms: [ProgressionProgramRecord] = []
    var totalCount: Int { exercises.count + plans.count + days.count + planExercises.count + sessions.count + sessionExercises.count + sets.count + metrics.count + photos.count + goals.count + reminders.count + preferences.count + records.count + trainingProfiles.count + feedback.count + measurements.count + exercisePreferences.count + progressionPrograms.count }

    enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, exercises, plans, days, planExercises, sessions
        case sessionExercises, sets, metrics, photos, goals, reminders, preferences, records, trainingProfiles, feedback, measurements, exercisePreferences, progressionPrograms
    }
}

extension BackupEnvelope {
    /// Earlier JSON backups have no trainingProfiles field; all their original arrays stay required.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(formatVersion: try values.decode(Int.self, forKey: .formatVersion),
            exportedAt: try values.decode(Date.self, forKey: .exportedAt),
            exercises: try values.decode([ExerciseRecord].self, forKey: .exercises),
            plans: try values.decode([WorkoutPlanRecord].self, forKey: .plans),
            days: try values.decode([PlanDayRecord].self, forKey: .days),
            planExercises: try values.decode([PlanExerciseRecord].self, forKey: .planExercises),
            sessions: try values.decode([WorkoutSessionRecord].self, forKey: .sessions),
            sessionExercises: try values.decode([SessionExerciseRecord].self, forKey: .sessionExercises),
            sets: try values.decode([LoggedSetRecord].self, forKey: .sets),
            metrics: try values.decode([BodyMetricRecord].self, forKey: .metrics),
            photos: try values.decode([ProgressPhotoRecord].self, forKey: .photos),
            goals: try values.decode([FitnessGoalRecord].self, forKey: .goals),
            reminders: try values.decode([WorkoutReminderRecord].self, forKey: .reminders),
            preferences: try values.decode([UserPreferencesRecord].self, forKey: .preferences),
            records: try values.decode([PersonalRecordRecord].self, forKey: .records),
            trainingProfiles: try values.decodeIfPresent([TrainingProfileRecord].self, forKey: .trainingProfiles) ?? [],
            feedback: try values.decodeIfPresent([SessionFeedbackRecord].self, forKey: .feedback) ?? [],
            measurements: try values.decodeIfPresent([SetMeasurementRecord].self, forKey: .measurements) ?? [],
            exercisePreferences: try values.decodeIfPresent([ExercisePreferenceRecord].self, forKey: .exercisePreferences) ?? [],
            progressionPrograms: try values.decodeIfPresent([ProgressionProgramRecord].self, forKey: .progressionPrograms) ?? [])
    }
}

enum BackupError: Error, LocalizedError {
    case invalidFormat, invalidValues, missingReferences, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "الملف غير متوافق مع نسخة وتيرة الحالية."
        case .invalidValues: return "يحتوي الملف على قيم غير صحيحة؛ لم تتغير بياناتك."
        case .missingReferences: return "الملف ناقص ويشير إلى تمارين أو جلسات غير موجودة."
        case .tooLarge: return "الملف أكبر من الحد المسموح للاستيراد."
        }
    }
}

@MainActor enum BackupService {
    static func envelope(context: ModelContext) throws -> BackupEnvelope {
        BackupEnvelope(exercises: try context.fetch(FetchDescriptor<Exercise>()).map(ExerciseRecord.init),
                       plans: try context.fetch(FetchDescriptor<WorkoutPlan>()).map(WorkoutPlanRecord.init),
                       days: try context.fetch(FetchDescriptor<PlanDay>()).map(PlanDayRecord.init),
                       planExercises: try context.fetch(FetchDescriptor<PlanExercise>()).map(PlanExerciseRecord.init),
                       sessions: try context.fetch(FetchDescriptor<WorkoutSession>()).map(WorkoutSessionRecord.init),
                       sessionExercises: try context.fetch(FetchDescriptor<SessionExercise>()).map(SessionExerciseRecord.init),
                       sets: try context.fetch(FetchDescriptor<LoggedSet>()).map(LoggedSetRecord.init),
                       metrics: try context.fetch(FetchDescriptor<BodyMetric>()).map(BodyMetricRecord.init),
                       photos: try context.fetch(FetchDescriptor<ProgressPhoto>()).map(ProgressPhotoRecord.init),
                       goals: try context.fetch(FetchDescriptor<FitnessGoal>()).map(FitnessGoalRecord.init),
                       reminders: try context.fetch(FetchDescriptor<WorkoutReminder>()).map(WorkoutReminderRecord.init),
                       preferences: try context.fetch(FetchDescriptor<UserPreferences>()).map(UserPreferencesRecord.init),
                       records: try context.fetch(FetchDescriptor<PersonalRecord>()).map(PersonalRecordRecord.init),
                       trainingProfiles: try context.fetch(FetchDescriptor<TrainingProfile>()).map(TrainingProfileRecord.init),
                       feedback: try context.fetch(FetchDescriptor<SessionFeedback>()).map(SessionFeedbackRecord.init),
                       measurements: try context.fetch(FetchDescriptor<SetMeasurement>()).map(SetMeasurementRecord.init),
                       exercisePreferences: try context.fetch(FetchDescriptor<ExercisePreference>()).map(ExercisePreferenceRecord.init),
                       progressionPrograms: try context.fetch(FetchDescriptor<ProgressionProgram>()).map(ProgressionProgramRecord.init))
    }
    static func encode(context: ModelContext) throws -> Data {
        try PersistenceController.reconcile(context: context)
        try context.save()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var value = encoder.singleValueContainer(); try value.encode(formatter.string(from: date))
        }
        return try encoder.encode(envelope(context: context))
    }
    static func decode(_ data: Data) throws -> BackupEnvelope {
        guard data.count <= 512 * 1024 * 1024 else { throw BackupError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw BackupError.invalidValues }
            return date
        }
        let backup: BackupEnvelope
        do { backup = try decoder.decode(BackupEnvelope.self, from: data) } catch { throw BackupError.invalidFormat }
        guard [1, 2, 3].contains(backup.formatVersion), backup.totalCount < 2_000_000 else { throw BackupError.invalidFormat }
        try validate(backup)
        return backup
    }
    static func validate(_ backup: BackupEnvelope) throws {
        guard [1, 2, 3].contains(backup.formatVersion) else { throw BackupError.invalidFormat }
        func unique<R>(_ records: [R], _ id: KeyPath<R, UUID>) -> Bool { Set(records.map { $0[keyPath: id] }).count == records.count }
        guard unique(backup.exercises, \.id), unique(backup.plans, \.id), unique(backup.days, \.id), unique(backup.planExercises, \.id), unique(backup.sessions, \.id), unique(backup.sessionExercises, \.id), unique(backup.sets, \.id), unique(backup.metrics, \.id), unique(backup.photos, \.id), unique(backup.goals, \.id), unique(backup.reminders, \.id), unique(backup.preferences, \.id), unique(backup.records, \.id), Set(backup.preferences.map(\.key)).count == backup.preferences.count else { throw BackupError.invalidValues }
        guard unique(backup.trainingProfiles, \.id),
              Set(backup.trainingProfiles.map(\.key)).count == backup.trainingProfiles.count,
              backup.trainingProfiles.allSatisfy({ TrainingPlace(rawValue: $0.key) != nil
                  && SmartTrainingStore.validProfile(goal: $0.goalRaw, level: $0.levelRaw,
                    equipment: $0.equipmentRaw, duration: $0.durationMinutes, increment: $0.incrementKg) }) else {
            throw BackupError.invalidValues
        }
        guard unique(backup.feedback, \.id), Set(backup.feedback.map(\.sessionID)).count == backup.feedback.count,
              unique(backup.measurements, \.id), Set(backup.measurements.map(\.setID)).count == backup.measurements.count,
              unique(backup.exercisePreferences, \.id), Set(backup.exercisePreferences.map(\.exerciseID)).count == backup.exercisePreferences.count,
              unique(backup.progressionPrograms, \.id), Set(backup.progressionPrograms.map(\.exerciseID)).count == backup.progressionPrograms.count,
              backup.feedback.allSatisfy({ (0...3).contains($0.difficulty) && (0...3).contains($0.energy)
                && $0.fatigueRaw.split(separator: ",").allSatisfy { MuscleRegion(rawValue: String($0)) != nil } }),
              backup.measurements.allSatisfy({ SetTrackingMode(rawValue: $0.modeRaw) != nil && LoadConvention(rawValue: $0.conventionRaw) != nil
                && $0.seconds.isFinite && (0...86400).contains($0.seconds) && $0.distanceMeters.isFinite && (0...1000000).contains($0.distanceMeters)
                && $0.assistanceKg.isFinite && (0...2000).contains($0.assistanceKg) }),
              backup.exercisePreferences.allSatisfy({ SetTrackingMode(rawValue: $0.modeRaw) != nil && LoadConvention(rawValue: $0.conventionRaw) != nil }),
              backup.progressionPrograms.allSatisfy({ (1...100).contains($0.lowerReps) && ($0.lowerReps...100).contains($0.upperReps)
                && (1...20).contains($0.targetSets) && $0.incrementKg.isFinite && (0.25...10).contains($0.incrementKg) && (1...52).contains($0.weeks) }) else { throw BackupError.invalidValues }
        func valid(_ value: Double?) -> Bool { value == nil || (value?.isFinite == true && (value ?? -1) >= 0 && (value ?? 0) <= 10_000_000) }
        guard backup.sets.allSatisfy({ valid($0.weightKg) && (0...10000).contains($0.reps) && ($0.rpe == nil || (0...10).contains($0.rpe ?? -1)) && ["warmup", "working", "drop", "failure"].contains($0.kindRaw) }),
              backup.metrics.allSatisfy({ valid($0.weightKg) && valid($0.chestCm) && valid($0.waistCm) && valid($0.armCm) && valid($0.hipsCm) && valid($0.thighCm) && ($0.fatPercent == nil || (0...100).contains($0.fatPercent ?? -1)) }),
              backup.plans.allSatisfy({ (1...52).contains($0.cycleWeeks) && (0...52).contains($0.deloadEvery) }),
              backup.days.allSatisfy({ (1...7).contains($0.weekday) && (1...52).contains($0.week) }),
              backup.planExercises.allSatisfy({ (1...100).contains($0.targetSets) && (1...10000).contains($0.targetReps) && (0...3600).contains($0.restSeconds) }),
              backup.sessions.allSatisfy({ ["active", "paused", "completed", "excluded"].contains($0.statusRaw) && valid($0.accumulatedPause) }),
              backup.goals.allSatisfy({ valid($0.targetValue) && $0.targetValue > 0 }),
              backup.preferences.allSatisfy({ ["kg","lb"].contains($0.weightUnit) && ["cm","in"].contains($0.lengthUnit) && (1...7).contains($0.weekStart) && (0...3600).contains($0.defaultRestSeconds) }),
              backup.reminders.allSatisfy({ (0...23).contains($0.hour) && (0...59).contains($0.minute) }) else { throw BackupError.invalidValues }
        let setIDs = Set(backup.sets.map(\.id))
        let exercises = Set(backup.exercises.map(\.id)), plans = Set(backup.plans.map(\.id)), days = Set(backup.days.map(\.id)), sessions = Set(backup.sessions.map(\.id)), movements = Set(backup.sessionExercises.map(\.id))
        guard backup.days.allSatisfy({ plans.contains($0.planID) }),
              backup.planExercises.allSatisfy({ days.contains($0.dayID) && exercises.contains($0.exerciseID) }),
              backup.sessionExercises.allSatisfy({ sessions.contains($0.sessionID) && exercises.contains($0.exerciseID) }),
              backup.sets.allSatisfy({ movements.contains($0.sessionExerciseID) }),
              backup.feedback.allSatisfy({ sessions.contains($0.sessionID) }),
              backup.measurements.allSatisfy({ setIDs.contains($0.setID) }),
              backup.exercisePreferences.allSatisfy({ exercises.contains($0.exerciseID) }),
              backup.progressionPrograms.allSatisfy({ exercises.contains($0.exerciseID) }) else { throw BackupError.missingReferences }
    }
    static func merge(_ backup: BackupEnvelope, container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try merge(backup, context: context)
    }
    static func merge(_ backup: BackupEnvelope, context: ModelContext) throws {
        try validate(backup)
        // Save prior edits before the import transaction, then preserve visible model identity.
        try context.save()
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        do {
            try merge(backup.exercises, context: context, model: Exercise.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.plans, context: context, model: WorkoutPlan.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.days, context: context, model: PlanDay.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.planExercises, context: context, model: PlanExercise.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.sessions, context: context, model: WorkoutSession.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.sessionExercises, context: context, model: SessionExercise.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.sets, context: context, model: LoggedSet.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.metrics, context: context, model: BodyMetric.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.photos, context: context, model: ProgressPhoto.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.goals, context: context, model: FitnessGoal.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.reminders, context: context, model: WorkoutReminder.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.preferences, context: context, model: UserPreferences.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.records, context: context, model: PersonalRecord.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.feedback, context: context, model: SessionFeedback.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.measurements, context: context, model: SetMeasurement.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.exercisePreferences, context: context, model: ExercisePreference.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            try merge(backup.progressionPrograms, context: context, model: ProgressionProgram.self, id: \.id, date: \.updatedAt, recordID: \.id, recordDate: \.updatedAt, make: { $0.makeModel() }, apply: { $0.apply(to: $1) })
            // Profiles are singletons by key, even when an import originated on another device.
            let profiles = try context.fetch(FetchDescriptor<TrainingProfile>())
            var byKey = Dictionary(profiles.map { ($0.key, $0) }, uniquingKeysWith: {
                $0.updatedAt >= $1.updatedAt ? $0 : $1
            })
            for record in backup.trainingProfiles {
                if let profile = byKey[record.key] {
                    if record.updatedAt > profile.updatedAt { record.apply(to: profile) }
                } else {
                    let profile = record.makeModel()
                    context.insert(profile)
                    byKey[record.key] = profile
                }
            }
            for profile in profiles {
                if let survivor = byKey[profile.key], survivor !== profile { context.delete(profile) }
            }
            try PersistenceController.reconcile(context: context)
            try context.save()
        } catch { context.rollback(); throw error }
    }
    private static func merge<M: PersistentModel, R>(_ records: [R], context: ModelContext, model: M.Type, id: KeyPath<M, UUID>, date: KeyPath<M, Date>, recordID: KeyPath<R, UUID>, recordDate: KeyPath<R, Date>, make: (R) -> M, apply: (R, M) -> Void) throws {
        var existing = Dictionary(try context.fetch(FetchDescriptor<M>()).map { ($0[keyPath: id], $0) }, uniquingKeysWith: { a, b in a[keyPath: date] >= b[keyPath: date] ? a : b })
        for record in records {
            let key = record[keyPath: recordID]
            if let item = existing[key] { if record[keyPath: recordDate] > item[keyPath: date] { apply(record, item) } }
            else { let item = make(record); context.insert(item); existing[key] = item }
        }
    }
}
