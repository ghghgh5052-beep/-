import Foundation
import SwiftData

struct TrainingSnapshot: Sendable {
    /// Current known exercises eligible for generation; archived/custom definitions are excluded.
    let exercises: [TrainingExercise]
    /// Retains known archived definitions so their completed history still affects recovery estimates.
    let recoveryExercises: [TrainingExercise]
    let history: [TrainingSetHistory]
    let unsupportedExerciseCount: Int
}

enum SmartTrainingStoreError: Error, LocalizedError {
    case invalidPreferences
    var errorDescription: String? {
        "اختر هدفًا ومستوى وأدوات صالحة، ومدة بين ١٥ و١٢٠ دقيقة، وزيادة وزن بين ٠٫٢٥ و١٠ كجم."
    }
}

@MainActor enum SmartTrainingStore {
    nonisolated static let profileKey = "smart-training"

    /// Central classification prevents UI/service checks drifting when exact machines are added.
    static func requiresExternalLoad(exerciseID: UUID) -> Bool {
        guard let metadata = SmartExerciseMetadata.forBuiltInID(exerciseID) else { return false }
        let loadedEquipment: Set<TrainingEquipment> = [.barbell, .dumbbell, .cable, .chestPress,
            .pecDeck, .legPress, .hackSquat, .legExtension, .legCurl, .calfRaise, .seatedCalf,
            .preacherCurl, .tricepsMachine, .rowMachine, .shoulderPress, .hipAbduction,
            .hipAdduction, .latPulldown, .seatedCableRow]
        return !metadata.requiredEquipment.isDisjoint(with: loadedEquipment)
    }

    static func loadPreferences(context: ModelContext, key: String = profileKey) throws -> TrainingPreferences {
        let records = try context.fetch(FetchDescriptor<TrainingProfile>())
        guard let profile = records.filter({ $0.key == key }).sorted(by: newerProfile).first else {
            return TrainingPreferences()
        }
        guard validProfile(goal: profile.goalRaw, level: profile.levelRaw,
                           equipment: profile.equipmentRaw, duration: profile.durationMinutes,
                           increment: profile.incrementKg),
              let goal = TrainingGoal(rawValue: profile.goalRaw),
              let level = TrainingLevel(rawValue: profile.levelRaw) else {
            throw SmartTrainingStoreError.invalidPreferences
        }
        return TrainingPreferences(goal: goal, level: level,
            equipment: Set(profile.equipmentRaw.split(separator: ",").compactMap {
                TrainingEquipment(rawValue: String($0))
            }), durationMinutes: profile.durationMinutes, incrementKg: profile.incrementKg)
    }

    static func savePreferences(_ preferences: TrainingPreferences, context: ModelContext, key: String = profileKey) throws {
        let equipment = preferences.equipment.map(\.rawValue).sorted().joined(separator: ",")
        guard validProfile(goal: preferences.goal.rawValue, level: preferences.level.rawValue,
                           equipment: equipment, duration: preferences.durationMinutes,
                           increment: preferences.incrementKg) else {
            throw SmartTrainingStoreError.invalidPreferences
        }
        // Preserve unrelated visible edits before beginning the profile transaction.
        try context.save()
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        do {
            let records = try context.fetch(FetchDescriptor<TrainingProfile>())
                .filter { $0.key == key }.sorted(by: newerProfile)
            let profile = records.first ?? TrainingProfile(key: key)
            if records.isEmpty { context.insert(profile) }
            profile.goalRaw = preferences.goal.rawValue
            profile.levelRaw = preferences.level.rawValue
            profile.equipmentRaw = equipment
            profile.durationMinutes = preferences.durationMinutes
            profile.incrementKg = preferences.incrementKg
            profile.updatedAt = .now
            for duplicate in records.dropFirst() { context.delete(duplicate) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func snapshot(context: ModelContext) throws -> TrainingSnapshot {
        let definitions = try context.fetch(FetchDescriptor<Exercise>())
        let definitionsByID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: {
            $0.updatedAt >= $1.updatedAt ? $0 : $1
        })
        let known: [(Exercise, TrainingExercise)] = definitionsByID.values.compactMap { exercise in
            guard !exercise.isCustom, let metadata = SmartExerciseMetadata.forBuiltInID(exercise.id) else {
                return nil
            }
            return (exercise, TrainingExercise(id: exercise.id, name: exercise.name,
                primaryMuscles: metadata.primaryMuscles, secondaryMuscles: metadata.secondaryMuscles,
                requiredEquipment: metadata.requiredEquipment, movementPattern: metadata.movementPattern,
                mode: metadata.mode, difficulty: metadata.difficulty, isFavorite: exercise.isFavorite))
        }
        let preferences = try context.fetch(FetchDescriptor<ExercisePreference>())
        let avoided = Set(preferences.filter(\.avoid).map(\.exerciseID))
        let measurements = try context.fetch(FetchDescriptor<SetMeasurement>())
        let measurementsByID = Dictionary(measurements.map { ($0.setID, $0) }, uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second })
        let preferencesByID = Dictionary(preferences.map { ($0.exerciseID, $0) }, uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second })
        let unsupportedSets = Set(measurements.filter { !["reps", "bodyweight"].contains($0.modeRaw) }.map(\.setID))
        let feedback = try context.fetch(FetchDescriptor<SessionFeedback>())
        let difficultSessions = Set(feedback.filter { $0.difficulty == 3 || $0.energy == 1 }.map(\.sessionID))
        let knownIDs = Set(known.map { $0.1.id })
        let finished = try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == "completed" }))
        let sessionsByID = Dictionary(finished.map { ($0.id, $0) }, uniquingKeysWith: {
            $0.updatedAt >= $1.updatedAt ? $0 : $1
        })
        let movements = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { sessionsByID[$0.sessionID] != nil && knownIDs.contains($0.exerciseID) }
        let movementsByID = Dictionary(movements.map { ($0.id, $0) }, uniquingKeysWith: {
            $0.updatedAt >= $1.updatedAt ? $0 : $1
        })
        let completedSets = try context.fetch(FetchDescriptor<LoggedSet>(
            predicate: #Predicate { $0.isCompleted }))
        let setsByID = Dictionary(completedSets.map { ($0.id, $0) }, uniquingKeysWith: {
            $0.updatedAt >= $1.updatedAt ? $0 : $1
        })
        let history: [TrainingSetHistory] = setsByID.values.compactMap { set in
            guard !unsupportedSets.contains(set.id), ["working", "drop", "failure"].contains(set.kindRaw),
                  set.weightKg.isFinite, (0...2_000).contains(set.weightKg), (1...10_000).contains(set.reps),
                  set.rpe.map({ $0.isFinite && (0...10).contains($0) }) ?? true,
                  let movement = movementsByID[set.sessionExerciseID],
                  let session = sessionsByID[movement.sessionID] else { return nil }
            let convention = measurementsByID[set.id]?.conventionRaw ?? "total"
            // Never suggest a one-dumbbell load using an old total-pair measurement.
            if let current = preferencesByID[movement.exerciseID], current.conventionRaw != convention { return nil }
            return TrainingSetHistory(sessionID: session.id, exerciseID: movement.exerciseID,
                date: set.completedAt ?? session.end ?? session.start, weightKg: set.weightKg,
                reps: set.reps, rpe: difficultSessions.contains(session.id) ? max(9, set.rpe ?? 0) : set.rpe, kind: set.kindRaw, isCompleted: true)
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.sessionID != $1.sessionID { return $0.sessionID.uuidString < $1.sessionID.uuidString }
            if $0.exerciseID != $1.exerciseID { return $0.exerciseID.uuidString < $1.exerciseID.uuidString }
            if $0.weightKg != $1.weightKg { return $0.weightKg < $1.weightKg }
            return $0.reps < $1.reps
        }
        let recentSessionIDs = Set(finished.filter { Date.now.timeIntervalSince($0.end ?? $0.start) >= 0 && Date.now.timeIntervalSince($0.end ?? $0.start) < 48 * 3600 }.map(\.id))
        let fatigued = Set(feedback.filter { recentSessionIDs.contains($0.sessionID) }.flatMap { $0.fatigueRaw.split(separator: ",").compactMap { MuscleRegion(rawValue: String($0)) } })
        let ordered = known.sorted { $0.1.id.uuidString < $1.1.id.uuidString }
        return TrainingSnapshot(exercises: ordered.filter { !$0.0.isArchived && !avoided.contains($0.0.id) && $0.1.primaryMuscles.isDisjoint(with: fatigued) }.map { $0.1 },
            recoveryExercises: ordered.map { $0.1 }, history: history,
            unsupportedExerciseCount: definitionsByID.values.filter {
                !$0.isArchived && ($0.isCustom || !knownIDs.contains($0.id))
            }.count)
    }

    static func validProfile(goal: String, level: String, equipment: String,
                             duration: Int, increment: Double) -> Bool {
        let tokens = equipment.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return TrainingGoal(rawValue: goal) != nil && TrainingLevel(rawValue: level) != nil
            && !tokens.isEmpty && Set(tokens).count == tokens.count
            && tokens.allSatisfy({ TrainingEquipment(rawValue: $0) != nil })
            && (15...120).contains(duration) && increment.isFinite && (0.25...10).contains(increment)
    }

    private static func newerProfile(_ lhs: TrainingProfile, _ rhs: TrainingProfile) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.id.uuidString > rhs.id.uuidString : lhs.updatedAt > rhs.updatedAt
    }
}
