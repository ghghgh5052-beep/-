import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FitnessWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWorkoutWidget()
        StreakWidget()
        NextWorkoutWidget()
        ActiveWorkoutWidget()
    }
}

struct WorkoutWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WorkoutWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutWidgetEntry {
        WorkoutWidgetEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutWidgetEntry) -> Void) {
        completion(WorkoutWidgetEntry(date: .now, snapshot: SharedWorkoutStorage.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutWidgetEntry>) -> Void) {
        let now = Date.now
        var snapshot = SharedWorkoutStorage.readSnapshot()
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = snapshot.weekStart
        if let today = snapshot.schedule.first(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
            snapshot.todayTitle = today.isRest ? "يوم راحة" : (today.isCompleted ? "اكتمل: " + today.title : today.title)
        } else if !calendar.isDate(snapshot.generatedAt, inSameDayAs: now) {
            snapshot.todayTitle = "لا يوجد تمرين مجدول"
        }
        if let next = snapshot.schedule.first(where: { !$0.isRest && !$0.isCompleted && $0.date >= calendar.startOfDay(for: now) }) {
            snapshot.nextTitle = next.title
            snapshot.nextDate = next.date
        } else if !calendar.isDate(snapshot.generatedAt, inSameDayAs: now) {
            snapshot.nextDate = nil
            snapshot.nextTitle = "لا يوجد تمرين قادم في الخطة"
        }
        let completedDays = Set(snapshot.completedWorkoutDates.map { calendar.startOfDay(for: $0) })
        let currentDay = calendar.startOfDay(for: now)
        var cursor = completedDays.contains(currentDay) ? currentDay :
            (calendar.date(byAdding: .day, value: -1, to: currentDay) ?? currentDay)
        var streak = 0
        while completedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        snapshot.streak = streak
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        snapshot.completedThisWeek = snapshot.completedWorkoutDates.filter { week?.contains($0) == true }.count
        let refresh = calendar.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [WorkoutWidgetEntry(date: now, snapshot: snapshot)], policy: .after(refresh)))
    }
}

enum WorkoutWidgetKind: Equatable { case today, streak, next }

struct WorkoutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WorkoutWidgetEntry
    var kind: WorkoutWidgetKind

    var body: some View {
        Group {
            if family == .accessoryCircular {
                VStack(spacing: 2) {
                    Image(systemName: kind == .streak ? "flame.fill" : "dumbbell.fill")
                    Text(kind == .streak ? WidgetArabic.digits(entry.snapshot.streak, arabic: entry.snapshot.useArabicDigits) : "وتيرة")
                        .font(.caption2)
                }
                .widgetAccentable()
            } else if family == .accessoryInline {
                Label(title, systemImage: symbol)
            } else {
                VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 3 : 10) {
                    Label(heading, systemImage: symbol)
                        .font(family == .accessoryRectangular ? .caption : .subheadline.weight(.semibold))
                        .foregroundStyle(family == .accessoryRectangular ? Color.primary : Color.green)
                    Text(title).font(.headline).lineLimit(3).minimumScaleFactor(0.75)
                    if kind == .next, let date = entry.snapshot.nextDate {
                        Text(date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if family == .systemMedium || family == .systemSmall {
                        Spacer(minLength: 0)
                        Text("هذا الأسبوع: \(WidgetArabic.digits(entry.snapshot.completedThisWeek, arabic: entry.snapshot.useArabicDigits)) تمارين")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, WidgetArabic.locale(arabic: entry.snapshot.useArabicDigits))
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: kind == .streak ? "wateera://progress" : "wateera://today"))
        .privacySensitive()
    }

    private var heading: String {
        switch kind {
        case .today: return entry.snapshot.activeWorkoutTitle == nil ? "تمرين اليوم" : "تمرينك الجاري"
        case .streak: return "سلسلة الالتزام"
        case .next: return "التمرين القادم"
        }
    }

    private var title: String {
        switch kind {
        case .today: return entry.snapshot.activeWorkoutTitle ?? entry.snapshot.todayTitle
        case .streak: return "\(WidgetArabic.digits(entry.snapshot.streak, arabic: entry.snapshot.useArabicDigits)) أيام متتالية"
        case .next: return entry.snapshot.nextTitle
        }
    }

    private var symbol: String { kind == .streak ? "flame.fill" : "dumbbell.fill" }
}

struct TodayWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "todayWorkout", provider: WorkoutWidgetProvider()) { entry in
            WorkoutWidgetView(entry: entry, kind: .today)
        }
        .configurationDisplayName("تمرين اليوم")
        .description("اطّلع على تمرين اليوم أو تمرينك الجاري.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "workoutStreak", provider: WorkoutWidgetProvider()) { entry in
            WorkoutWidgetView(entry: entry, kind: .streak)
        }
        .configurationDisplayName("سلسلة الالتزام")
        .description("تابع أيام تمرينك المتتالية وإنجاز هذا الأسبوع.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nextWorkout", provider: WorkoutWidgetProvider()) { entry in
            WorkoutWidgetView(entry: entry, kind: .next)
        }
        .configurationDisplayName("التمرين القادم")
        .description("اعرف موعد الجلسة القادمة من خطتك الحالية.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct ActiveWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLiveActivityView(state: context.state)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.green)
                .widgetURL(URL(string: "wateera://active"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("وتيرة", systemImage: "dumbbell.fill").font(.headline).foregroundStyle(.green)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(WidgetArabic.digits(context.state.completedSets, arabic: context.state.useArabicDigits)) مجموعات")
                        .font(.caption)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutLiveActivityView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "dumbbell.fill").foregroundStyle(.green)
            } compactTrailing: {
                if let deadline = context.state.restDeadline, deadline > .now {
                    Text(timerInterval: min(Date.now, deadline)...deadline, countsDown: true).monospacedDigit().frame(width: 48)
                        .environment(\.locale, WidgetArabic.locale(arabic: context.state.useArabicDigits))
                } else {
                    Text(WidgetArabic.digits(context.state.completedSets, arabic: context.state.useArabicDigits))
                }
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "dumbbell.fill")
            }
            .widgetURL(URL(string: "wateera://active"))
            .keylineTint(.green)
        }
    }
}

struct WorkoutLiveActivityView: View {
    var state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.workoutTitle).font(.headline).lineLimit(2)
                Text(state.isPaused ? "التمرين متوقف مؤقتًا" : "\(WidgetArabic.digits(state.completedSets, arabic: state.useArabicDigits)) مجموعات مكتملة")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(spacing: 3) {
                if let deadline = state.restDeadline, deadline > .now {
                    Text("الراحة").font(.caption)
                    Text(timerInterval: min(Date.now, deadline)...deadline, countsDown: true).font(.title2.weight(.semibold)).monospacedDigit()
                } else if state.isPaused {
                    Image(systemName: "pause.circle.fill").font(.title2)
                } else {
                    Text("وقت التمرين").font(.caption)
                    // Offset by accumulated pauses so the system continues without background execution.
                    Text(state.timerReferenceDate, style: .timer)
                        .font(.title3.weight(.semibold)).monospacedDigit()
                }
            }
            .foregroundStyle(.green)
        }
        .padding(12)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, WidgetArabic.locale(arabic: state.useArabicDigits))
        .privacySensitive()
    }
}
