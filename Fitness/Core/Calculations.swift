import Foundation

enum OneRepMaxFormula: String, CaseIterable, Codable, Hashable, Sendable {
    case epley, brzycki

    var arabicName: String {
        switch self {
        case .epley: return "إيبلي"
        case .brzycki: return "برزيكي"
        }
    }
}

enum WorkoutMath {
    static func epley(weight: Double, reps: Int) -> Double {
        guard weight.isFinite, weight > 0, reps > 0 else { return 0 }
        guard reps > 1 else { return weight }
        let result = weight * (1 + Double(reps) / 30)
        return result.isFinite ? result : 0
    }

    static func brzycki(weight: Double, reps: Int) -> Double {
        guard weight.isFinite, weight > 0, reps > 0, reps < 37 else { return 0 }
        let result = weight * 36 / Double(37 - reps)
        return result.isFinite ? result : 0
    }

    static func estimatedOneRepMax(weight: Double, reps: Int,
                                   formula: OneRepMaxFormula = .epley) -> Double {
        switch formula {
        case .epley: return epley(weight: weight, reps: reps)
        case .brzycki: return brzycki(weight: weight, reps: reps)
        }
    }

    static func volume(weight: Double, reps: Int) -> Double {
        guard weight.isFinite, weight >= 0, reps > 0 else { return 0 }
        let result = weight * Double(reps)
        return result.isFinite ? result : 0
    }

    static func volume(sets: [LoggedSet]) -> Double {
        sets.filter { $0.isCompleted && $0.kindRaw != "warmup" }.reduce(0) { $0 + volume(weight: $1.weightKg, reps: $1.reps) }
    }

    static func kilograms(fromPounds pounds: Double) -> Double { pounds / 2.2046226218 }
    static func pounds(fromKilograms kilograms: Double) -> Double { kilograms * 2.2046226218 }
    static func centimeters(fromInches inches: Double) -> Double { inches * 2.54 }
    static func inches(fromCentimeters centimeters: Double) -> Double { centimeters / 2.54 }
}

struct PlateResult: Equatable, Sendable {
    /// Each value represents one plate on each side; matching pairs are assumed available.
    let platesPerSide: [Double]
    let achievedWeight: Double
    let remainder: Double
    var isExact: Bool { abs(remainder) < 0.001 }
    var perSide: [Double] { platesPerSide }
}

enum PlateCalculator {
    /// Finds the heaviest attainable load at or below the requested weight.
    /// This coin-change algorithm also handles plate denominations for which greedy selection fails.
    static func calculate(targetWeight: Double, barWeight: Double = 20,
                          availablePlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]) -> PlateResult {
        guard targetWeight.isFinite, barWeight.isFinite, targetWeight >= 0, barWeight >= 0 else {
            return PlateResult(platesPerSide: [], achievedWeight: 0, remainder: 0)
        }
        guard targetWeight >= barWeight else {
            return PlateResult(platesPerSide: [], achievedWeight: barWeight,
                               remainder: targetWeight - barWeight)
        }
        // Hundredths of a unit are sufficient for standard kg and lb denominations.
        let perSide = (targetWeight - barWeight) / 2
        let denominations = Array(Set(availablePlates.filter {
            $0.isFinite && $0 >= 0.01 && $0 <= perSide + 0.0001
        })).sorted(by: >)
        guard perSide <= 10_000, !denominations.isEmpty else {
            return PlateResult(platesPerSide: [], achievedWeight: barWeight,
                               remainder: targetWeight - barWeight)
        }
        let capacity = Int((perSide * 100 + 0.0001).rounded(.down))
        let coins = denominations.map { Int(($0 * 100).rounded()) }
        var count = Array(repeating: Int.max, count: capacity + 1)
        var chosen = Array(repeating: -1, count: capacity + 1)
        count[0] = 0
        if capacity > 0 {
            for amount in 1...capacity {
                for (index, coin) in coins.enumerated() where coin <= amount && count[amount - coin] != Int.max {
                    let candidate = count[amount - coin] + 1
                    if candidate < count[amount] {
                        count[amount] = candidate
                        chosen[amount] = index
                    }
                }
            }
        }
        var amount = capacity
        while amount > 0 && chosen[amount] == -1 { amount -= 1 }
        let attained = amount
        var plates: [Double] = []
        while amount > 0 {
            let index = chosen[amount]
            guard coins.indices.contains(index) else { break }
            plates.append(denominations[index])
            amount -= coins[index]
        }
        let achieved = barWeight + Double(attained) / 100 * 2
        return PlateResult(platesPerSide: plates.sorted(by: >), achievedWeight: achieved,
                           remainder: max(0, targetWeight - achieved))
    }
}

struct WarmupSet: Identifiable, Equatable, Sendable {
    let id: Int
    let weight: Double
    let reps: Int
    let percentage: Double
    var weightKg: Double { weight }
}

enum WarmupCalculator {
    static func calculate(workingWeight: Double, barWeight: Double = 20,
                          increment: Double = 2.5) -> [WarmupSet] {
        guard workingWeight.isFinite, barWeight.isFinite, increment.isFinite,
              workingWeight > 0, barWeight >= 0, increment > 0 else { return [] }
        let stages: [(Double, Int)] = [(0.4, 10), (0.6, 6), (0.75, 4), (0.85, 2)]
        var result: [WarmupSet] = []
        for (percentage, reps) in stages {
            let weight = max(barWeight, (workingWeight * percentage / increment).rounded(.down) * increment)
            guard weight < workingWeight,
                  !result.contains(where: { abs($0.weight - weight) < 0.001 }) else { continue }
            result.append(WarmupSet(id: result.count, weight: weight, reps: reps, percentage: percentage))
        }
        return result
    }
}

enum PRKind: String, Codable, Hashable, Sendable { case weight, reps, estimated1RM }

struct SetSnapshot: Equatable, Sendable {
    var id: UUID
    var weight: Double
    var reps: Int
    var kindRaw: String
    var completed: Bool
    var date: Date

    init(id: UUID = UUID(), weight: Double, reps: Int, kindRaw: String = "working",
         completed: Bool = true, date: Date = Date()) {
        self.id = id; self.weight = weight; self.reps = reps
        self.kindRaw = kindRaw; self.completed = completed; self.date = date
    }

    var isEligible: Bool {
        completed && kindRaw != "warmup" && weight.isFinite && weight >= 0 && reps > 0
    }
}

struct PRAchievement: Equatable, Sendable {
    let setID: UUID
    let kind: PRKind
    let value: Double
    let weight: Double
    let date: Date
}

enum PREngine {
    /// Repetition records compare sets at the same weight; ties are not new records.
    static func records(for candidate: SetSnapshot, previous: [SetSnapshot],
                        formula: OneRepMaxFormula = .epley) -> [PRAchievement] {
        guard candidate.isEligible else { return [] }
        let history = previous.filter { $0.id != candidate.id && $0.isEligible && $0.date <= candidate.date }
        var result: [PRAchievement] = []
        func append(_ kind: PRKind, value: Double) {
            result.append(PRAchievement(setID: candidate.id, kind: kind,
                                        value: value, weight: candidate.weight, date: candidate.date))
        }
        if candidate.weight > (history.map(\.weight).max() ?? 0) { append(.weight, value: candidate.weight) }
        let sameWeight = history.filter { abs($0.weight - candidate.weight) < 0.001 }
        if candidate.reps > (sameWeight.map(\.reps).max() ?? 0) { append(.reps, value: Double(candidate.reps)) }
        let estimate = WorkoutMath.estimatedOneRepMax(weight: candidate.weight, reps: candidate.reps, formula: formula)
        let previousEstimate = history.map {
            WorkoutMath.estimatedOneRepMax(weight: $0.weight, reps: $0.reps, formula: formula)
        }.max() ?? 0
        if estimate > previousEstimate + 0.0001 { append(.estimated1RM, value: estimate) }
        return result
    }

    static func history(sets: [SetSnapshot], formula: OneRepMaxFormula = .epley) -> [PRAchievement] {
        let unique = Dictionary(sets.map { ($0.id, $0) }, uniquingKeysWith: { first, second in
            if first.date != second.date { return first.date > second.date ? first : second }
            if first.weight != second.weight { return first.weight > second.weight ? first : second }
            return first.reps >= second.reps ? first : second
        })
        let chronological = unique.values.filter(\.isEligible).sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
        let weights = Array(Set(chronological.map(\.weight))).sorted()
        let indexes = Dictionary(uniqueKeysWithValues: weights.enumerated().map { ($0.element, $0.offset) })
        var repetitionMax = RepetitionRangeMaximum(size: weights.count)
        var weightMax: Double = 0, estimateMax: Double = 0
        var achievements: [PRAchievement] = []
        for set in chronological {
            func append(_ kind: PRKind, _ value: Double) {
                achievements.append(PRAchievement(setID: set.id, kind: kind, value: value,
                                                  weight: set.weight, date: set.date))
            }
            if set.weight > weightMax { append(.weight, set.weight) }
            // Search bounds with the same absolute tolerance as records(for:previous:).
            let lower = boundary(in: weights) { $0 > set.weight - 0.001 }
            let upper = boundary(in: weights) { $0 >= set.weight + 0.001 }
            if set.reps > repetitionMax.maximum(in: lower..<upper) { append(.reps, Double(set.reps)) }
            let estimate = WorkoutMath.estimatedOneRepMax(weight: set.weight, reps: set.reps, formula: formula)
            if estimate > estimateMax + 0.0001 { append(.estimated1RM, estimate) }
            weightMax = max(weightMax, set.weight)
            estimateMax = max(estimateMax, estimate)
            if let index = indexes[set.weight] { repetitionMax.update(index: index, value: set.reps) }
        }
        return achievements
    }

    private static func boundary(in values: [Double], predicate: (Double) -> Bool) -> Int {
        var lower = 0, upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if predicate(values[middle]) { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }
}

/// Range maxima avoid rescanning the full workout history when rebuilding repetition PRs.
private struct RepetitionRangeMaximum {
    private let base: Int
    private var tree: [Int]
    init(size: Int) {
        var capacity = 1
        while capacity < size { capacity *= 2 }
        base = capacity
        tree = Array(repeating: 0, count: capacity * 2)
    }
    mutating func update(index: Int, value: Int) {
        var cursor = base + index
        tree[cursor] = max(tree[cursor], value)
        while cursor > 1 {
            cursor /= 2
            tree[cursor] = max(tree[cursor * 2], tree[cursor * 2 + 1])
        }
    }
    func maximum(in range: Range<Int>) -> Int {
        var lower = base + range.lowerBound, upper = base + range.upperBound, result = 0
        while lower < upper {
            if lower % 2 == 1 { result = max(result, tree[lower]); lower += 1 }
            if upper % 2 == 1 { upper -= 1; result = max(result, tree[upper]) }
            lower /= 2; upper /= 2
        }
        return result
    }
}

enum ProgressMath {
    static func movingAverage(_ values: [Double], window: Int = 7) -> [Double] {
        guard window > 0 else { return [] }
        var result: [Double] = []
        var sum: Double = 0
        for index in values.indices {
            sum += values[index].isFinite ? values[index] : 0
            if index >= window { sum -= values[index - window].isFinite ? values[index - window] : 0 }
            result.append(sum / Double(min(index + 1, window)))
        }
        return result
    }

    /// Counts consecutive workout days, accepting yesterday when today's session is still pending.
    static func streak(dates: [Date], today: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        let current = calendar.startOfDay(for: today)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: current) else { return 0 }
        var cursor = days.contains(current) ? current : yesterday
        var result = 0
        while days.contains(cursor) {
            result += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return result
    }

    static func weeklyStreak(dates: [Date], target: Int, today: Date = Date(),
                             calendar: Calendar = .current) -> Int {
        guard target > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return 0 }
        var counts: [Date: Int] = [:]
        for date in dates where date <= today {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            counts[start, default: 0] += 1
        }
        var cursor = thisWeek
        if counts[cursor, default: 0] < target {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }
        var result = 0
        while counts[cursor, default: 0] >= target {
            result += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return result
    }
}
