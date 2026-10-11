import Foundation
import SwiftData

enum TrainingEditError: LocalizedError {
    case invalid, inactive, loggedExercise
    var errorDescription: String? {
        switch self {
        case .invalid: return "راجع القيم والتاريخ قبل الحفظ؛ لم تتغير بياناتك."
        case .inactive: return "هذا الخيار متاح للجلسات المحفوظة فقط."
        case .loggedExercise: return "لا يمكن استبدال تمرين له جولات مكتملة. أضف البديل كتمرين جديد لحفظ ما سجلته."
        }
    }
}

struct SessionSetEdit: Identifiable {
    let id: UUID
    var weightKg: Double
    var reps: Int
    var rpe: Double?
    var kindRaw: String
    var seconds: Double
    var distanceMeters: Double
    var assistanceKg: Double
    var modeRaw: String
    var conventionRaw: String
}

@MainActor enum TrainingEnhancementStore {
    static func transaction(context: ModelContext, commit: (ModelContext) throws -> Void = { try $0.save() },
                            changes: () throws -> Void) throws {
        try context.save()
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do { try changes(); try commit(context) }
        catch { context.rollback(); throw error }
    }

    static func defaultMode(exerciseID: UUID) -> SetTrackingMode {
        guard let metadata = SmartExerciseMetadata.forBuiltInID(exerciseID) else { return .reps }
        if metadata.mode == .hold { return .timed }
        if metadata.mode == .cardio { return .distance }
        return SmartTrainingStore.requiresExternalLoad(exerciseID: exerciseID) ? .reps : .bodyweight
    }

    static func measurement(set: LoggedSet, exerciseID: UUID, context: ModelContext) throws -> SetMeasurement {
        let all = try context.fetch(FetchDescriptor<SetMeasurement>())
        if let existing = all.filter({ $0.setID == set.id }).max(by: { $0.updatedAt < $1.updatedAt }) { return existing }
        let preference = try context.fetch(FetchDescriptor<ExercisePreference>())
            .filter { $0.exerciseID == exerciseID }.max(by: { $0.updatedAt < $1.updatedAt })
        let mode = preference.flatMap { SetTrackingMode(rawValue: $0.modeRaw) } ?? defaultMode(exerciseID: exerciseID)
        let defaultConvention = SmartExerciseMetadata.forBuiltInID(exerciseID)?.requiredEquipment.contains(.dumbbell) == true ? "perHand" : "total"
        let record = SetMeasurement(setID: set.id, modeRaw: mode.rawValue,
            conventionRaw: preference?.conventionRaw ?? defaultConvention)
        // Legacy completed sets retain their original meaning. New modes are applied only to pending sets.
        if set.isCompleted { record.modeRaw = "reps" }
        context.insert(record)
        if !set.isCompleted && (mode == .timed || mode == .distance) { set.reps = 0; set.weightKg = 0 }
        if !set.isCompleted && mode == .assisted { set.weightKg = 0 }
        return record
    }

    static func validMeasurement(_ value: SetMeasurement, set: LoggedSet) -> Bool {
        guard let mode = SetTrackingMode(rawValue: value.modeRaw), LoadConvention(rawValue: value.conventionRaw) != nil,
              value.seconds.isFinite, (0...86_400).contains(value.seconds),
              value.distanceMeters.isFinite, (0...1_000_000).contains(value.distanceMeters),
              value.assistanceKg.isFinite, (0...2_000).contains(value.assistanceKg) else { return false }
        switch mode {
        case .timed: return value.seconds > 0
        case .distance: return value.seconds > 0 && value.distanceMeters > 0
        case .assisted: return set.reps > 0 && value.assistanceKg > 0
        case .reps, .bodyweight: return set.reps > 0 && set.weightKg.isFinite && (0...2_000).contains(set.weightKg)
        }
    }

    static func edit(session: WorkoutSession, title: String, start: Date, duration: Double,
                     notes: String, excluded: Bool, edits: [SessionSetEdit], context: ModelContext,
                     commit: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard ["completed", "excluded"].contains(session.statusRaw) else { throw TrainingEditError.inactive }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
              duration.isFinite, (0...86_400).contains(duration), start <= .now,
              start.addingTimeInterval(duration) <= Date.now.addingTimeInterval(60),
              Set(edits.map(\.id)).count == edits.count else { throw TrainingEditError.invalid }
        let movements = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.sessionID == session.id }
        let byID = Dictionary(movements.map { ($0.id, $0.exerciseID) }, uniquingKeysWith: { first, _ in first })
        let sets = try context.fetch(FetchDescriptor<LoggedSet>()).filter { byID[$0.sessionExerciseID] != nil }
        let setsByID = Dictionary(sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard edits.allSatisfy({ setsByID[$0.id] != nil && $0.weightKg.isFinite && (0...2_000).contains($0.weightKg)
            && (0...10_000).contains($0.reps) && ($0.rpe.map { $0.isFinite && (1...10).contains($0) } ?? true)
            && ["working", "warmup", "drop", "failure"].contains($0.kindRaw)
            && $0.seconds.isFinite && (0...86_400).contains($0.seconds)
            && $0.distanceMeters.isFinite && (0...1_000_000).contains($0.distanceMeters)
            && $0.assistanceKg.isFinite && (0...2_000).contains($0.assistanceKg)
            && SetTrackingMode(rawValue: $0.modeRaw) != nil && LoadConvention(rawValue: $0.conventionRaw) != nil }) else {
            throw TrainingEditError.invalid
        }
        try transaction(context: context, commit: commit) {
            session.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            session.start = start; session.end = start.addingTimeInterval(duration)
            session.accumulatedPause = 0; session.pausedAt = nil; session.pauseEventsRaw = ""
            session.notes = notes; session.statusRaw = excluded ? "excluded" : "completed"; session.updatedAt = .now
            for value in edits {
                guard let set = setsByID[value.id], let exerciseID = byID[set.sessionExerciseID] else { continue }
                let measurement = try measurement(set: set, exerciseID: exerciseID, context: context)
                measurement.modeRaw = value.modeRaw; measurement.conventionRaw = value.conventionRaw
                measurement.seconds = value.seconds; measurement.distanceMeters = value.distanceMeters
                measurement.assistanceKg = value.assistanceKg; measurement.updatedAt = .now
                set.weightKg = value.modeRaw == "timed" || value.modeRaw == "distance" || value.modeRaw == "assisted" ? 0 : value.weightKg
                set.reps = value.modeRaw == "timed" || value.modeRaw == "distance" ? 0 : value.reps
                set.rpe = value.rpe; set.kindRaw = value.kindRaw; set.updatedAt = .now
                if set.isCompleted {
                    guard validMeasurement(measurement, set: set) else { throw TrainingEditError.invalid }
                    set.completedAt = session.end
                }
            }
            // Move unedited timestamps too, so dated edits change charts, recovery and PR chronology consistently.
            for set in sets where set.isCompleted { set.completedAt = session.end; set.updatedAt = .now }
            try PRService.rebuild(context: context, saveChanges: false)
        }
    }

    static func replace(item: SessionExercise, with definition: Exercise, context: ModelContext) throws {
        let id = item.id
        let sets = try context.fetch(FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.sessionExerciseID == id }))
        guard !sets.contains(where: \.isCompleted) else { throw TrainingEditError.loggedExercise }
        let sessionID = item.sessionID
        guard let session = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first,
              session.statusRaw == "active", !definition.isArchived else { throw TrainingEditError.inactive }
        let history = try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.statusRaw == "completed" }
            .sorted { $0.start > $1.start }
        let past = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.exerciseID == definition.id }
        let allSets = try context.fetch(FetchDescriptor<LoggedSet>())
        let prior = history.lazy.compactMap { session in past.first { $0.sessionID == session.id } }.first
        let previous = allSets.filter { $0.sessionExerciseID == prior?.id && $0.isCompleted && $0.kindRaw != "warmup" }.sorted { $0.order < $1.order }
        try transaction(context: context) {
            item.exerciseID = definition.id; item.name = definition.name; item.notes = definition.notes; item.updatedAt = .now
            let ids = Set(sets.map(\.id))
            for value in try context.fetch(FetchDescriptor<SetMeasurement>()) where ids.contains(value.setID) { context.delete(value) }
            for set in sets {
                let value = previous.indices.contains(set.order) ? previous[set.order] : previous.last
                set.weightKg = value?.weightKg ?? 0; set.reps = value?.reps ?? 10; set.rpe = nil; set.updatedAt = .now
                _ = try measurement(set: set, exerciseID: definition.id, context: context)
            }
            session.updatedAt = .now
        }
    }

    static func report(context: ModelContext, now: Date, calendar: Calendar, completedWeek: Bool) throws -> WeeklyReport {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.statusRaw == "completed" }
        let movements = try context.fetch(FetchDescriptor<SessionExercise>())
        let map = Dictionary(movements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let measurements = Dictionary(try context.fetch(FetchDescriptor<SetMeasurement>()).map { ($0.setID, $0) }, uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second })
        let sets = try context.fetch(FetchDescriptor<LoggedSet>()).filter { $0.isCompleted && $0.kindRaw != "warmup" }
        let samples = sets.compactMap { set -> ReportSet? in
            guard let item = map[set.sessionExerciseID] else { return nil }
            let measure = measurements[set.id]
            return ReportSet(sessionID: item.sessionID, exerciseID: item.exerciseID, name: item.name,
                weight: set.weightKg, reps: set.reps, mode: measure?.modeRaw ?? "reps", convention: measure?.conventionRaw ?? "total")
        }
        return WeeklyReportEngine.make(sessions: sessions.map { ReportSession(id: $0.id, date: $0.start) },
            sets: samples, now: now, calendar: calendar, completedWeek: completedWeek)
    }

    static func prescription(entry: TrainingExercise, preferences: TrainingPreferences,
                             snapshot: TrainingSnapshot, context: ModelContext) throws -> TrainingPrescription {
        let base = SmartTrainingEngine.prescription(for: entry, preferences: preferences, history: snapshot.history, now: .now)
        let programs = try context.fetch(FetchDescriptor<ProgressionProgram>())
        guard let program = programs.filter({ $0.exerciseID == entry.id && $0.enabled && $0.start <= .now
            && $0.start.addingTimeInterval(Double($0.weeks) * 7 * 86_400) > .now }).max(by: { $0.updatedAt < $1.updatedAt }) else { return base }
        let history = snapshot.history.filter { $0.exerciseID == entry.id && $0.date >= program.start }
        let feedback = try context.fetch(FetchDescriptor<SessionFeedback>())
        let latest = history.max(by: { $0.date < $1.date })
        let difficult = feedback.contains { $0.sessionID == latest?.sessionID && ($0.difficulty == 3 || $0.energy == 1) }
        let decision = DoubleProgressionEngine.decide(history: history, lower: program.lowerReps,
            upper: program.upperReps, targetSets: program.targetSets, increment: program.incrementKg, difficult: difficult, now: .now)
        return TrainingPrescription(exerciseID: base.exerciseID, name: base.name, sets: program.targetSets,
            reps: decision.reps, weightKg: decision.weightKg, restSeconds: base.restSeconds,
            reason: decision.reason, mode: base.mode)
    }
}
