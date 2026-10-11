import SwiftUI
import UIKit
import XCTest
@testable import Fitness

final class PresentationTests: XCTestCase {
    @MainActor func testDashboardOnlyCountsCompletedSessionsAndWorkingSetsInLocalWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 10800) ?? .current
        calendar.firstWeekday = 7
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12)) ?? Date()
        let completed = WorkoutSession(start: today.addingTimeInterval(-86400), statusRaw: "completed")
        let excluded = WorkoutSession(start: today, statusRaw: "excluded")
        let active = WorkoutSession(start: today, statusRaw: "active")
        let old = WorkoutSession(start: today.addingTimeInterval(-21 * 86400), statusRaw: "completed")
        let movement = SessionExercise(sessionID: completed.id)
        let ignored = SessionExercise(sessionID: excluded.id)
        let oldMovement = SessionExercise(sessionID: old.id)
        let sets = [LoggedSet(sessionExerciseID: movement.id, weightKg: 40, reps: 10, isCompleted: true),
                    LoggedSet(sessionExerciseID: movement.id, weightKg: 20, reps: 10, kindRaw: "warmup", isCompleted: true),
                    LoggedSet(sessionExerciseID: movement.id, weightKg: 100, reps: 10, isCompleted: false),
                    LoggedSet(sessionExerciseID: ignored.id, weightKg: 100, reps: 10, isCompleted: true),
                    LoggedSet(sessionExerciseID: oldMovement.id, weightKg: 200, reps: 10, isCompleted: true)]
        let summary = DashboardSnapshot(sessions: [completed, excluded, active, old], movements: [movement, ignored, oldMovement], sets: sets, now: today, calendar: calendar)
        XCTAssertEqual(summary.weeklySessions, 1)
        XCTAssertEqual(summary.weeklyVolume, 400)
        XCTAssertEqual(summary.streak, 1)
        XCTAssertEqual(Set(summary.completed.map(\.id)), Set([completed.id, old.id]))
        XCTAssertFalse(active.statusRaw == "completed", "Presentation must not mutate session state")
    }
    func testCalendarDoesNotMarkRestUnscheduledOrTodayAsMissed() {
        let calendar = Calendar(identifier: .gregorian), today = Date(timeIntervalSince1970: 1_800_000_000)
        let past = today.addingTimeInterval(-86400)
        XCTAssertEqual(WorkoutCalendarStatus.resolve(completed: false, scheduledWorkout: true, rest: false, date: past, today: today, calendar: calendar), .missed)
        XCTAssertEqual(WorkoutCalendarStatus.resolve(completed: true, scheduledWorkout: true, rest: false, date: past, today: today, calendar: calendar), .completed)
        XCTAssertEqual(WorkoutCalendarStatus.resolve(completed: false, scheduledWorkout: true, rest: true, date: past, today: today, calendar: calendar), .rest)
        XCTAssertEqual(WorkoutCalendarStatus.resolve(completed: false, scheduledWorkout: false, rest: false, date: past, today: today, calendar: calendar), .unscheduled)
        XCTAssertEqual(WorkoutCalendarStatus.resolve(completed: false, scheduledWorkout: true, rest: false, date: today, today: today, calendar: calendar), .planned)
    }
    func testQuickActionsRecognizeOnlySupportedRoutes() {
        XCTAssertEqual(WorkoutQuickAction(shortcutType: "com.personal.Wateera.today"), .today)
        XCTAssertEqual(WorkoutQuickAction(shortcutType: "com.personal.Wateera.free"), .free)
        XCTAssertEqual(WorkoutQuickAction(shortcutType: "com.personal.Wateera.progress"), .progress)
        XCTAssertNil(WorkoutQuickAction(shortcutType: "com.personal.Wateera.widget"))
    }
    @MainActor func testAchievementRendersAnOpaqueShareableImageWithoutNetworkOrPhotoAccess() throws {
        let renderer = ImageRenderer(content: AchievementCard(title: "تمرين اختبار", date: "١٤ أكتوبر", duration: "٣٠:٠٠", volume: "٤٠٠ كجم", sets: "١٠", records: "١").environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, 600); XCTAssertEqual(image.size.height, 800)
        XCTAssertNotNil(image.pngData())
        XCTAssertEqual(image.cgImage?.width, 1200); XCTAssertEqual(image.cgImage?.height, 1600)
    }
    @MainActor func testDefaultAccentHasAccessibleContrastInBothAppearances() {
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            func linear(_ x: CGFloat) -> Double { let x = Double(x); return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return linear(r) * 0.2126 + linear(g) * 0.7152 + linear(b) * 0.0722
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let a = luminance(UIColor(WateeraDesign.brand).resolvedColor(with: traits))
            let b = luminance(UIColor(WateeraDesign.surface).resolvedColor(with: traits))
            XCTAssertGreaterThanOrEqual((max(a,b) + 0.05) / (min(a,b) + 0.05), 4.5)
        }
    }
}
