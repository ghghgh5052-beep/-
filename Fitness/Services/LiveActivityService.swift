import ActivityKit
import Foundation
import UIKit

@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()
    private var activity: Activity<WorkoutActivityAttributes>?
    private var updateTask: Task<Void, Never>?
    private(set) var errorMessage: String?

    private init() {}

    func update(sessionID: UUID, title: String, startedAt: Date, elapsedSeconds: Int, completedSets: Int,
                restDeadline: Date?, paused: Bool, arabicDigits: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = WorkoutActivityAttributes.ContentState(workoutTitle: title, startedAt: startedAt,
                                                          timerReferenceDate: .now.addingTimeInterval(-Double(elapsedSeconds)),
                                                          elapsedSeconds: elapsedSeconds, completedSets: completedSets,
                                                          restDeadline: restDeadline, isPaused: paused,
                                                          useArabicDigits: arabicDigits)
        let content = ActivityContent(state: state, staleDate: restDeadline)
        let matching = Activity<WorkoutActivityAttributes>.activities.first { $0.attributes.sessionID == sessionID.uuidString }
        activity = matching
        if let activity {
            let previous = updateTask
            previous?.cancel()
            updateTask = Task {
                await previous?.value
                guard !Task.isCancelled else { return }
                await activity.update(content)
            }
        } else if UIApplication.shared.applicationState == .active {
            do {
                activity = try Activity.request(attributes: WorkoutActivityAttributes(sessionID: sessionID.uuidString),
                                                content: content, pushType: nil)
                errorMessage = nil
            } catch {
                errorMessage = "تعذر بدء النشاط المباشر. يمكنك متابعة التمرين والمؤقت داخل التطبيق."
            }
        }
    }

    func endAll() async {
        let pending = updateTask
        pending?.cancel()
        await pending?.value
        updateTask = nil
        for item in Activity<WorkoutActivityAttributes>.activities {
            await item.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }
}
