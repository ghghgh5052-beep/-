import CryptoKit
import Foundation
import SwiftData

enum PersistenceMode: String, Equatable, Sendable { case local, cloudKit, memory }

struct PersistenceResult {
    let container: ModelContainer
    let syncMode: PersistenceMode
    let warning: String?
    /// Technical detail is for diagnostics; the user-facing warning is always Arabic.
    let diagnostic: String?
}

enum PersistenceFailure: LocalizedError {
    case cannotOpenStore(String)
    var errorDescription: String? {
        "تعذّر فتح بياناتك المحفوظة. بقيت الملفات في مكانها؛ أعد المحاولة أو استعد نسخة احتياطية."
    }
}

@MainActor
enum PersistenceController {
    static var schema: Schema { Schema(versionedSchema: FitnessSchemaV2.self) }

    static func makeContainer(useCloudKit: Bool = false, inMemory: Bool = false,
                              storeURL: URL? = nil,
                              cloudKitContainerIdentifier: String? = nil) throws -> PersistenceResult {
        if inMemory {
            let configuration = ModelConfiguration("FitnessMemory", schema: schema,
                                                   isStoredInMemoryOnly: true,
                                                   cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: FitnessMigrationPlan.self,
                                               configurations: [configuration])
            return PersistenceResult(container: container, syncMode: .memory, warning: nil, diagnostic: nil)
        }
        let resolvedURL: URL
        if let storeURL {
            resolvedURL = storeURL
        } else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask, appropriateFor: nil, create: true)
            resolvedURL = support.appendingPathComponent("Fitness", isDirectory: true)
                .appendingPathComponent("Fitness.store")
        }
        try FileManager.default.createDirectory(at: resolvedURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let identifier = cloudKitContainerIdentifier
            ?? Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String
        var cloudFailure: Error?
        // CloudKit can terminate the process for a missing entitlement before Swift can catch it.
        // Check the signature produced by the user's signer, not the unsigned build configuration.
        if useCloudKit, let identifier, SigningCapabilities.current.allowsCloudKit(container: identifier) {
            do {
                let configuration = ModelConfiguration("Fitness", schema: schema, url: resolvedURL,
                                                       cloudKitDatabase: .private(identifier))
                let container = try ModelContainer(for: schema, migrationPlan: FitnessMigrationPlan.self,
                                                   configurations: [configuration])
                return PersistenceResult(container: container, syncMode: .cloudKit, warning: nil, diagnostic: nil)
            } catch {
                cloudFailure = error
            }
        }
        do {
            // Open the SAME store locally. Never delete, rename, truncate, or replace a failed store.
            let configuration = ModelConfiguration("Fitness", schema: schema, url: resolvedURL,
                                                   cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: FitnessMigrationPlan.self,
                                               configurations: [configuration])
            let warning = useCloudKit
                ? "مزامنة آي كلاود غير متاحة الآن. بياناتك محفوظة على هذا الجهاز."
                : nil
            return PersistenceResult(container: container, syncMode: .local, warning: warning,
                                     diagnostic: cloudFailure.map { String(describing: $0) })
        } catch {
            throw PersistenceFailure.cannotOpenStore(String(describing: error))
        }
    }

    /// SwiftData merges each CloudKit record. UUID deduplication covers concurrent device seeding/imports.
    /// Entire records use last-writer-wins; equal timestamps use a deterministic full-content tie break.
    @discardableResult
    static func reconcile(context: ModelContext) throws -> Int {
        var removed = 0
        removed += try deduplicate(context, type: Exercise.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.name, $0.primaryMuscleRaw, $0.secondaryMusclesRaw,
                         $0.equipmentRaw, $0.kindRaw, $0.notes, $0.mediaURL,
                         String($0.isFavorite), String($0.isCustom), String($0.isArchived)])
        }
        removed += try deduplicate(context, type: WorkoutPlan.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.name, $0.notes, String($0.isArchived), String($0.cycleWeeks),
                         String($0.deloadEvery), date($0.programStart), String($0.isActive)])
        }
        removed += try deduplicate(context, type: PlanDay.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.planID.uuidString, String($0.weekday), String($0.week),
                         String($0.isRest), $0.title])
        }
        removed += try deduplicate(context, type: PlanExercise.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.dayID.uuidString, $0.exerciseID.uuidString, String($0.order),
                         String($0.targetSets), String($0.targetReps), String($0.restSeconds), $0.groupID])
        }
        removed += try deduplicate(context, type: WorkoutSession.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.planDayID?.uuidString ?? "", $0.title, date($0.start),
                         date($0.end), date($0.pausedAt), String($0.accumulatedPause), $0.pauseEventsRaw,
                         $0.notes, $0.statusRaw, String($0.healthExported)])
        }
        removed += try deduplicate(context, type: SessionExercise.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.sessionID.uuidString, $0.exerciseID.uuidString,
                         $0.name, String($0.order), $0.notes, $0.groupID, String($0.restSeconds)])
        }
        removed += try deduplicate(context, type: LoggedSet.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.sessionExerciseID.uuidString, String($0.order), String($0.weightKg),
                         String($0.reps), $0.rpe.map { String($0) } ?? "", $0.kindRaw,
                         String($0.isCompleted), date($0.completedAt)])
        }
        removed += try deduplicate(context, type: BodyMetric.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, date($0.date), number($0.weightKg), number($0.fatPercent),
                         number($0.chestCm), number($0.waistCm), number($0.armCm), number($0.hipsCm), number($0.thighCm)])
        }
        removed += try deduplicate(context, type: ProgressPhoto.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            let digest = $0.imageData.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
            return fingerprint([$0.id.uuidString, date($0.date), digest, $0.notes])
        }
        removed += try deduplicate(context, type: FitnessGoal.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.title, $0.kindRaw, String($0.targetValue),
                         $0.exerciseID?.uuidString ?? "", date($0.deadline), date($0.createdAt)])
        }
        removed += try deduplicate(context, type: WorkoutReminder.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.kindRaw, String($0.hour), String($0.minute),
                         $0.weekdaysRaw, String($0.enabled)])
        }
        removed += try deduplicate(context, type: UserPreferences.self, key: { $0.key }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.key, String($0.useArabicDigits), $0.weightUnit, $0.lengthUnit,
                         String($0.defaultRestSeconds), String($0.weekStart), $0.theme, $0.accent])
        }
        removed += try deduplicate(context, type: PersonalRecord.self, key: { $0.id.uuidString }, updated: { $0.updatedAt }) {
            fingerprint([$0.id.uuidString, $0.exerciseID.uuidString, $0.sessionID?.uuidString ?? "",
                         $0.setID?.uuidString ?? "", $0.kindRaw, String($0.value), String($0.weightKg),
                         date($0.achievedAt), $0.formulaRaw])
        }
        // Concurrent selection of two distinct plans must still leave one active schedule.
        let activePlans = try context.fetch(FetchDescriptor<WorkoutPlan>()).filter { $0.isActive && !$0.isArchived }
        let orderedPlans = activePlans.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString > $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }
        for plan in orderedPlans.dropFirst() { plan.isActive = false }
        if removed > 0 || orderedPlans.count > 1 { try context.save() }
        return removed
    }

    private static func deduplicate<T: PersistentModel>(
        _ context: ModelContext, type: T.Type, key: (T) -> String,
        updated: (T) -> Date, fingerprint: (T) -> String
    ) throws -> Int {
        let groups = Dictionary(grouping: try context.fetch(FetchDescriptor<T>()), by: key)
        var removed = 0
        for copies in groups.values where copies.count > 1 {
            let ordered = copies.sorted {
                let first = updated($0), second = updated($1)
                return first == second ? fingerprint($0) > fingerprint($1) : first > second
            }
            for loser in ordered.dropFirst() {
                context.delete(loser)
                removed += 1
            }
        }
        return removed
    }

    private static func fingerprint(_ fields: [String]) -> String {
        (try? JSONEncoder().encode(fields)).map { $0.base64EncodedString() } ?? fields.joined(separator: "\u{001F}")
    }
    private static func date(_ value: Date?) -> String { value.map { String($0.timeIntervalSince1970) } ?? "" }
    private static func number(_ value: Double?) -> String { value.map { String($0) } ?? "" }
}

@MainActor
enum PRService {
    /// Rebuild from completed sessions so incomplete workouts and warm-up sets never create permanent PRs.
    /// Stable IDs retain sync identity and make rebuilding after import or deletion idempotent.
    @discardableResult
    static func rebuild(context: ModelContext, formula: OneRepMaxFormula = .epley) throws -> Int {
        let completed = Dictionary(try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.statusRaw == "completed" }.map { ($0.id, $0) }, uniquingKeysWith: { first, second in
                first.updatedAt >= second.updatedAt ? first : second
            })
        let exercises = try context.fetch(FetchDescriptor<SessionExercise>()).filter { completed[$0.sessionID] != nil }
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, second in
            first.updatedAt >= second.updatedAt ? first : second
        })
        let sets = try context.fetch(FetchDescriptor<LoggedSet>()).filter { $0.isCompleted && byID[$0.sessionExerciseID] != nil }
        let grouped = Dictionary(grouping: sets, by: { byID[$0.sessionExerciseID]?.exerciseID })
        let existing = try context.fetch(FetchDescriptor<PersonalRecord>())
        var records = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, second in
            first.updatedAt >= second.updatedAt ? first : second
        })
        var retained: Set<UUID> = []
        for (exerciseID, exerciseSets) in grouped {
            guard let exerciseID else { continue }
            let snapshots = exerciseSets.map {
                SetSnapshot(id: $0.id, weight: $0.weightKg, reps: $0.reps, kindRaw: $0.kindRaw,
                            completed: $0.isCompleted, date: $0.completedAt ?? $0.updatedAt)
            }
            let setLookup = Dictionary(exerciseSets.map { ($0.id, $0) }, uniquingKeysWith: { first, second in
                first.updatedAt >= second.updatedAt ? first : second
            })
            for achievement in PREngine.history(sets: snapshots, formula: formula) {
                let id = stableID("\(achievement.setID.uuidString):\(achievement.kind.rawValue):\(formula.rawValue)")
                retained.insert(id)
                let record = records[id] ?? PersonalRecord(id: id)
                if records[id] == nil { context.insert(record); records[id] = record }
                let sourceExerciseID = setLookup[achievement.setID]?.sessionExerciseID
                let sessionID = sourceExerciseID.flatMap { byID[$0]?.sessionID }
                if record.exerciseID == exerciseID, record.sessionID == sessionID,
                   record.setID == achievement.setID, record.kindRaw == achievement.kind.rawValue,
                   record.value == achievement.value, record.weightKg == achievement.weight,
                   record.achievedAt == achievement.date, record.formulaRaw == formula.rawValue,
                   record.updatedAt == achievement.date { continue }
                record.exerciseID = exerciseID
                record.sessionID = sessionID
                record.setID = achievement.setID
                record.kindRaw = achievement.kind.rawValue
                record.value = achievement.value
                record.weightKg = achievement.weight
                record.achievedAt = achievement.date
                record.formulaRaw = formula.rawValue
                record.updatedAt = achievement.date
            }
        }
        for obsolete in existing where !retained.contains(obsolete.id) { context.delete(obsolete) }
        if context.hasChanges { try context.save() }
        return retained.count
    }

    private static func stableID(_ value: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(value.utf8)))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
