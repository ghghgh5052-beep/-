import XCTest
@testable import Fitness

final class SmartTrainingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func exercise(_ code: Int, favorite: Bool = false) throws -> TrainingExercise {
        let id = SeedCatalog.stableID(namespace: 1, code: code)
        let metadata = try XCTUnwrap(SmartExerciseMetadata.forBuiltInID(id))
        let entry = try XCTUnwrap(SeedCatalog.entries.first { $0.code == code })
        return TrainingExercise(id: id, name: entry.name, primaryMuscles: metadata.primaryMuscles,
                                secondaryMuscles: metadata.secondaryMuscles,
                                requiredEquipment: metadata.requiredEquipment,
                                movementPattern: metadata.movementPattern, mode: metadata.mode,
                                difficulty: metadata.difficulty, isFavorite: favorite)
    }

    private func history(for exercise: TrainingExercise, count: Int = 3, weight: Double = 100,
                         reps: Int = 12, rpe: Double? = 7, ageDays: Double = 1,
                         kind: String = "working", completed: Bool = true) -> [TrainingSetHistory] {
        let sessionID = SeedCatalog.stableID(namespace: 9, code: 1)
        return (0..<count).map { index in
            TrainingSetHistory(sessionID: sessionID, exerciseID: exercise.id,
                               date: now.addingTimeInterval(-ageDays * 86_400 + Double(index)),
                               weightKg: weight, reps: reps, rpe: rpe, kind: kind, isCompleted: completed)
        }
    }

    func testEveryBuiltInHasSpecificEquipmentAndMuscleMetadata() throws {
        for entry in SeedCatalog.entries {
            let item = try exercise(entry.code)
            XCTAssertFalse(item.primaryMuscles.isEmpty, entry.name)
            XCTAssertFalse(item.requiredEquipment.isEmpty, entry.name)
            XCTAssertTrue(item.primaryMuscles.isDisjoint(with: item.secondaryMuscles), entry.name)
        }
        XCTAssertNil(SmartExerciseMetadata.forBuiltInID(UUID()))
        XCTAssertNil(SmartExerciseMetadata.forBuiltInID(SeedCatalog.stableID(namespace: 1, code: 67)))
        XCTAssertNil(SmartExerciseMetadata.forBuiltInID(SeedCatalog.stableID(namespace: 2, code: 1)))
        XCTAssertEqual(try exercise(12).requiredEquipment, [.bodyweight, .pullUpBar])
        XCTAssertEqual(try exercise(19).requiredEquipment, [.bodyweight, .backExtension])
        XCTAssertEqual(try exercise(1).requiredEquipment, [.barbell, .bench, .rack])
        XCTAssertEqual(try exercise(11).requiredEquipment, [.latPulldown])
        XCTAssertEqual(try exercise(15).requiredEquipment, [.seatedCableRow])
        XCTAssertEqual(try exercise(21).requiredEquipment, [.barbell, .rack])
        XCTAssertEqual(try exercise(42).primaryMuscles, [.adductors])
        XCTAssertEqual(MuscleRegion.allCases.count, 12)
        XCTAssertNotEqual(try exercise(16).requiredEquipment, try exercise(65).requiredEquipment)
    }

    func testNoHistoryIsUnknownAndNeverInventsAStartingLoad() throws {
        let bench = try exercise(2)
        let values = SmartTrainingEngine.recoveries(exercises: [bench], history: [], now: now)
        XCTAssertEqual(values.count, MuscleRegion.allCases.count)
        XCTAssertTrue(values.allSatisfy { $0.readiness == nil && $0.lastTrained == nil && $0.recentSets == 0 })
        let suggested = SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(), history: [], now: now)
        XCTAssertNil(suggested.weightKg)
        XCTAssertEqual(suggested.reps, 10)
        XCTAssertFalse(suggested.reason.isEmpty)
    }

    func testRecoverySeparatesPrimarySecondaryAndUntrainedMuscles() throws {
        let bench = try exercise(2)
        let logged = history(for: bench, count: 3, ageDays: 0)
        let recovered = SmartTrainingEngine.recoveries(exercises: [bench], history: logged, now: now.addingTimeInterval(10))
        let chest = try XCTUnwrap(recovered.first { $0.id == .chest })
        let triceps = try XCTUnwrap(recovered.first { $0.id == .triceps })
        let calves = try XCTUnwrap(recovered.first { $0.id == .calves })
        XCTAssertLessThan(try XCTUnwrap(chest.readiness), try XCTUnwrap(triceps.readiness))
        XCTAssertEqual(chest.recentSets, 3)
        XCTAssertEqual(triceps.recentSets, 3)
        XCTAssertNil(calves.readiness)
        XCTAssertNotNil(chest.lastTrained)
    }

    func testRecoveryDecaysAndIsBoundedWithoutUsingFutureWarmupOrIncompleteWork() throws {
        let bench = try exercise(2)
        let heavy = history(for: bench, count: 20, rpe: 10, ageDays: 0, kind: "failure")
        let recent = SmartTrainingEngine.recoveries(exercises: [bench], history: heavy, now: now.addingTimeInterval(30))
        XCTAssertEqual(try XCTUnwrap(recent.first { $0.id == .chest }?.readiness), 0)
        let later = SmartTrainingEngine.recoveries(exercises: [bench], history: heavy, now: now.addingTimeInterval(4 * 86_400))
        XCTAssertEqual(try XCTUnwrap(later.first { $0.id == .chest }?.readiness), 1)
        let invalid = history(for: bench, kind: "warmup") + history(for: bench, completed: false) +
            history(for: bench, ageDays: -1) + history(for: bench, weight: .nan)
        let ignored = SmartTrainingEngine.recoveries(exercises: [bench], history: invalid, now: now)
        XCTAssertTrue(ignored.allSatisfy { $0.readiness == nil })
    }

    func testWeightProgressionNeedsRepeatedTopRangeAndKnownComfortableEffort() throws {
        let bench = try exercise(2)
        let preferences = TrainingPreferences(level: .intermediate)
        let good = SmartTrainingEngine.prescription(for: bench, preferences: preferences,
                                                   history: history(for: bench), now: now)
        XCTAssertEqual(good.weightKg, 102.5)
        XCTAssertEqual(good.reps, 8)
        let single = SmartTrainingEngine.prescription(for: bench, preferences: preferences,
                                                     history: history(for: bench, count: 1), now: now)
        XCTAssertEqual(single.weightKg, 100)
        let unknownEffort = SmartTrainingEngine.prescription(for: bench, preferences: preferences,
                                                            history: history(for: bench, rpe: nil), now: now)
        XCTAssertEqual(unknownEffort.weightKg, 100)
        let shortRange = SmartTrainingEngine.prescription(for: bench, preferences: preferences,
                                                         history: history(for: bench, reps: 10), now: now)
        XCTAssertEqual(shortRange.weightKg, 100)
        XCTAssertEqual(shortRange.reps, 11)
    }

    func testWeightStepNeverExceedsFivePercentAndMixedLoadsDoNotTriggerIncrease() throws {
        let bench = try exercise(2)
        let tooLarge = SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(incrementKg: 2.5),
                                                       history: history(for: bench, weight: 20), now: now)
        XCTAssertEqual(tooLarge.weightKg, 20)
        var mixed = history(for: bench, count: 2, weight: 100)
        mixed += history(for: bench, count: 1, weight: 90)
        let mixedResult = SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(), history: mixed, now: now)
        XCTAssertEqual(mixedResult.weightKg, 90)
        let offGrid = SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(incrementKg: 2.5),
                                                      history: history(for: bench, weight: 99), now: now)
        let suggested = try XCTUnwrap(offGrid.weightKg)
        XCTAssertGreaterThan(suggested, 99)
        XCTAssertLessThanOrEqual(suggested, 99 * 1.05)
        XCTAssertEqual(suggested.truncatingRemainder(dividingBy: 2.5), 0, accuracy: 0.0001)
        let maximum = SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(),
                                                       history: history(for: bench, weight: 2_000), now: now)
        XCTAssertEqual(maximum.weightKg, 2_000)
    }

    func testHighEffortFailureAndBreakSuppressProgression() throws {
        let bench = try exercise(2)
        let high = SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(),
                                                   history: history(for: bench, rpe: 9.5), now: now)
        XCTAssertEqual(high.weightKg, 100)
        XCTAssertLessThan(high.reps, 12)
        let failure = history(for: bench) + history(for: bench, count: 1, weight: 100, kind: "failure")
        XCTAssertEqual(SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(),
                                                       history: failure, now: now).weightKg, 100)
        let shortBreak = SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(),
                                                         history: history(for: bench, ageDays: 10), now: now)
        XCTAssertEqual(shortBreak.weightKg, 100)
        let longBreak = SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(),
                                                        history: history(for: bench, weight: 99, ageDays: 30), now: now)
        XCTAssertEqual(longBreak.weightKg, 87.5)
        XCTAssertEqual(longBreak.reps, 8)
    }

    func testOnlyMatchingCompletedWorkingSetsCanProvideLoadingHistory() throws {
        let bench = try exercise(2), other = try exercise(4)
        let excluded = history(for: other) + history(for: bench, kind: "warmup") +
            history(for: bench, kind: "drop") + history(for: bench, kind: "failure") +
            history(for: bench, completed: false) + history(for: bench, weight: 0) +
            history(for: bench, weight: .infinity) + history(for: bench, ageDays: -1)
        let suggested = SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(), history: excluded, now: now)
        XCTAssertNil(suggested.weightKg)
        let renamed = TrainingExercise(id: bench.id, name: "اسمي المعدل", primaryMuscles: bench.primaryMuscles,
                                       secondaryMuscles: bench.secondaryMuscles, requiredEquipment: bench.requiredEquipment,
                                       movementPattern: bench.movementPattern)
        XCTAssertEqual(SmartTrainingEngine.prescription(for: renamed, preferences: TrainingPreferences(),
                                                       history: history(for: bench), now: now).weightKg, 102.5)
    }

    func testRecentFailureOnlyOrUnloadedSessionCannotReuseOlderSuccessToIncrease() throws {
        let bench = try exercise(2)
        let older = history(for: bench, ageDays: 2)
        let recentSession = SeedCatalog.stableID(namespace: 9, code: 2)
        let failed = TrainingSetHistory(sessionID: recentSession, exerciseID: bench.id,
                                       date: now.addingTimeInterval(-86_400), weightKg: 100,
                                       reps: 4, rpe: 10, kind: "failure")
        let result = SmartTrainingEngine.prescription(for: bench, preferences: TrainingPreferences(), history: older + [failed], now: now)
        XCTAssertNil(result.weightKg)
        let pushup = try exercise(8)
        let unloaded = TrainingSetHistory(sessionID: recentSession, exerciseID: pushup.id,
                                         date: now.addingTimeInterval(-86_400), weightKg: 0,
                                         reps: 12, rpe: 7)
        let bodyweight = SmartTrainingEngine.prescription(for: pushup, preferences: TrainingPreferences(),
                                                         history: history(for: pushup, weight: 20, ageDays: 2) + [unloaded], now: now)
        XCTAssertNil(bodyweight.weightKg)
    }

    func testBodyweightHoldAndCardioDoNotReceiveInventedWeights() throws {
        let pushup = try exercise(8)
        XCTAssertNil(SmartTrainingEngine.prescription(for: pushup, preferences: TrainingPreferences(),
                                                    history: history(for: pushup, weight: 0), now: now).weightKg)
        for code in [55, 56, 63, 64, 65, 66] {
            let item = try exercise(code)
            let suggestion = SmartTrainingEngine.prescription(for: item, preferences: TrainingPreferences(),
                                                             history: history(for: item), now: now)
            XCTAssertNil(suggestion.weightKg)
            XCTAssertEqual(suggestion.reps, 0)
        }
    }

    func testGenerationRespectsExactEquipmentDifficultyBudgetAndRepMode() throws {
        let catalog = try SeedCatalog.entries.map { try exercise($0.code) }
        let choices = TrainingPreferences(equipment: [.bodyweight, .dumbbell], durationMinutes: 30)
        let result = SmartTrainingEngine.generate(exercises: catalog, preferences: choices, history: [], now: now)
        XCTAssertFalse(result.exercises.isEmpty)
        XCTAssertLessThanOrEqual(result.estimatedMinutes, 30)
        XCTAssertEqual(Set(result.exercises.map(\.exerciseID)).count, result.exercises.count)
        for prescription in result.exercises {
            let original = try XCTUnwrap(catalog.first { $0.id == prescription.exerciseID })
            XCTAssertTrue(original.requiredEquipment.isSubset(of: choices.equipment))
            XCTAssertEqual(original.difficulty, .beginner)
            XCTAssertEqual(prescription.mode, .reps)
            XCTAssertNil(prescription.weightKg)
        }
        XCTAssertFalse(result.exercises.contains { $0.exerciseID == SeedCatalog.stableID(namespace: 1, code: 2) })
        let machineOnly = SmartTrainingEngine.generate(exercises: [try exercise(7), try exercise(10), try exercise(16)],
                                                      preferences: TrainingPreferences(equipment: [.chestPress]), history: [], now: now)
        XCTAssertEqual(machineOnly.exercises.map(\.exerciseID), [SeedCatalog.stableID(namespace: 1, code: 7)])
        let genericCable = SmartTrainingEngine.generate(exercises: [try exercise(11), try exercise(15)],
                                                       preferences: TrainingPreferences(equipment: [.cable]), history: [], now: now)
        XCTAssertTrue(genericCable.exercises.isEmpty)
    }

    func testGenerationIsDeterministicBalancedAndSensitiveToRecentHeavyTraining() throws {
        let catalog = try SeedCatalog.entries.map { try exercise($0.code) }
        let choices = TrainingPreferences(level: .intermediate, equipment: Set(TrainingEquipment.allCases), durationMinutes: 60)
        let first = SmartTrainingEngine.generate(exercises: catalog, preferences: choices, history: [], now: now)
        let reverse = SmartTrainingEngine.generate(exercises: Array(catalog.reversed()), preferences: choices, history: [], now: now)
        XCTAssertEqual(first, reverse)
        let selected = catalog.filter { first.exercises.map(\.exerciseID).contains($0.id) }
        let patterns = Set(selected.map(\.movementPattern))
        XCTAssertTrue(patterns.contains(.squat))
        XCTAssertTrue(patterns.contains(.hinge))
        XCTAssertTrue(patterns.contains(.horizontalPush))
        XCTAssertFalse(patterns.isDisjoint(with: [.horizontalPull, .verticalPull]))
        let pushup = try exercise(8)
        let tired = SmartTrainingEngine.generate(exercises: [pushup], preferences: TrainingPreferences(),
                                                history: history(for: pushup, count: 15, weight: 0, ageDays: 0),
                                                now: now.addingTimeInterval(30))
        XCTAssertTrue(tired.exercises.isEmpty)
        XCTAssertFalse(tired.warnings.isEmpty)
    }

    func testImpossibleTimeAndUnavailableEquipmentYieldExplainedEmptyPreview() throws {
        let strength = TrainingPreferences(goal: .strength, durationMinutes: 10)
        let short = SmartTrainingEngine.generate(exercises: [try exercise(8)], preferences: strength, history: [], now: now)
        XCTAssertTrue(short.exercises.isEmpty)
        XCTAssertEqual(short.estimatedMinutes, 0)
        let unavailable = SmartTrainingEngine.generate(exercises: [try exercise(1)], preferences: TrainingPreferences(), history: [], now: now)
        XCTAssertTrue(unavailable.exercises.isEmpty)
        XCTAssertFalse(unavailable.warnings.isEmpty)
        let invalid = SmartTrainingEngine.generate(exercises: [try exercise(8)],
                                                  preferences: TrainingPreferences(durationMinutes: Int.max), history: [], now: now)
        XCTAssertTrue(invalid.exercises.isEmpty)
    }

    func testArchivedDefinitionStillContributesToGeneratorRecoveryButCannotBeSelected() throws {
        let archivedBench = try exercise(2), availablePress = try exercise(22)
        let preferences = TrainingPreferences(equipment: [.dumbbell, .bench])
        let logged = history(for: archivedBench, count: 20, ageDays: 0)
        let withoutArchivedDefinition = SmartTrainingEngine.generate(exercises: [availablePress],
            preferences: preferences, history: logged, now: now.addingTimeInterval(30))
        XCTAssertFalse(withoutArchivedDefinition.exercises.isEmpty)
        let result = SmartTrainingEngine.generate(exercises: [availablePress], preferences: preferences,
            history: logged, now: now.addingTimeInterval(30), recoveryExercises: [archivedBench, availablePress])
        XCTAssertTrue(result.exercises.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testPreferencesRoundTripPreservesGranularChoices() throws {
        let preferences = TrainingPreferences(goal: .fitness, level: .advanced,
                                              equipment: [.pullUpBar, .hipAbduction, .box, .bodyweight],
                                              durationMinutes: 35, incrementKg: 1.25)
        let decoded = try JSONDecoder().decode(TrainingPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded, preferences)
        XCTAssertTrue(TrainingEquipment.allCases.allSatisfy { !$0.arabicName.isEmpty })
        XCTAssertTrue(MuscleRegion.allCases.allSatisfy { !$0.arabicName.isEmpty })
    }
}
