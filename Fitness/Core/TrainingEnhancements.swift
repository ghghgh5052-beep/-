import Foundation

enum SetTrackingMode: String, CaseIterable, Codable, Sendable {
    case reps, timed, distance, bodyweight, assisted
    var arabicName: String {
        switch self {
        case .reps: return "وزن وتكرارات"
        case .timed: return "مدة الثبات"
        case .distance: return "وقت ومسافة"
        case .bodyweight: return "وزن الجسم"
        case .assisted: return "تكرارات بوزن مساعدة"
        }
    }
    var supportsWeightRecords: Bool { self == .reps || self == .bodyweight }
}

enum LoadConvention: String, CaseIterable, Codable, Sendable {
    case total, perHand, perSide
    var arabicName: String {
        switch self {
        case .total: return "الوزن الكلي، شامل البار إن وُجد"
        case .perHand: return "وزن الدمبل الواحد"
        case .perSide: return "وزن جهة واحدة، والتكرارات لكل جهة"
        }
    }
}

enum TrainingPlace: String, CaseIterable, Identifiable {
    case gym = "smart-training", home = "smart-home", travel = "smart-travel"
    var id: String { rawValue }
    var arabicName: String {
        switch self { case .gym: return "النادي"; case .home: return "البيت"; case .travel: return "السفر" }
    }
}

struct WeeklyLiftComparison: Identifiable, Equatable {
    let id: UUID
    let name: String
    let currentWeight: Double
    let previousWeight: Double
    let currentReps: Int
    let previousReps: Int
    let comparable: Bool
}

struct WeeklyReport: Equatable {
    let start: Date
    let end: Date
    let currentSessions: Int
    let previousSessions: Int
    let currentSets: Int
    let previousSets: Int
    let currentVolume: Double
    let previousVolume: Double
    let lifts: [WeeklyLiftComparison]
}

struct ReportSession: Equatable { let id: UUID; let date: Date }
struct ReportSet: Equatable {
    let sessionID: UUID
    let exerciseID: UUID
    let name: String
    let weight: Double
    let reps: Int
    let mode: String
    let convention: String
}

enum WeeklyReportEngine {
    /// Calendar arithmetic preserves local weeks across DST; the previous comparison uses elapsed weekdays.
    static func make(sessions: [ReportSession], sets: [ReportSet], now: Date,
                     calendar: Calendar, completedWeek: Bool = false) -> WeeklyReport {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let start = completedWeek ? (calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek) : thisWeek
        let end = completedWeek ? thisWeek : now
        let previous = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let previousEnd = calendar.date(byAdding: .day, value: -7, to: end) ?? end
        let currentIDs = Set(sessions.filter { $0.date >= start && $0.date < end }.map(\.id))
        let previousIDs = Set(sessions.filter { $0.date >= previous && $0.date < previousEnd }.map(\.id))
        let currentSets = sets.filter { currentIDs.contains($0.sessionID) }
        let previousSets = sets.filter { previousIDs.contains($0.sessionID) }
        func volume(_ entries: [ReportSet]) -> Double {
            entries.filter { ["reps", "bodyweight"].contains($0.mode) }.reduce(0) { $0 + WorkoutMath.volume(weight: $1.weight, reps: $1.reps) }
        }
        let currentByExercise = Dictionary(grouping: currentSets, by: \.exerciseID)
        let previousByExercise = Dictionary(grouping: previousSets, by: \.exerciseID)
        let comparisons = currentByExercise.compactMap { id, values -> WeeklyLiftComparison? in
            let eligible = values.filter { ["reps", "bodyweight"].contains($0.mode) && $0.weight > 0 && $0.reps > 0 }
            guard let best = eligible.max(by: { $0.weight == $1.weight ? $0.reps < $1.reps : $0.weight < $1.weight }) else { return nil }
            let previousBest = previousByExercise[id]?.filter { $0.mode == best.mode && $0.convention == best.convention && $0.weight > 0 && $0.reps > 0 }
                .max(by: { $0.weight == $1.weight ? $0.reps < $1.reps : $0.weight < $1.weight })
            return WeeklyLiftComparison(id: id, name: best.name, currentWeight: best.weight,
                previousWeight: previousBest?.weight ?? 0, currentReps: best.reps,
                previousReps: previousBest?.reps ?? 0, comparable: previousBest != nil)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return WeeklyReport(start: start, end: end, currentSessions: currentIDs.count,
            previousSessions: previousIDs.count, currentSets: currentSets.count, previousSets: previousSets.count,
            currentVolume: volume(currentSets), previousVolume: volume(previousSets), lifts: comparisons)
    }
}

struct ProgressionDecision: Equatable {
    let weightKg: Double?
    let reps: Int
    let reason: String
}

enum DoubleProgressionEngine {
    static func decide(history: [TrainingSetHistory], lower: Int, upper: Int, targetSets: Int,
                       increment: Double, difficult: Bool, now: Date) -> ProgressionDecision {
        let eligible = history.filter { $0.isValid(at: now) && $0.kind == "working" }
        guard let latest = eligible.max(by: { $0.date < $1.date }) else {
            return ProgressionDecision(weightKg: nil, reps: lower, reason: "ابدأ من الحد الأدنى للتكرارات واختر وزن بداية مناسبًا؛ لا يوجد سجل كافٍ.")
        }
        let last = eligible.filter { $0.sessionID == latest.sessionID }
        let weight = last.map(\.weightKg).min() ?? latest.weightKg
        let minimum = last.map(\.reps).min() ?? lower
        guard now.timeIntervalSince(latest.date) <= 21 * 86_400 else {
            return ProgressionDecision(weightKg: weight, reps: lower, reason: "مرّت فترة انقطاع. راجع وزن العودة بنفسك وابدأ من الحد الأدنى، دون زيادة تلقائية.")
        }
        guard !difficult && !last.contains(where: { ($0.rpe ?? 0) > 8 }) else {
            return ProgressionDecision(weightKg: weight, reps: max(lower, min(upper, minimum)), reason: "الجهد الأخير مرتفع؛ ثبّت الوزن والتكرارات وراجع استعدادك قبل الزيادة.")
        }
        let sameLoad = last.allSatisfy { abs($0.weightKg - weight) < 0.001 }
        if last.count >= targetSets && sameLoad && minimum >= upper && last.allSatisfy({ $0.rpe != nil && ($0.rpe ?? 10) <= 8 }) && weight > 0 {
            let next = weight + increment
            return ProgressionDecision(weightKg: min(2_000, next), reps: lower,
                reason: "وصلت جميع جولات العمل إلى الحد الأعلى بجهد مسجل مناسب. جرّب خطوة وزن واحدة وعد إلى الحد الأدنى للتكرارات.")
        }
        return ProgressionDecision(weightKg: weight, reps: min(upper, max(lower, minimum + 1)),
            reason: "ثبّت الوزن وجرّب تكرارًا إضافيًا ضمن نطاق البرنامج. زيادة الوزن تحتاج اكتمال الجولات والجهد المسجل.")
    }
}

enum ExerciseAlternativesEngine {
    static func alternatives(to source: TrainingExercise, candidates: [TrainingExercise],
                             available: Set<TrainingEquipment>, avoided: Set<UUID>) -> [TrainingExercise] {
        candidates.filter { candidate in
            candidate.id != source.id && !avoided.contains(candidate.id) && candidate.mode == source.mode
                && candidate.movementPattern == source.movementPattern
                && !candidate.primaryMuscles.isDisjoint(with: source.primaryMuscles)
                && candidate.requiredEquipment.isSubset(of: available.union([.bodyweight]))
                && candidate.difficulty.rank <= source.difficulty.rank
        }.sorted {
            let left = $0.primaryMuscles == source.primaryMuscles ? 1 : 0
            let right = $1.primaryMuscles == source.primaryMuscles ? 1 : 0
            if left != right { return left > right }
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
