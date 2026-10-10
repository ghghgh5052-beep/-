import XCTest
@testable import Fitness

final class CalculationTests: XCTestCase {
    func testOneRepMaxFormulasAndSingleRep() {
        XCTAssertEqual(WorkoutMath.epley(weight: 100, reps: 5), 116.6666667, accuracy: 0.0001)
        XCTAssertEqual(WorkoutMath.brzycki(weight: 100, reps: 5), 112.5, accuracy: 0.0001)
        XCTAssertEqual(WorkoutMath.epley(weight: 100, reps: 1), 100)
        XCTAssertEqual(WorkoutMath.brzycki(weight: 100, reps: 1), 100)
        XCTAssertEqual(WorkoutMath.estimatedOneRepMax(weight: 100, reps: 5, formula: .brzycki), 112.5)
    }

    func testInvalidSetValuesDoNotProduceNaNOrInfinity() {
        XCTAssertEqual(WorkoutMath.epley(weight: .nan, reps: 10), 0)
        XCTAssertEqual(WorkoutMath.epley(weight: -50, reps: 10), 0)
        XCTAssertEqual(WorkoutMath.brzycki(weight: 50, reps: 37), 0)
        XCTAssertEqual(WorkoutMath.brzycki(weight: 50, reps: 0), 0)
        XCTAssertEqual(WorkoutMath.volume(weight: .infinity, reps: 10), 0)
        XCTAssertEqual(WorkoutMath.volume(weight: 50, reps: -1), 0)
        XCTAssertEqual(WorkoutMath.volume(weight: 50, reps: 10), 500)
    }

    func testPlatePairsAndUnattainableRemainder() {
        let exact = PlateCalculator.calculate(targetWeight: 100)
        XCTAssertEqual(exact.platesPerSide, [25, 15])
        XCTAssertEqual(exact.achievedWeight, 100)
        XCTAssertTrue(exact.isExact)
        let remainder = PlateCalculator.calculate(targetWeight: 101)
        XCTAssertEqual(remainder.achievedWeight, 100)
        XCTAssertEqual(remainder.remainder, 1)
        let belowBar = PlateCalculator.calculate(targetWeight: 10)
        XCTAssertEqual(belowBar.platesPerSide, [])
        XCTAssertEqual(belowBar.remainder, -10)
    }

    func testPlateCalculatorFindsCombinationWhenGreedyWouldFail() {
        let result = PlateCalculator.calculate(targetWeight: 12, barWeight: 0, availablePlates: [4, 3])
        XCTAssertEqual(result.platesPerSide, [3, 3])
        XCTAssertTrue(result.isExact)
        XCTAssertEqual(PlateCalculator.calculate(targetWeight: 20, availablePlates: []).platesPerSide, [])
    }

    func testWarmupsAreAscendingRoundedAndBelowWorkingWeight() {
        let result = WarmupCalculator.calculate(workingWeight: 100)
        XCTAssertEqual(result.map(\.weight), [40, 60, 75, 85])
        XCTAssertEqual(result.map(\.reps), [10, 6, 4, 2])
        XCTAssertEqual(WarmupCalculator.calculate(workingWeight: 20), [])
        let light = WarmupCalculator.calculate(workingWeight: 25)
        XCTAssertEqual(light.map(\.weight), [20])
    }

    func testRecordsExcludeWarmupAndIncompleteSetsAndDoNotCountTies() {
        let date = Date(timeIntervalSince1970: 100)
        let previous = SetSnapshot(weight: 100, reps: 5, date: date)
        let same = SetSnapshot(weight: 100, reps: 5, date: date.addingTimeInterval(60))
        XCTAssertEqual(PREngine.records(for: same, previous: [previous]), [])
        let warmup = SetSnapshot(weight: 110, reps: 6, kindRaw: "warmup", date: date.addingTimeInterval(60))
        XCTAssertEqual(PREngine.records(for: warmup, previous: [previous]), [])
        let unfinished = SetSnapshot(weight: 110, reps: 6, completed: false, date: date.addingTimeInterval(60))
        XCTAssertEqual(PREngine.records(for: unfinished, previous: [previous]), [])
        let improvement = SetSnapshot(weight: 100, reps: 6, date: date.addingTimeInterval(60))
        XCTAssertEqual(Set(PREngine.records(for: improvement, previous: [previous]).map(\.kind)), [.reps, .estimated1RM])
    }

    func testRepetitionRecordIsSpecificToWeightAndFutureSetsDoNotSuppressRecords() {
        let current = SetSnapshot(weight: 100, reps: 5, date: Date(timeIntervalSince1970: 100))
        let lighter = SetSnapshot(weight: 50, reps: 20, date: Date(timeIntervalSince1970: 50))
        let future = SetSnapshot(weight: 200, reps: 5, date: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(Set(PREngine.records(for: current, previous: [lighter, future]).map(\.kind)),
                       [.weight, .reps, .estimated1RM])
        XCTAssertEqual(PREngine.history(sets: [future, current, lighter]),
                       PREngine.history(sets: [lighter, current, future]))
    }

    func testMovingAverageAndDailyStreak() {
        XCTAssertEqual(ProgressMath.movingAverage([70, 72, 74, 76], window: 3), [70, 71, 72, 74])
        XCTAssertEqual(ProgressMath.movingAverage([70], window: 0), [])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let today = Date(timeIntervalSince1970: 10 * 86_400)
        let dates = [today.addingTimeInterval(-86_400), today.addingTimeInterval(-2 * 86_400),
                     today.addingTimeInterval(-2 * 86_400 + 100), today.addingTimeInterval(-4 * 86_400)]
        XCTAssertEqual(ProgressMath.streak(dates: dates, today: today, calendar: calendar), 2)
        XCTAssertEqual(ProgressMath.streak(dates: dates + [today], today: today, calendar: calendar), 3)
    }

    func testEfficientHistoryMatchesIndividualRecordEvaluation() {
        let weights: [Double] = [100, 100.0005, 101, 0, 80, 120]
        let sets = (0..<500).map { index in
            SetSnapshot(weight: weights[index % weights.count], reps: index % 15 + 1,
                        kindRaw: index % 19 == 0 ? "warmup" : "working", completed: index % 23 != 0,
                        date: Date(timeIntervalSince1970: Double(index)))
        }
        var preceding: [SetSnapshot] = [], expected: [PRAchievement] = []
        for set in sets {
            expected += PREngine.records(for: set, previous: preceding)
            preceding.append(set)
        }
        XCTAssertEqual(PREngine.history(sets: Array(sets.reversed())), expected)
    }

    func testUnitConversionsRoundTrip() {
        XCTAssertEqual(WorkoutMath.kilograms(fromPounds: WorkoutMath.pounds(fromKilograms: 75)), 75, accuracy: 0.00001)
        XCTAssertEqual(WorkoutMath.centimeters(fromInches: WorkoutMath.inches(fromCentimeters: 180)), 180, accuracy: 0.00001)
    }
}
