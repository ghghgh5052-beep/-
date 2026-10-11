import Foundation
import SwiftData

// The local build keeps coordinator APIs stable while shipping no integration frameworks,
// shared containers, extension targets, or background network services.
@MainActor final class LiveActivityService {
    static let shared = LiveActivityService()
    let errorMessage: String? = nil
    func update(sessionID: UUID, title: String, startedAt: Date, elapsedSeconds: Int, completedSets: Int,
                restDeadline: Date?, paused: Bool, arabicDigits: Bool) {}
    func endAll() async {}
}

@MainActor final class HealthService {
    static let shared = HealthService()
    var isEnabled = false
    let errorMessage: String? = nil
    func writeCompletedWorkout(_ session: WorkoutSession) async throws -> Bool { false }
}

@MainActor enum WidgetSnapshotService {
    @discardableResult static func refresh(context: ModelContext, settings: AppSettings) -> String? { nil }
    static func programWeek(plan: WorkoutPlan, date: Date, calendar: Calendar) -> Int {
        let origin = calendar.dateInterval(of: .weekOfYear, for: plan.programStart)?.start ?? calendar.startOfDay(for: plan.programStart)
        let target = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: origin, to: target).day ?? 0
        return max(0, days / 7) % max(1, plan.cycleWeeks) + 1
    }
}

enum SharedWorkoutStorage {
    static func requestStartToday() { UserDefaults.standard.set(true, forKey: "pendingStartToday") }
    static func consumeStartToday() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: "pendingStartToday")
        UserDefaults.standard.removeObject(forKey: "pendingStartToday")
        return pending
    }
}

extension Notification.Name {
    static let startTodayWorkoutRequested = Notification.Name("pendingStartToday")
    static let workoutShortcutRequested = Notification.Name("workoutShortcutRequested")
}
