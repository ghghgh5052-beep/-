import SwiftUI
import SwiftData

/// Presentation-only aggregates. The persisted models and PR engine remain unchanged.
struct DashboardSnapshot {
    let completed: [WorkoutSession]
    let weeklySessions: Int
    let weeklyVolume: Double
    let streak: Int
    @MainActor init(sessions: [WorkoutSession], movements: [SessionExercise], sets: [LoggedSet], now: Date, calendar: Calendar) {
        completed = sessions.filter { $0.statusRaw == "completed" && $0.start <= now }
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
        let sessionIDs = Set(completed.filter { interval?.contains($0.start) == true }.map(\.id))
        let movementIDs = Set(movements.filter { sessionIDs.contains($0.sessionID) }.map(\.id))
        weeklySessions = sessionIDs.count
        weeklyVolume = WorkoutMath.volume(sets: sets.filter { $0.isCompleted && $0.kindRaw != "warmup" && movementIDs.contains($0.sessionExerciseID) })
        streak = ProgressMath.streak(dates: completed.map(\.start), today: now, calendar: calendar)
    }
}

@MainActor struct DashboardOverview: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var sessions: [WorkoutSession]
    @Query private var movements: [SessionExercise]
    @Query private var sets: [LoggedSet]
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]
    @Query private var exercises: [Exercise]
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.firstWeekday = settings.weekStart; return value }
    private var snapshot: DashboardSnapshot { DashboardSnapshot(sessions: sessions, movements: movements, sets: sets, now: .now, calendar: calendar) }
    var body: some View {
        let summary = snapshot
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "أسبوعك، خطوة بخطوة", subtitle: "إنجازات صغيرة تتراكم")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                StatCard(title: "جلسات هذا الأسبوع", value: ArabicFormat.integer(summary.weeklySessions, arabic: settings.useArabicDigits), symbol: "checkmark.circle.fill")
                StatCard(title: "أيام متواصلة", value: ArabicFormat.integer(summary.streak, arabic: settings.useArabicDigits), symbol: "flame.fill")
            }
            HStack {
                Label("حجم الأسبوع", systemImage: "chart.bar.fill").font(.subheadline)
                Spacer()
                Text(ArabicFormat.weight(summary.weeklyVolume, settings: settings)).font(.headline).monospacedDigit()
            }.wateeraCard(padding: 16).accessibilityElement(children: .combine)
            NavigationLink { WorkoutCalendarView() } label: {
                DestinationRow(title: "تقويم إنجازك", subtitle: "شاهد أيام التمرين والراحة خلال الشهر", symbol: "calendar.badge.checkmark")
            }.buttonStyle(.plain).accessibilityIdentifier("dashboard.calendar")
            if let record = records.first(where: { record in summary.completed.contains { $0.id == record.sessionID } }) {
                NavigationLink { PersonalRecordsView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trophy.fill").font(.title2).foregroundStyle(WateeraDesign.gold).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("آخر رقم شخصي").font(.caption).foregroundStyle(.secondary)
                            Text(exercises.first { $0.id == record.exerciseID }?.name ?? "تمرين محفوظ").font(.headline).foregroundStyle(.primary)
                            Text(record.kindRaw == "reps" ? "أعلى تكرارات" : record.kindRaw == "weight" ? "أعلى وزن" : "أقصى تكرار تقديري").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(record.kindRaw == "reps" ? ArabicFormat.integer(Int(record.value), arabic: settings.useArabicDigits) : ArabicFormat.weight(record.value, settings: settings)).font(.headline).foregroundStyle(WateeraDesign.gold)
                    }.wateeraCard()
                }.buttonStyle(.plain).accessibilityIdentifier("dashboard.record")
            } else {
                NavigationLink { PersonalRecordsView() } label: { DestinationRow(title: "أرقامك الشخصية", subtitle: "تُسجَّل تلقائيًا بعد إكمال جلساتك", symbol: "trophy") }.buttonStyle(.plain)
            }
        }
    }
}

enum WorkoutCalendarStatus: String { case completed, missed, planned, rest, unscheduled
    var title: String {
        switch self { case .completed: return "تمرين منجز"; case .missed: return "موعد لم تُسجّل فيه جلسة"; case .planned: return "تمرين مجدول"; case .rest: return "يوم راحة"; case .unscheduled: return "دون تمرين مجدول" }
    }
    static func resolve(completed: Bool, scheduledWorkout: Bool, rest: Bool, date: Date, today: Date, calendar: Calendar) -> Self {
        if completed { return .completed }
        if rest { return .rest }
        guard scheduledWorkout else { return .unscheduled }
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: today) ? .missed : .planned
    }
}

@MainActor struct WorkoutCalendarView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var sessions: [WorkoutSession]
    @Query private var plans: [WorkoutPlan]
    @Query private var days: [PlanDay]
    @State private var offset = 0
    @State private var selection = Date.now
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = settings.weekStart; return c }
    private var first: Date {
        let base = calendar.date(byAdding: .month, value: offset, to: Date()) ?? Date()
        return calendar.dateInterval(of: .month, for: base)?.start ?? base
    }
    private var monthTitle: String {
        let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: settings.useArabicDigits ? "ar_SA" : "ar_SA@numbers=latn"); f.dateFormat = "MMMM yyyy"
        return f.string(from: first)
    }
    private var monthDates: [Date] {
        (0..<(calendar.range(of: .day, in: .month, for: first)?.count ?? 0)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }
    private func status(_ date: Date) -> WorkoutCalendarStatus {
        let complete = sessions.contains { $0.statusRaw == "completed" && calendar.isDate($0.start, inSameDayAs: date) }
        let plan = plans.filter { $0.isActive && !$0.isArchived }.max { $0.updatedAt < $1.updatedAt }
        var scheduled: PlanDay?
        if let plan, calendar.startOfDay(for: date) >= calendar.startOfDay(for: plan.programStart) {
            let week = WidgetSnapshotService.programWeek(plan: plan, date: date, calendar: calendar)
            scheduled = days.first { $0.planID == plan.id && $0.week == week && $0.weekday == calendar.component(.weekday, from: date) }
        }
        return .resolve(completed: complete, scheduledWorkout: scheduled?.isRest == false, rest: scheduled?.isRest == true, date: date, today: .now, calendar: calendar)
    }
    private func tint(_ status: WorkoutCalendarStatus) -> Color {
        switch status { case .completed: return settings.color; case .missed: return WateeraDesign.coral; case .planned: return WateeraDesign.blue; default: return .secondary }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.backward").frame(width: 44, height: 44) }.accessibilityLabel("الشهر السابق")
                    Spacer(); Text(monthTitle).font(.title3.bold()).accessibilityAddTraits(.isHeader); Spacer()
                    Button { offset += 1 } label: { Image(systemName: "chevron.forward").frame(width: 44, height: 44) }.accessibilityLabel("الشهر التالي")
                }
                VStack(spacing: 12) {
                    // At accessibility sizes switch to a day list rather than shrinking 7 tap targets.
                    if typeSize.isAccessibilitySize {
                        ForEach(monthDates, id: \.self) { date in
                            Button { selection = date } label: {
                                HStack { Text(ArabicFormat.date(date)); Spacer(); Text(status(date).title).foregroundStyle(tint(status(date))) }.frame(minHeight: 44)
                            }.foregroundStyle(.primary)
                        }
                    } else {
                        let leading = (calendar.component(.weekday, from: first) - settings.weekStart + 7) % 7
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                            ForEach(0..<7, id: \.self) { index in Text(PlanWeekdays.shortName((settings.weekStart - 1 + index) % 7 + 1)).font(.caption2.bold()).foregroundStyle(.secondary) }
                            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 44).accessibilityHidden(true) }
                            ForEach(monthDates, id: \.self) { date in
                                Button { selection = date } label: {
                                    VStack(spacing: 3) {
                                        Text(ArabicFormat.integer(calendar.component(.day, from: date), arabic: settings.useArabicDigits)).font(.subheadline.weight(calendar.isDateInToday(date) ? .bold : .medium))
                                        Image(systemName: status(date) == .completed ? "checkmark" : status(date) == .missed ? "minus" : status(date) == .rest ? "moon.fill" : "circle.fill").font(.system(size: 7, weight: .bold))
                                    }.foregroundStyle(tint(status(date))).frame(maxWidth: .infinity, minHeight: 44)
                                        .background(calendar.isDate(date, inSameDayAs: selection) ? tint(status(date)).opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(calendar.isDate(date, inSameDayAs: selection) ? tint(status(date)) : .clear, lineWidth: 1) }
                                }.buttonStyle(.plain).accessibilityLabel(ArabicFormat.date(date) + "، " + status(date).title)
                            }
                        }
                    }
                }.padding(.vertical, 16).background(WateeraDesign.surface, in: RoundedRectangle(cornerRadius: 24))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) { legend }; VStack(alignment: .leading, spacing: 10) { legend }
                }
                SectionHeading(title: ArabicFormat.date(selection), subtitle: status(selection).title)
                let selected = sessions.filter { $0.statusRaw == "completed" && calendar.isDate($0.start, inSameDayAs: selection) }
                ForEach(selected) { session in
                    NavigationLink { SessionHistoryView(session: session) } label: { DestinationRow(title: session.title, subtitle: ArabicFormat.duration(session.activeDuration(), arabic: settings.useArabicDigits), symbol: "checkmark.circle") }.buttonStyle(.plain)
                }
                if selected.isEmpty { Text("لا توجد جلسة مكتملة مسجّلة في هذا اليوم.").foregroundStyle(.secondary).font(.subheadline) }
                Text("الأيام المجدولة والمفوّتة تُعرض وفق خطتك الحالية. تغيير الخطة قد يغيّر هذه العلامات، ولا يغيّر سجلات الجلسات.").font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }.wateeraCanvas().navigationTitle("تقويم الإنجاز").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("dashboard.calendar.screen")
    }
    @ViewBuilder private var legend: some View {
        Label("منجز", systemImage: "checkmark.circle.fill").foregroundStyle(settings.color)
        Label("مفوّت", systemImage: "minus.circle.fill").foregroundStyle(WateeraDesign.coral)
        Label("مجدول", systemImage: "circle.fill").foregroundStyle(WateeraDesign.blue)
    }
}
