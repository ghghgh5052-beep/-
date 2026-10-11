import SwiftUI
import SwiftData
import Charts

@MainActor struct ProgressDashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \SessionExercise.order) private var movements: [SessionExercise]
    @Query(filter: #Predicate<LoggedSet> { $0.isCompleted }) private var sets: [LoggedSet]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var measurements: [SetMeasurement]
    @Query private var trackingPreferences: [ExercisePreference]
    @State private var selectedExercise: UUID?
    @State private var range = 90
    @State private var chartKind = 0
    @State private var volumePeriod = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @WateeraReduceMotion private var reduceMotion: Bool
    @State private var formula = OneRepMaxFormula.epley

    private var finished: [WorkoutSession] { sessions.filter { $0.statusRaw == "completed" } }
    private var cutoff: Date { Calendar.current.date(byAdding: .day, value: -range, to: Date()) ?? Date() }
    private var selectedConvention: String {
        guard let selectedExercise else { return "total" }
        if let preference = trackingPreferences.filter({ $0.exerciseID == selectedExercise }).max(by: { $0.updatedAt < $1.updatedAt }) {
            return preference.conventionRaw
        }
        let itemIDs = Set(movements.filter { $0.exerciseID == selectedExercise }.map(\.id))
        let setIDs = Set(sets.filter { itemIDs.contains($0.sessionExerciseID) }.map(\.id))
        return measurements.filter { setIDs.contains($0.setID) }.max { $0.updatedAt < $1.updatedAt }?.conventionRaw ?? "total"
    }
    private var samples: [LiftSample] {
        guard let selectedExercise else { return [] }
        let movementMap = Dictionary(movements.filter { $0.exerciseID == selectedExercise }.map { ($0.id, $0.sessionID) }, uniquingKeysWith: { first, _ in first })
        let sessionMap = Dictionary(finished.filter { $0.start >= cutoff }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let details = Dictionary(measurements.map { ($0.setID, $0) }, uniquingKeysWith: { first, second in first.updatedAt >= second.updatedAt ? first : second })
        let convention = selectedConvention
        let grouped = Dictionary(grouping: sets.filter { movementMap[$0.sessionExerciseID] != nil && $0.kindRaw != "warmup"
            && (details[$0.id].map { ["reps", "bodyweight"].contains($0.modeRaw) } ?? true)
            && (details[$0.id]?.conventionRaw ?? "total") == convention }) { movementMap[$0.sessionExerciseID] ?? UUID() }
        return grouped.compactMap { sessionID, entries in
            guard let session = sessionMap[sessionID], !entries.isEmpty else { return nil }
            return LiftSample(id: sessionID, date: session.start,
                              oneRM: entries.map { estimate($0.weightKg, $0.reps) }.max() ?? 0,
                              top: entries.map(\.weightKg).max() ?? 0,
                              volume: entries.reduce(0) { $0 + $1.weightKg * Double($1.reps) }, reps: entries.map(\.reps).max() ?? 0)
        }.sorted { $0.date < $1.date }
    }
    private var weekly: [WeekSample] { periodSamples(.weekOfYear) }
    private var monthly: [WeekSample] { periodSamples(.month) }
    private func periodSamples(_ component: Calendar.Component) -> [WeekSample] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = settings.weekStart
        let recent = finished.filter { $0.start >= cutoff }
        let sessionMap = Dictionary(recent.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let exerciseSession = Dictionary(movements.map { ($0.id, $0.sessionID) }, uniquingKeysWith: { first, _ in first })
        var volumes: [Date: Double] = [:]
        var counts: [Date: Int] = [:]
        for session in recent {
            let week = calendar.dateInterval(of: component, for: session.start)?.start ?? calendar.startOfDay(for: session.start)
            counts[week, default: 0] += 1
        }
        for entry in sets where entry.kindRaw != "warmup" {
            guard let id = exerciseSession[entry.sessionExerciseID], let session = sessionMap[id] else { continue }
            let week = calendar.dateInterval(of: component, for: session.start)?.start ?? calendar.startOfDay(for: session.start)
            volumes[week, default: 0] += entry.weightKg * Double(entry.reps)
        }
        let current = calendar.dateInterval(of: component, for: Date())?.start ?? Date()
        let first = calendar.dateInterval(of: component, for: cutoff)?.start ?? cutoff
        let count = max(1, (calendar.dateComponents([component], from: first, to: current).value(for: component) ?? 0) + 1)
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: component, value: -offset, to: current) else { return nil }
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
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeading(title: "جهدك يتحوّل إلى أرقام", subtitle: "قارن نفسك بأمس، واحتفل بما تحقّق")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        StatCard(title: "جلسات مكتملة", value: ArabicFormat.integer(finished.count, arabic: settings.useArabicDigits), symbol: "checkmark.seal").accessibilityIdentifier("progress.completed")
                        StatCard(title: "أسابيع متواصلة", value: ArabicFormat.integer(streak, arabic: settings.useArabicDigits), symbol: "flame")
                    }
                    Picker("الفترة", selection: $range) {
                        Text("شهر").tag(30); Text(ArabicFormat.integer(3, arabic: settings.useArabicDigits) + " أشهر").tag(90); Text("سنة").tag(365); Text("سنتان").tag(730)
                    }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("progress.range")
                    if finished.isEmpty {
                        EmptyState(title: "كل مجموعة تصنع فرقًا", message: "أكمل أول جلسة لتظهر أحجام تدريبك وأرقامك الشخصية هنا.", symbol: "chart.xyaxis.line").wateeraCard()
                    } else { trainingCharts }
                    exerciseProgress
                    SectionHeading(title: "الصورة الكاملة")
                    NavigationLink { WeeklyReportView() } label: { DestinationRow(title: "تقريرك الأسبوعي", subtitle: "جلساتك وحجم التدريب والالتزام", symbol: "chart.bar.doc.horizontal") }.buttonStyle(WateeraCardButtonStyle()).accessibilityIdentifier("progress.weeklyReport")
                    NavigationLink { PersonalRecordsView() } label: { DestinationRow(title: "الأرقام الشخصية", subtitle: "سجل إنجازاتك، تمرينًا بعد تمرين", symbol: "trophy.fill") }.buttonStyle(WateeraCardButtonStyle()).accessibilityIdentifier("progress.records")
                    NavigationLink { TrackingProgressView() } label: { DestinationRow(title: "تقدم الوقت والمسافة والمساعدة", subtitle: "كل طرق تسجيلك، في مكان واحد", symbol: "stopwatch") }.buttonStyle(WateeraCardButtonStyle()).accessibilityIdentifier("progress.tracking")
                    NavigationLink { MuscleRecoveryView() } label: { DestinationRow(title: "خريطة العضلات والتعافي التقديري", subtitle: "توازن تدريبك عبر مجموعات العضلات", symbol: "figure.stand") }.buttonStyle(WateeraCardButtonStyle()).accessibilityIdentifier("progress.recovery")
                    NavigationLink { BodyMetricsView() } label: { DestinationRow(title: "قياسات الجسم", subtitle: "اتجاه الوزن والقياسات والمتوسطات", symbol: "scalemass") }.buttonStyle(WateeraCardButtonStyle())
                    NavigationLink { ProgressPhotosView() } label: { DestinationRow(title: "صور التقدم", subtitle: "قارن رحلتك بصورة", symbol: "photo.on.rectangle.angled") }.buttonStyle(WateeraCardButtonStyle())
                    NavigationLink { GoalsView() } label: { DestinationRow(title: "أهدافي", subtitle: "خطوة واضحة نحو هدفك التالي", symbol: "target") }.buttonStyle(WateeraCardButtonStyle())
                    if !finished.isEmpty { SectionHeading(title: "جلساتك الأخيرة", subtitle: "آخر مئة جلسة") }
                    ForEach(finished.prefix(100)) { session in
                        NavigationLink { SessionHistoryView(session: session) } label: { DestinationRow(title: session.title, subtitle: ArabicFormat.date(session.start), symbol: "checkmark.circle") }.buttonStyle(WateeraCardButtonStyle())
                    }
                }.padding(WateeraDesign.Space.page)
            }.wateeraCanvas().navigationTitle("تقدّمك").accessibilityIdentifier("progress.screen")
        }
    }
    private var trainingCharts: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "حجم التدريب", subtitle: "الوزن × التكرارات، دون الإحماء")
                Picker("تجميع الحجم", selection: $volumePeriod) { Text("أسبوعي").tag(0); Text("شهري").tag(1) }.pickerStyle(.segmented).accessibilityIdentifier("progress.volumePeriod")
                Chart(volumePeriod == 0 ? weekly : monthly) { item in
                    BarMark(x: .value(volumePeriod == 0 ? "الأسبوع" : "الشهر", item.date), y: .value("الحجم", settings.displayWeight(item.volume)))
                        .foregroundStyle(settings.color.gradient).cornerRadius(4)
                        .accessibilityLabel(shortDate(item.date)).accessibilityValue(ArabicFormat.weight(item.volume, settings: settings))
                }.chartXScale(domain: .automatic())
                    .chartXAxis { AxisMarks(values: .stride(by: volumePeriod == 0 ? .weekOfYear : .month, count: volumePeriod == 0 ? max(1, range / 42) : max(1, range / 180))) { axis in
                        AxisValueLabel { if let date = axis.as(Date.self) { Text(shortDate(date)) } }
                    } }
                    .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisValueLabel { if let number = value.as(Double.self) { Text(ArabicFormat.number(number, decimals: 0, arabic: settings.useArabicDigits)) } } } }
                    .frame(height: 210).accessibilityLabel(volumePeriod == 0 ? "حجم التدريب حسب الأسبوع" : "حجم التدريب حسب الشهر")
                Text("الحجم بوحدة " + settings.weightLabel).font(.caption).foregroundStyle(.secondary)
            }.wateeraCard()
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "وتيرة التزامك", subtitle: "عدد الجلسات كل أسبوع")
                Chart(weekly) { item in BarMark(x: .value("الأسبوع", item.date), y: .value("الجلسات", item.workouts)).foregroundStyle(WateeraDesign.blue.gradient).cornerRadius(4) }
                    .chartXScale(domain: .automatic())
                    .chartXAxis { AxisMarks { value in AxisValueLabel { if let date = value.as(Date.self) { Text(shortDate(date)) } } } }
                    .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisValueLabel { if let n = value.as(Int.self) { Text(ArabicFormat.integer(n, arabic: settings.useArabicDigits)) } } } }.frame(height: 150)
            }.wateeraCard()
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "توازن تدريبك", subtitle: "توزيع الجولات على العضلات")
                ForEach(distribution) { item in
                    HStack {
                        Text(item.name).font(.subheadline).frame(minWidth: 70, alignment: .leading)
                        ProgressView(value: Double(item.sets), total: Double(distribution.map(\.sets).max() ?? 1))
                        Text(ArabicFormat.integer(item.sets, arabic: settings.useArabicDigits)).font(.subheadline.bold()).monospacedDigit()
                    }.accessibilityElement(children: .combine)
                }
            }.wateeraCard()
        }
    }
    private var exerciseProgress: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "تقدم تمرين محدد", subtitle: "نفس التمرين، قصة تطوّر جديدة")
            Picker("التمرين", selection: $selectedExercise) {
                Text("اختر تمرينًا").tag(Optional<UUID>.none)
                ForEach(exercises) { exercise in Text(exercise.name).tag(Optional(exercise.id)) }
            }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("progress.exercise")
            Picker("الرسم", selection: $chartKind) {
                Text("أقصى تكرار").tag(0); Text("الوزن").tag(1); Text("الحجم").tag(2); Text("التكرارات").tag(3)
            }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("progress.chartKind")
            if chartKind == 0 {
                Picker("معادلة التقدير", selection: $formula) { ForEach(OneRepMaxFormula.allCases, id: \.self) { Text($0.arabicName).tag($0) } }.pickerStyle(.segmented)
            }
            if !samples.isEmpty {
                Text(chartKind == 3 ? "أعلى عدد تكرارات في الجلسة" : LoadConvention(rawValue: selectedConvention)?.arabicName ?? "الوزن الكلي").font(.caption).foregroundStyle(.secondary)
                Chart(samples) { sample in
                    AreaMark(x: .value("التاريخ", sample.date), y: .value("القيمة", chartValue(sample))).foregroundStyle(LinearGradient(colors: [settings.color.opacity(0.22), settings.color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("التاريخ", sample.date), y: .value("القيمة", chartValue(sample))).interpolationMethod(.linear).lineStyle(StrokeStyle(lineWidth: 3)).foregroundStyle(settings.color)
                    PointMark(x: .value("التاريخ", sample.date), y: .value("القيمة", chartValue(sample))).foregroundStyle(settings.color)
                        .accessibilityLabel(shortDate(sample.date)).accessibilityValue(ArabicFormat.number(chartValue(sample), arabic: settings.useArabicDigits))
                }.chartXScale(domain: .automatic()).chartXAxis { AxisMarks { axis in AxisValueLabel { if let d = axis.as(Date.self) { Text(shortDate(d)) } } } }
                    .chartYAxis { AxisMarks(position: .leading) { axis in AxisGridLine(); AxisValueLabel { if let n = axis.as(Double.self) { Text(ArabicFormat.number(n, decimals: 0, arabic: settings.useArabicDigits)) } } } }
                    .frame(height: 230)
                if chartKind == 0 { Text("تقدير أقصى تكرار بمعادلة " + formula.arabicName + ". التقدير أدق مع عشر تكرارات أو أقل.").font(.caption).foregroundStyle(.secondary) }
                else { Text(chartKind == 3 ? "التكرارات" : "بوحدة " + settings.weightLabel).font(.caption).foregroundStyle(.secondary) }
            } else {
                Text(selectedExercise == nil ? "اختر تمرينًا لعرض الأوزان والتكرارات عبر الجلسات." : "لا توجد مجموعات مكتملة لهذا التمرين في الفترة المحددة.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
            }
        }.wateeraCard().animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: chartKind)
    }
    private func chartValue(_ sample: LiftSample) -> Double {
        chartKind == 3 ? Double(sample.reps) : settings.displayWeight(chartKind == 0 ? sample.oneRM : chartKind == 1 ? sample.top : sample.volume)
    }
    private func estimate(_ weight: Double, _ reps: Int) -> Double { WorkoutMath.estimatedOneRepMax(weight: weight, reps: reps, formula: formula) }
    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "ar_SA"); formatter.dateFormat = "d MMM"
        return ArabicFormat.digits(formatter.string(from: date), arabic: settings.useArabicDigits)
    }
}

private struct LiftSample: Identifiable { let id: UUID; let date: Date; let oneRM: Double; let top: Double; let volume: Double; let reps: Int }
private struct WeekSample: Identifiable { var id: Date { date }; let date: Date; let volume: Double; let workouts: Int }
private struct MuscleSample: Identifiable { var id: String { name }; let name: String; let sets: Int }

func muscleName(_ raw: String) -> String {
    let names = ["chest": "الصدر", "back": "الظهر", "lats": "الظهر", "shoulders": "الأكتاف", "biceps": "العضلة ذات الرأسين", "triceps": "العضلة ثلاثية الرؤوس", "quadriceps": "الفخذ الأمامي", "quads": "الفخذ الأمامي", "hamstrings": "الفخذ الخلفي", "glutes": "الأرداف", "calves": "السمانة", "core": "البطن", "abs": "البطن", "forearms": "الساعد", "fullBody": "الجسم كاملًا", "cardio": "القلب واللياقة"]
    return names[raw] ?? (raw.range(of: "[A-Za-z]", options: .regularExpression) == nil ? raw : "عضلات أخرى")
}

@MainActor struct SessionHistoryView: View {
    let session: WorkoutSession
    @State private var showingEdit = false
    @State private var showingFeedback = false
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
                        SetPerformanceLabel(set: entry)
                    }
                }
            }
            Section {
                Button("تعديل الجلسة أو استبعادها") { showingEdit = true }
                Button("تقييم الجهد والطاقة") { showingFeedback = true }
            }
        }.wateeraCanvas().navigationTitle(session.title)
            .sheet(isPresented: $showingEdit) { SessionEditorView(session: session) }
            .sheet(isPresented: $showingFeedback) { SessionFeedbackView(sessionID: session.id) }
    }
}

@MainActor struct PersonalRecordsView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]
    @Query private var exercises: [Exercise]
    @Query private var measurements: [SetMeasurement]
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
                    Text(LoadConvention(rawValue: measurements.filter { $0.setID == record.setID }.max { $0.updatedAt < $1.updatedAt }?.conventionRaw ?? "total")?.arabicName ?? "الوزن الكلي")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
        }.wateeraCanvas().navigationTitle("الأرقام الشخصية")
    }
    private func recordLabel(_ raw: String) -> String {
        switch raw { case "weight": return "أعلى وزن"; case "reps": return "أعلى تكرارات"; default: return "أقصى تكرار تقديري" }
    }
}
