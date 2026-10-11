import Foundation
import SwiftData

/// The first shipped schema is retained unchanged so existing stores can migrate safely.
enum FitnessSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Exercise.self, WorkoutPlan.self, PlanDay.self, PlanExercise.self,
         WorkoutSession.self, SessionExercise.self, LoggedSet.self, BodyMetric.self,
         ProgressPhoto.self, FitnessGoal.self, WorkoutReminder.self, UserPreferences.self]
    }

    // Scalar UUID references avoid mandatory relationships and are compatible with CloudKit.
    // Property defaults are declared here, rather than only in initializers, for CloudKit.
    @Model final class Exercise {
        var id: UUID = UUID()
        var name: String = ""
        var primaryMuscleRaw: String = "صدر"
        var secondaryMusclesRaw: String = ""
        var equipmentRaw: String = "وزن الجسم"
        var kindRaw: String = "قوة"
        var notes: String = ""
        var mediaURL: String = ""
        var isFavorite: Bool = false
        var isCustom: Bool = false
        var isArchived: Bool = false
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), name: String = "", primaryMuscleRaw: String = "صدر",
             secondaryMusclesRaw: String = "", equipmentRaw: String = "وزن الجسم",
             kindRaw: String = "قوة", notes: String = "", mediaURL: String = "",
             isFavorite: Bool = false, isCustom: Bool = false, isArchived: Bool = false,
             updatedAt: Date = Date()) {
            self.id = id; self.name = name; self.primaryMuscleRaw = primaryMuscleRaw
            self.secondaryMusclesRaw = secondaryMusclesRaw; self.equipmentRaw = equipmentRaw
            self.kindRaw = kindRaw; self.notes = notes; self.mediaURL = mediaURL
            self.isFavorite = isFavorite; self.isCustom = isCustom; self.isArchived = isArchived
            self.updatedAt = updatedAt
        }
    }

    @Model final class WorkoutPlan {
        var id: UUID = UUID()
        var name: String = ""
        var notes: String = ""
        var isArchived: Bool = false
        var cycleWeeks: Int = 1
        var deloadEvery: Int = 0
        var programStart: Date = Date()
        var isActive: Bool = false
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), name: String = "", notes: String = "", isArchived: Bool = false,
             cycleWeeks: Int = 1, deloadEvery: Int = 0, programStart: Date = Date(),
             isActive: Bool = false, updatedAt: Date = Date()) {
            self.id = id; self.name = name; self.notes = notes; self.isArchived = isArchived
            self.cycleWeeks = cycleWeeks; self.deloadEvery = deloadEvery
            self.programStart = programStart; self.isActive = isActive; self.updatedAt = updatedAt
        }
    }

    @Model final class PlanDay {
        var id: UUID = UUID()
        var planID: UUID = UUID()
        var weekday: Int = 7
        var week: Int = 1
        var isRest: Bool = false
        var title: String = ""
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), planID: UUID = UUID(), weekday: Int = 7, week: Int = 1,
             isRest: Bool = false, title: String = "", updatedAt: Date = Date()) {
            self.id = id; self.planID = planID; self.weekday = weekday; self.week = week
            self.isRest = isRest; self.title = title; self.updatedAt = updatedAt
        }
    }

    @Model final class PlanExercise {
        var id: UUID = UUID()
        var dayID: UUID = UUID()
        var exerciseID: UUID = UUID()
        var order: Int = 0
        var targetSets: Int = 3
        var targetReps: Int = 10
        var restSeconds: Int = 90
        var groupID: String = ""
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), dayID: UUID = UUID(), exerciseID: UUID = UUID(), order: Int = 0,
             targetSets: Int = 3, targetReps: Int = 10, restSeconds: Int = 90,
             groupID: String = "", updatedAt: Date = Date()) {
            self.id = id; self.dayID = dayID; self.exerciseID = exerciseID; self.order = order
            self.targetSets = targetSets; self.targetReps = targetReps; self.restSeconds = restSeconds
            self.groupID = groupID; self.updatedAt = updatedAt
        }
    }

    @Model final class WorkoutSession {
        var id: UUID = UUID()
        var planDayID: UUID?
        var title: String = "تمرين حر"
        var start: Date = Date()
        var end: Date?
        var pausedAt: Date?
        var accumulatedPause: Double = 0
        var pauseEventsRaw: String = ""
        var notes: String = ""
        var statusRaw: String = "active"
        var healthExported: Bool = false
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), planDayID: UUID? = nil, title: String = "تمرين حر",
             start: Date = Date(), end: Date? = nil, pausedAt: Date? = nil,
             accumulatedPause: Double = 0, pauseEventsRaw: String = "", notes: String = "", statusRaw: String = "active",
             healthExported: Bool = false, updatedAt: Date = Date()) {
            self.id = id; self.planDayID = planDayID; self.title = title; self.start = start
            self.end = end; self.pausedAt = pausedAt; self.accumulatedPause = accumulatedPause
            self.pauseEventsRaw = pauseEventsRaw
            self.notes = notes; self.statusRaw = statusRaw; self.healthExported = healthExported
            self.updatedAt = updatedAt
        }

        func activeDuration(at now: Date = Date()) -> TimeInterval {
            let elapsed = (end ?? now).timeIntervalSince(start)
            let pendingPause = pausedAt.map { max(0, (end ?? now).timeIntervalSince($0)) } ?? 0
            return max(0, elapsed - max(0, accumulatedPause) - pendingPause)
        }
    }

    @Model final class SessionExercise {
        var id: UUID = UUID()
        var sessionID: UUID = UUID()
        var exerciseID: UUID = UUID()
        var name: String = ""
        var order: Int = 0
        var notes: String = ""
        var groupID: String = ""
        var restSeconds: Int = 90
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), sessionID: UUID = UUID(), exerciseID: UUID = UUID(),
             name: String = "", order: Int = 0, notes: String = "", groupID: String = "",
             restSeconds: Int = 90, updatedAt: Date = Date()) {
            self.id = id; self.sessionID = sessionID; self.exerciseID = exerciseID
            self.name = name; self.order = order; self.notes = notes; self.groupID = groupID
            self.restSeconds = restSeconds; self.updatedAt = updatedAt
        }
    }

    @Model final class LoggedSet {
        var id: UUID = UUID()
        var sessionExerciseID: UUID = UUID()
        var order: Int = 0
        var weightKg: Double = 0
        var reps: Int = 10
        var rpe: Double?
        var kindRaw: String = "working"
        var isCompleted: Bool = false
        var completedAt: Date?
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), sessionExerciseID: UUID = UUID(), order: Int = 0,
             weightKg: Double = 0, reps: Int = 10, rpe: Double? = nil, kindRaw: String = "working",
             isCompleted: Bool = false, completedAt: Date? = nil, updatedAt: Date = Date()) {
            self.id = id; self.sessionExerciseID = sessionExerciseID; self.order = order
            self.weightKg = weightKg; self.reps = reps; self.rpe = rpe; self.kindRaw = kindRaw
            self.isCompleted = isCompleted; self.completedAt = completedAt; self.updatedAt = updatedAt
        }
    }

    @Model final class BodyMetric {
        var id: UUID = UUID()
        var date: Date = Date()
        var weightKg: Double?
        var fatPercent: Double?
        var chestCm: Double?
        var waistCm: Double?
        var armCm: Double?
        var hipsCm: Double?
        var thighCm: Double?
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), date: Date = Date(), weightKg: Double? = nil,
             fatPercent: Double? = nil, chestCm: Double? = nil, waistCm: Double? = nil,
             armCm: Double? = nil, hipsCm: Double? = nil, thighCm: Double? = nil,
             updatedAt: Date = Date()) {
            self.id = id; self.date = date; self.weightKg = weightKg; self.fatPercent = fatPercent
            self.chestCm = chestCm; self.waistCm = waistCm; self.armCm = armCm
            self.hipsCm = hipsCm; self.thighCm = thighCm; self.updatedAt = updatedAt
        }
    }

    @Model final class ProgressPhoto {
        var id: UUID = UUID()
        var date: Date = Date()
        @Attribute(.externalStorage) var imageData: Data?
        var notes: String = ""
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), date: Date = Date(), imageData: Data? = nil,
             notes: String = "", updatedAt: Date = Date()) {
            self.id = id; self.date = date; self.imageData = imageData
            self.notes = notes; self.updatedAt = updatedAt
        }
    }

    @Model final class FitnessGoal {
        var id: UUID = UUID()
        var title: String = ""
        var kindRaw: String = "weeklyWorkouts"
        var targetValue: Double = 3
        var exerciseID: UUID?
        var deadline: Date?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), title: String = "", kindRaw: String = "weeklyWorkouts",
             targetValue: Double = 3, exerciseID: UUID? = nil, deadline: Date? = nil,
             createdAt: Date = Date(), updatedAt: Date = Date()) {
            self.id = id; self.title = title; self.kindRaw = kindRaw; self.targetValue = targetValue
            self.exerciseID = exerciseID; self.deadline = deadline
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }
    }

    @Model final class WorkoutReminder {
        var id: UUID = UUID()
        var kindRaw: String = "workout"
        var hour: Int = 18
        var minute: Int = 0
        var weekdaysRaw: String = "7,2,4"
        var enabled: Bool = true
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), kindRaw: String = "workout", hour: Int = 18, minute: Int = 0,
             weekdaysRaw: String = "7,2,4", enabled: Bool = true, updatedAt: Date = Date()) {
            self.id = id; self.kindRaw = kindRaw; self.hour = hour; self.minute = minute
            self.weekdaysRaw = weekdaysRaw; self.enabled = enabled; self.updatedAt = updatedAt
        }

        var weekdays: [Int] {
            Array(Set(weekdaysRaw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })).sorted()
        }
    }

    @Model final class UserPreferences {
        var id: UUID = UUID()
        var key: String = "settings"
        var useArabicDigits: Bool = true
        var weightUnit: String = "kg"
        var lengthUnit: String = "cm"
        var defaultRestSeconds: Int = 90
        var weekStart: Int = 7
        var theme: String = "system"
        var accent: String = "mint"
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), key: String = "settings", useArabicDigits: Bool = true,
             weightUnit: String = "kg", lengthUnit: String = "cm", defaultRestSeconds: Int = 90,
             weekStart: Int = 7, theme: String = "system", accent: String = "mint",
             updatedAt: Date = Date()) {
            self.id = id; self.key = key; self.useArabicDigits = useArabicDigits
            self.weightUnit = weightUnit; self.lengthUnit = lengthUnit
            self.defaultRestSeconds = defaultRestSeconds; self.weekStart = weekStart
            self.theme = theme; self.accent = accent; self.updatedAt = updatedAt
        }
    }
}

/// V2 adds persistent PR history without altering any V1 entity or deleting its data.
enum FitnessSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        FitnessSchemaV1.models + [PersonalRecord.self]
    }

    @Model final class PersonalRecord {
        var id: UUID = UUID()
        var exerciseID: UUID = UUID()
        var sessionID: UUID?
        var setID: UUID?
        var kindRaw: String = "estimated1RM"
        var value: Double = 0
        var weightKg: Double = 0
        var achievedAt: Date = Date()
        var formulaRaw: String = "epley"
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), exerciseID: UUID = UUID(), sessionID: UUID? = nil,
             setID: UUID? = nil, kindRaw: String = "estimated1RM", value: Double = 0,
             weightKg: Double = 0, achievedAt: Date = Date(), formulaRaw: String = "epley",
             updatedAt: Date = Date()) {
            self.id = id; self.exerciseID = exerciseID; self.sessionID = sessionID; self.setID = setID
            self.kindRaw = kindRaw; self.value = value; self.weightKg = weightKg
            self.achievedAt = achievedAt; self.formulaRaw = formulaRaw; self.updatedAt = updatedAt
        }
    }
}

/// V3 is additive: shipped V1/V2 entities remain unchanged and keep every UUID reference.
enum FitnessSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        FitnessSchemaV2.models + [TrainingProfile.self]
    }

    @Model final class TrainingProfile {
        var id: UUID = UUID()
        var key: String = "smart-training"
        var goalRaw: String = "hypertrophy"
        var levelRaw: String = "beginner"
        var equipmentRaw: String = "bodyweight"
        var durationMinutes: Int = 45
        var incrementKg: Double = 2.5
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), key: String = "smart-training", goalRaw: String = "hypertrophy",
             levelRaw: String = "beginner", equipmentRaw: String = "bodyweight",
             durationMinutes: Int = 45, incrementKg: Double = 2.5, updatedAt: Date = Date()) {
            self.id = id; self.key = key; self.goalRaw = goalRaw; self.levelRaw = levelRaw
            self.equipmentRaw = equipmentRaw; self.durationMinutes = durationMinutes
            self.incrementKg = incrementKg; self.updatedAt = updatedAt
        }
    }
}

/// V4 adds optional training detail without changing any shipped entity or store identity.
enum FitnessSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        FitnessSchemaV3.models + [SessionFeedback.self, SetMeasurement.self, ExercisePreference.self, ProgressionProgram.self]
    }

    @Model final class SessionFeedback {
        var id: UUID = UUID()
        var sessionID: UUID = UUID()
        var difficulty: Int = 0
        var energy: Int = 0
        var fatigueRaw: String = ""
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), sessionID: UUID = UUID(), difficulty: Int = 0,
             energy: Int = 0, fatigueRaw: String = "", updatedAt: Date = Date()) {
            self.id = id; self.sessionID = sessionID; self.difficulty = difficulty
            self.energy = energy; self.fatigueRaw = fatigueRaw; self.updatedAt = updatedAt
        }
    }

    @Model final class SetMeasurement {
        var id: UUID = UUID()
        var setID: UUID = UUID()
        var modeRaw: String = "reps"
        var seconds: Double = 0
        var distanceMeters: Double = 0
        var assistanceKg: Double = 0
        var conventionRaw: String = "total"
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), setID: UUID = UUID(), modeRaw: String = "reps", seconds: Double = 0,
             distanceMeters: Double = 0, assistanceKg: Double = 0,
             conventionRaw: String = "total", updatedAt: Date = Date()) {
            self.id = id; self.setID = setID; self.modeRaw = modeRaw; self.seconds = seconds
            self.distanceMeters = distanceMeters; self.assistanceKg = assistanceKg
            self.conventionRaw = conventionRaw; self.updatedAt = updatedAt
        }
    }

    @Model final class ExercisePreference {
        var id: UUID = UUID()
        var exerciseID: UUID = UUID()
        var avoid: Bool = false
        var modeRaw: String = "reps"
        var conventionRaw: String = "total"
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), exerciseID: UUID = UUID(), avoid: Bool = false,
             modeRaw: String = "reps", conventionRaw: String = "total", updatedAt: Date = Date()) {
            self.id = id; self.exerciseID = exerciseID; self.avoid = avoid
            self.modeRaw = modeRaw; self.conventionRaw = conventionRaw; self.updatedAt = updatedAt
        }
    }

    @Model final class ProgressionProgram {
        var id: UUID = UUID()
        var exerciseID: UUID = UUID()
        var lowerReps: Int = 8
        var upperReps: Int = 12
        var targetSets: Int = 3
        var incrementKg: Double = 2.5
        var weeks: Int = 8
        var start: Date = Date()
        var enabled: Bool = true
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), exerciseID: UUID = UUID(), lowerReps: Int = 8, upperReps: Int = 12,
             targetSets: Int = 3, incrementKg: Double = 2.5, weeks: Int = 8, start: Date = Date(),
             enabled: Bool = true, updatedAt: Date = Date()) {
            self.id = id; self.exerciseID = exerciseID; self.lowerReps = lowerReps; self.upperReps = upperReps
            self.targetSets = targetSets; self.incrementKg = incrementKg; self.weeks = weeks
            self.start = start; self.enabled = enabled; self.updatedAt = updatedAt
        }
    }
}

enum FitnessMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FitnessSchemaV1.self, FitnessSchemaV2.self, FitnessSchemaV3.self, FitnessSchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: FitnessSchemaV1.self, toVersion: FitnessSchemaV2.self),
         .lightweight(fromVersion: FitnessSchemaV2.self, toVersion: FitnessSchemaV3.self),
         .lightweight(fromVersion: FitnessSchemaV3.self, toVersion: FitnessSchemaV4.self)]
    }
}

typealias Exercise = FitnessSchemaV1.Exercise
typealias WorkoutPlan = FitnessSchemaV1.WorkoutPlan
typealias PlanDay = FitnessSchemaV1.PlanDay
typealias PlanExercise = FitnessSchemaV1.PlanExercise
typealias WorkoutSession = FitnessSchemaV1.WorkoutSession
typealias SessionExercise = FitnessSchemaV1.SessionExercise
typealias LoggedSet = FitnessSchemaV1.LoggedSet
typealias BodyMetric = FitnessSchemaV1.BodyMetric
typealias ProgressPhoto = FitnessSchemaV1.ProgressPhoto
typealias FitnessGoal = FitnessSchemaV1.FitnessGoal
typealias WorkoutReminder = FitnessSchemaV1.WorkoutReminder
typealias PersonalRecord = FitnessSchemaV2.PersonalRecord
typealias UserPreferences = FitnessSchemaV1.UserPreferences
typealias TrainingProfile = FitnessSchemaV3.TrainingProfile
typealias SessionFeedback = FitnessSchemaV4.SessionFeedback
typealias SetMeasurement = FitnessSchemaV4.SetMeasurement
typealias ExercisePreference = FitnessSchemaV4.ExercisePreference
typealias ProgressionProgram = FitnessSchemaV4.ProgressionProgram
