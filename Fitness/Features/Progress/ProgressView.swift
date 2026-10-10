import SwiftUI
import SwiftData
import Charts

@MainActor struct ProgressDashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \SessionExercise.order) private var movements: [SessionExercise]
    @Query(filter: #Predicate<LoggedSet> { $0.isCompleted }) private var sets: [LoggedSet]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var selectedExercise: UUID?
    @State private var range = 90
    @State private var chartKind = 0
    @State private var formula = OneRepMaxFormula.epley

    private var finished: [WorkoutSession] { sessions.filter { $0.statusRaw == "completed" } }
    private var cutoff: Date { Calendar.current.date(byAdding: .day, value: -range, to: Date()) ?? Date() }
    private var samples: [LiftSample] {
        guard let selectedExercise else { return [] }
        let movementMap = Dictionary(movements.filter { $0.exerciseID == selectedExercise }.map { ($0.id, $0.sessionID) }, uniquingKeysWith: { first, _ in first })
        let sessionMap = Dictionary(finished.filter { $0.start >= cutoff }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: sets.filter { movementMap[$0.sessionExerciseID] != nil && $0.kindRaw != "warmup" }) { movementMap[$0.sessionExerciseID] ?? UUID() }
        return grouped.compactMap { sessionID, entries in
            guard let session = sessionMap[sessionID], !entries.isEmpty else { return nil }
            return LiftSample(id: sessionID, date: session.start,
                              oneRM: entries.map { estimate($0.weightKg, $0.reps) }.max() ?? 0,
                              top: entries.map(\.weightKg).max() ?? 0,
                              volume: entries.reduce(0) { $0 + $1.weightKg * Double($1.reps) })
        }.sorted { $0.date < $1.date }
    }
    private var weekly: [WeekSample] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = settings.weekStart
        let recent = finished.filter { $0.start >= cutoff }
        let sessionMap = Dictionary(recent.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let exerciseSession = Dictionary(movements.map { ($0.id, $0.sessionID) }, uniquingKeysWith: { first, _ in first })
        var volumes: [Date: Double] = [:]
        var counts: [Date: Int] = [:]
        for session in recent {
            let week = calendar.dateInterval(of: .weekOfYear, for: session.start)?.start ?? calendar.startOfDay(for: session.start)
            counts[week, default: 0] += 1
        }
        for entry in sets where entry.kindRaw != "warmup" {
            guard let id = exerciseSession[entry.sessionExerciseID], let session = sessionMap[id] else { continue }
            let week = calendar.dateInterval(of: .weekOfYear, for: session.start)?.start ?? calendar.startOfDay(for: session.start)
            volumes[week, default: 0] += entry.weightKg * Double(entry.reps)
        }
        let current = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<max(1, range / 7)).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .weekOfYear, value: -offset, to: current) else { return nil }
            return WeekSample(date: date, volume: volumes[date] ?? 0, workouts: counts[date] ?? 0)
        }
    }
    private var distribution: [MuscleSample] {
        let recentIDs = Set(finished.filter { $0.start >= cutoff }.map(\.id))
        let exerciseMap = Dictionary(exercises.map { ($0.id, $0.primaryMuscleRaw) }, uniquingKeysWith: { first, _ in first })
        let movementMap = Dictionary(movements.filter { recentIDs.contains($0.sessionID) }.map { ($0.id, exerciseMap[$0.exerciseID] ?? "other") }, uniquingKeysWith: { first, _ in first })
        var counts: [String: Int] = [:]
        for entry in sets where entry.kindRaw != "warmup" {
            if let muscle = movementMap[entry.sessionExerciseID] { counts[muscle, default: 0] += 1 }
        }
        return counts.map { MuscleSample(name: muscleName($0.key), sets: $0.value) }.sorted { $0.sets > $1.sets }
    }
    private var streak: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = settings.weekStart
        let weeks = Set(finished.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.start)?.start })
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        if !weeks.contains(cursor) { cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor }
        var count = 0
        while weeks.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        StatCard(title: "جلسات مكتملة", value: ArabicFormat.integer(finished.count, arabic: settings.useArabicDigits), symbol: "checkmark.seal").accessibilityIdentifier("progress.completed")
                        StatCard(title: "أسابيع متواصلة", value: ArabicFormat.integer(streak, arabic: settings.useArabicDigits), symbol: "flame")
                    }
                    Picker("الفترة", selection: $range) {
                        Text("شهر").tag(30); Text("ثلاثة أشهر").tag(90); Text("سنة").tag(365); Text("سنتان").tag(730)
                    }.pickerStyle(.segmented)
                    if finished.isEmpty {
                        EmptyState(title: "كل مجموعة تصنع فرقًا", message: "أكمل أول جلسة لتظهر أحجام تدريبك وأرقامك الشخصية هنا.", symbol: "chart.xyaxis.line")
                    } else {
                        Text("حجم التدريب الأسبوعي").font(.headline)
                        Chart(weekly) { item in
                            BarMark(x: .value("الأسبوع", item.date), y: .value("الحجم", settings.displayWeight(item.volume)))
                                .foregroundStyle(settings.color.gradient)
                        }
                        .chartXScale(domain: .automatic(reversed: true))
                        .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: max(1, range / 42))) { axis in
                            AxisGridLine(); AxisValueLabel { if let date = axis.as(Date.self) { Text(shortDate(date)) } }
                        } }
                        .chartYAxis { AxisMarks(position: .leading) { value in
                            AxisGridLine(); AxisValueLabel { if let number = value.as(Double.self) { Text(ArabicFormat.number(number, decimals: 0, arabic: settings.useArabicDigits)) } }
                        } }
                        .frame(height: 190)
                        .accessibilityLabel("حجم التدريب حسب الأسبوع")
                        Text("الحجم = الوزن × التكرارات، مع استبعاد الإحماء.").font(.caption).foregroundStyle(.secondary)
                        Text("عدد الجلسات الأسبوعي").font(.headline)
                        Chart(weekly) { item in
                            BarMark(x: .value("الأسبوع", item.date), y: .value("الجلسات", item.workouts)).foregroundStyle(.blue.gradient)
                        }.chartXScale(domain: .automatic(reversed: true)).chartXAxis { AxisMarks { value in AxisValueLabel { if let date = value.as(Date.self) { Text(shortDate(date)) } } } }
                            .chartYAxis { AxisMarks(position: .leading) { value in AxisValueLabel { if let n = value.as(Int.self) { Text(ArabicFormat.integer(n, arabic: settings.useArabicDigits)) } } } }
                            .frame(height: 150)
                        Text("توزيع المجموعات على العضلات").font(.headline)
                        ForEach(distribution) { item in
                            HStack {
                                Text(item.name).frame(minWidth: 80, alignment: .leading)
                                ProgressView(value: Double(item.sets), total: Double(distribution.map(\.sets).max() ?? 1))
                                Text(ArabicFormat.integer(item.sets, arabic: settings.useArabicDigits)).monospacedDigit()
                            }.accessibilityElement(children: .combine)
                        }
                    }
                    Text("تقدم تمرين محدد").font(.title3.bold())
                    Picker("التمرين", selection: $selectedExercise) {
                        Text("اختر تمرينًا").tag(Optional<UUID>.none)
                        ForEach(exercises) { exercise in Text(exercise.name).tag(Optional(exercise.id)) }
                    }.pickerStyle(.menu)
                    Picker("الرسم", selection: $chartKind) {
                        Text("أقصى تكرار تقديري").tag(0); Text("أعلى وزن").tag(1); Text("الحجم").tag(2)
                    }.pickerStyle(.segmented)
                    if chartKind == 0 {
                        Picker("معادلة التقدير", selection: $formula) {
                            ForEach(OneRepMaxFormula.allCases, id: \.self) { Text($0.arabicName).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    if !samples.isEmpty {
                        Chart(samples) { sample in
                            LineMark(x: .value("التاريخ", sample.date), y: .value("القيمة", settings.displayWeight(chartKind == 0 ? sample.oneRM : chartKind == 1 ? sample.top : sample.volume)))
                                .interpolationMethod(.linear).foregroundStyle(settings.color)
                            PointMark(x: .value("التاريخ", sample.date), y: .value("القيمة", settings.displayWeight(chartKind == 0 ? sample.oneRM : chartKind == 1 ? sample.top : sample.volume))).foregroundStyle(settings.color)
                        }.chartXScale(domain: .automatic(reversed: true)).chartXAxis { AxisMarks { axis in AxisValueLabel { if let d = axis.as(Date.self) { Text(shortDate(d)) } } } }
                            .chartYAxis { AxisMarks(position: .leading) { axis in AxisGridLine(); AxisValueLabel { if let n = axis.as(Double.self) { Text(ArabicFormat.number(n, decimals: 0, arabic: settings.useArabicDigits)) } } } }
                            .frame(height: 220)
                        Text("تقدير أقصى تكرار بمعادلة " + formula.arabicName + ". التقدير أدق مع عشر تكرارات أو أقل.").font(.caption).foregroundStyle(.secondary)
                    } else { Text("لا توجد مجموعات مكتملة لهذا التمرين في الفترة المحددة.").foregroundStyle(.secondary) }
                    NavigationLink("الأرقام الشخصية", destination: PersonalRecordsView()).accessibilityIdentifier("progress.records")
                    NavigationLink("قياسات الجسم", destination: BodyMetricsView())
                    NavigationLink("صور التقدم", destination: ProgressPhotosView())
                    NavigationLink("أهدافي", destination: GoalsView())
                    Text("آخر مئة جلسة").font(.title3.bold())
                    ForEach(finished.prefix(100)) { session in
                        NavigationLink { SessionHistoryView(session: session) } label: {
                            HStack { VStack(alignment: .leading) { Text(session.title).foregroundStyle(.primary); Text(ArabicFormat.date(session.start)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.left") }
                                .padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }.padding()
            }.navigationTitle("تقدّمك").accessibilityIdentifier("progress.screen")
        }
    }
    private func estimate(_ weight: Double, _ reps: Int) -> Double { WorkoutMath.estimatedOneRepMax(weight: weight, reps: reps, formula: formula) }
    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "ar_SA"); formatter.dateFormat = "d MMM"
        return ArabicFormat.digits(formatter.string(from: date), arabic: settings.useArabicDigits)
    }
}

private struct LiftSample: Identifiable { let id: UUID; let date: Date; let oneRM: Double; let top: Double; let volume: Double }
private struct WeekSample: Identifiable { var id: Date { date }; let date: Date; let volume: Double; let workouts: Int }
private struct MuscleSample: Identifiable { var id: String { name }; let name: String; let sets: Int }

func muscleName(_ raw: String) -> String {
    let names = ["chest": "الصدر", "back": "الظهر", "lats": "الظهر", "shoulders": "الأكتاف", "biceps": "العضلة ذات الرأسين", "triceps": "العضلة ثلاثية الرؤوس", "quadriceps": "الفخذ الأمامي", "quads": "الفخذ الأمامي", "hamstrings": "الفخذ الخلفي", "glutes": "الأرداف", "calves": "السمانة", "core": "البطن", "abs": "البطن", "forearms": "الساعد", "fullBody": "الجسم كاملًا", "cardio": "القلب واللياقة"]
    return names[raw] ?? (raw.range(of: "[A-Za-z]", options: .regularExpression) == nil ? raw : "عضلات أخرى")
}

@MainActor struct SessionHistoryView: View {
    let session: WorkoutSession
    @Environment(AppSettings.self) private var settings
    @Query private var exercises: [SessionExercise]
    @Query private var sets: [LoggedSet]
    var body: some View {
        List {
            Section { Text(ArabicFormat.date(session.start)); if !session.notes.isEmpty { Text(session.notes) } }
            ForEach(exercises.filter { $0.sessionID == session.id }.sorted { $0.order < $1.order }) { exercise in
                Section(exercise.name) {
                    if !exercise.notes.isEmpty { Text(exercise.notes).foregroundStyle(.secondary) }
                    ForEach(sets.filter { $0.sessionExerciseID == exercise.id && $0.isCompleted }.sorted { $0.order < $1.order }) { entry in
                        HStack { Text(ArabicFormat.weight(entry.weightKg, settings: settings)); Spacer(); Text(ArabicFormat.integer(entry.reps, arabic: settings.useArabicDigits) + " تكرار") }
                    }
                }
            }
        }.navigationTitle(session.title)
    }
}

@MainActor struct PersonalRecordsView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]
    @Query private var exercises: [Exercise]
    var body: some View {
        List {
            if records.isEmpty { EmptyState(title: "أرقامك القادمة تبدأ الآن", message: "تُسجَّل الأرقام الجديدة تلقائيًا عند إكمال جلسة.", symbol: "trophy") }
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    Text(exercises.first { $0.id == record.exerciseID }?.name ?? "تمرين محفوظ").font(.headline)
                    if record.kindRaw == "reps" {
                        Text("أعلى تكرارات: " + ArabicFormat.integer(Int(record.value), arabic: settings.useArabicDigits) + " عند " + ArabicFormat.weight(record.weightKg, settings: settings))
                    } else {
                        Text(recordLabel(record.kindRaw) + ": " + ArabicFormat.weight(record.value, settings: settings))
                    }
                    Text(ArabicFormat.date(record.achievedAt)).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
        }.navigationTitle("الأرقام الشخصية")
    }
    private func recordLabel(_ raw: String) -> String {
        switch raw { case "weight": return "أعلى وزن"; case "reps": return "أعلى تكرارات"; default: return "أقصى تكرار تقديري" }
    }
}
