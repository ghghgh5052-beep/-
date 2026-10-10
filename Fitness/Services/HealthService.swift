import Foundation
import HealthKit
import Observation

struct HealthWeightSample: Identifiable {
    var id: UUID
    var date: Date
    var weightKg: Double
    var kilograms: Double { weightKg }
}

@Observable
@MainActor
final class HealthService {
    static let shared = HealthService()

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "healthEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "healthEnabled") }
    }
    private(set) var isRequestingAuthorization = false
    private(set) var authorizationRequested = false
    var errorMessage: String?
    @ObservationIgnored private let store = HKHealthStore()

    var isAvailable: Bool { SigningCapabilities.current.hasHealthKit && HKHealthStore.isHealthDataAvailable() }

    private init() {}

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard SigningCapabilities.current.hasHealthKit else {
            errorMessage = "التوقيع الحالي لا يتضمن صلاحية تطبيق الصحة. يمكنك متابعة تسجيل بياناتك يدويًا."
            return false
        }
        guard isAvailable else {
            errorMessage = "بيانات صحتي غير متاحة على هذا الجهاز."
            return false
        }
        guard let weight = HKObjectType.quantityType(forIdentifier: .bodyMass),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else { return false }
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [weight, steps, HKObjectType.workoutType()])
            // HealthKit deliberately does not reveal whether read permission was granted.
            authorizationRequested = true
            isEnabled = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = "تعذر الاتصال بتطبيق صحتي. راجع الأذونات من إعدادات الجهاز."
            return false
        }
    }

    func readRecentBodyWeights(days: Int = 90) async throws -> [HealthWeightSample] {
        guard isAvailable, isEnabled, let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -max(1, days), to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
        return samples.map { HealthWeightSample(id: $0.uuid, date: $0.startDate, weightKg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    func readBodyWeights() async throws -> [HealthWeightSample] { try await readRecentBodyWeights() }

    func readStepsToday() async throws -> Double { try await stepsToday() }

    func stepsToday() async throws -> Double {
        guard isAvailable, isEnabled, let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            }
            store.execute(query)
        }
    }

    func writeCompletedWorkout(_ session: WorkoutSession) async throws -> Bool {
        guard isAvailable, isEnabled, session.statusRaw == "completed", let end = session.end else { return false }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            errorMessage = "اسمح لوتيرة بإضافة التمارين إلى صحتي من إعدادات الأذونات."
            return false
        }
        let identifier = "\(Bundle.main.bundleIdentifier ?? "Wateera").workout.\(session.id.uuidString)"
        if try await containsWorkout(syncIdentifier: identifier) { return true }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await perform { builder.beginCollection(withStart: session.start, completion: $0) }
            try await perform { builder.addMetadata([HKMetadataKeySyncIdentifier: identifier, HKMetadataKeySyncVersion: 1,
                                                     HKMetadataKeyWorkoutBrandName: "وتيرة"], completion: $0) }
            let pauseDates = session.pauseEventsRaw.data(using: .utf8).flatMap {
                try? JSONDecoder().decode([TimeInterval].self, from: $0)
            } ?? []
            let events = pauseDates.enumerated().compactMap { index, timestamp -> HKWorkoutEvent? in
                guard timestamp.isFinite else { return nil }
                let date = Date(timeIntervalSince1970: timestamp)
                guard date >= session.start, date <= end else { return nil }
                return HKWorkoutEvent(type: index.isMultiple(of: 2) ? .pause : .resume,
                                      dateInterval: DateInterval(start: date, duration: 0), metadata: nil)
            }
            if !events.isEmpty { try await perform { builder.addWorkoutEvents(events, completion: $0) } }
            try await perform { builder.endCollection(withEnd: max(end, session.start), completion: $0) }
            let workout: HKWorkout? = try await withCheckedThrowingContinuation { continuation in
                builder.finishWorkout { workout, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: workout)
                }
            }
            return workout != nil
        } catch {
            builder.discardWorkout()
            errorMessage = "تم حفظ تمرينك محليًا، وتعذرت إضافته إلى صحتي. يمكنك إعادة المحاولة."
            throw error
        }
    }

    private func containsWorkout(syncIdentifier: String) async throws -> Bool {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples?.isEmpty == false)
            }
            store.execute(query)
        }
    }

    private func perform(_ operation: (@escaping (Bool, Error?) -> Void) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation { succeeded, error in
                if let error { continuation.resume(throwing: error) }
                else if succeeded { continuation.resume() }
                else { continuation.resume(throwing: HealthError.operationFailed) }
            }
        }
    }
}

enum HealthError: LocalizedError {
    case operationFailed
    var errorDescription: String? { "تعذر إكمال العملية في تطبيق صحتي." }
}
