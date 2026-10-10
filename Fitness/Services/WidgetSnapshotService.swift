import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSnapshotService {
    @discardableResult
    static func refresh(context: ModelContext, settings: AppSettings) -> String? {
        guard let group = SharedWorkoutStorage.groupIdentifier,
              SigningCapabilities.current.allowsAppGroup(group) else {
            return "التوقيع الحالي لا يتيح مشاركة بيانات الويدجت. بياناتك محفوظة داخل التطبيق."
        }
        do {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = min(7, max(1, settings.weekStart))
            let now = Date.now
            let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            let completed = sessions.filter { $0.statusRaw == "completed" && $0.start <= now }
            let plans = try context.fetch(FetchDescriptor<WorkoutPlan>()).filter { $0.isActive && !$0.isArchived }
                .sorted { $0.updatedAt > $1.updatedAt }
            let days = try context.fetch(FetchDescriptor<PlanDay>())
            var todayTitle = "لا يوجد تمرين مجدول"
            var nextTitle = "أضف خطة للبدء"
            var nextDate: Date?
            var schedule: [WidgetScheduledDay] = []
            if let plan = plans.first {
                let relevant = days.filter { $0.planID == plan.id }
                for offset in 0...max(14, min(364, max(1, min(52, plan.cycleWeeks)) * 7)) {
                    guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                    guard calendar.startOfDay(for: date) >= calendar.startOfDay(for: plan.programStart) else { continue }
                    let cycleWeek = programWeek(plan: plan, date: date, calendar: calendar)
                    let weekday = calendar.component(.weekday, from: date)
                    guard let day = relevant.filter({ $0.week == cycleWeek && $0.weekday == weekday })
                        .sorted(by: { $0.updatedAt > $1.updatedAt }).first else { continue }
                    let isCompleted = completed.contains { $0.planDayID == day.id && calendar.isDate($0.start, inSameDayAs: date) }
                    schedule.append(WidgetScheduledDay(date: calendar.startOfDay(for: date), title: day.title,
                                                       isRest: day.isRest, isCompleted: isCompleted))
                    if offset == 0 { todayTitle = day.isRest ? "يوم راحة" : (isCompleted ? "اكتمل: " + day.title : day.title) }
                    if !day.isRest && !isCompleted && nextDate == nil {
                        nextTitle = day.title
                        nextDate = calendar.startOfDay(for: date)
                    }
                }
                if nextDate == nil { nextTitle = "لا يوجد تمرين قادم في الخطة" }
            }
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
            let weekCount = completed.filter { thisWeek?.contains($0.start) == true }.count
            let snapshot = WidgetSnapshot(generatedAt: now, todayTitle: todayTitle, nextTitle: nextTitle,
                                          nextDate: nextDate,
                                          streak: ProgressMath.streak(dates: completed.map(\.start), calendar: calendar),
                                          completedThisWeek: weekCount, useArabicDigits: settings.useArabicDigits,
                                          activeWorkoutTitle: sessions.filter { $0.statusRaw == "active" || $0.statusRaw == "paused" }
                                            .sorted { $0.start > $1.start }.first?.title,
                                          schedule: schedule, completedWorkoutDates: completed.map(\.start),
                                          weekStart: settings.weekStart)
            try SharedWorkoutStorage.writeSnapshot(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            return nil
        } catch {
            return "تعذر تحديث الويدجت. تحقق من توقيع مجموعة التطبيقات."
        }
    }

    static func programWeek(plan: WorkoutPlan, date: Date, calendar: Calendar) -> Int {
        let origin = calendar.dateInterval(of: .weekOfYear, for: plan.programStart)?.start ?? calendar.startOfDay(for: plan.programStart)
        let target = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: origin, to: target).day ?? 0
        let weeks = max(0, days / 7)
        return weeks % max(1, plan.cycleWeeks) + 1
    }
}
