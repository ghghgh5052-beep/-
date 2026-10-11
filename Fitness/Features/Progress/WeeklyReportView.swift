import SwiftUI
import SwiftData
import Charts

@MainActor struct WeeklyReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var completedWeek = false
    @State private var report: WeeklyReport?
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("الأسبوع", selection: $completedWeek) {
                    Text("هذا الأسبوع").tag(false); Text("الأسبوع المكتمل").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("report.week")
                if let report {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("خطواتك هذا الأسبوع", systemImage: "chart.bar.doc.horizontal").font(.title2.bold())
                        Text(ArabicFormat.date(report.start) + " — " + ArabicFormat.date(report.end)).font(.caption).foregroundStyle(.secondary)
                        Text(completedWeek ? "مقارنة أسبوعين مكتملين" : "مقارنة بالأيام المناظرة من الأسبوع السابق")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    comparison("الجلسات", current: Double(report.currentSessions), previous: Double(report.previousSessions), symbol: "figure.strengthtraining.traditional", weight: false)
                        .accessibilityIdentifier("report.sessions")
                    comparison("جولات العمل", current: Double(report.currentSets), previous: Double(report.previousSets), symbol: "checkmark.circle", weight: false)
                    comparison("حجم المقاومة", current: report.currentVolume, previous: report.previousVolume, symbol: "scalemass", weight: true)
                    Text("الحجم وفق الوزن المسجل × التكرارات. اختلاف عدد الجولات أو نوع التمارين لا يعني وحده زيادة القوة.").font(.caption).foregroundStyle(.secondary)
                    if report.lifts.isEmpty {
                        EmptyState(title: "ابدأ المقارنة من أول جلسة", message: "تظهر مقارنة أوزان التمارين بعد تسجيل جولات مقاومة مكتملة. الجلسات التجريبية والإحماء مستبعدة.", symbol: "chart.line.uptrend.xyaxis")
                    } else {
                        Text("نفس التمرين، أسبوعًا بعد أسبوع").font(.title3.bold())
                        ForEach(report.lifts) { lift in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(lift.name).font(.headline)
                                LabeledContent("هذا الأسبوع", value: liftLabel(lift.currentWeight, lift.currentReps))
                                Text(LoadConvention(rawValue: lift.convention)?.arabicName ?? "الوزن الكلي").font(.caption).foregroundStyle(.secondary)
                                if lift.comparable {
                                    LabeledContent("الأسبوع السابق", value: liftLabel(lift.previousWeight, lift.previousReps))
                                    Text(lift.currentWeight > lift.previousWeight ? "وزن أعلى في أفضل جولة" :
                                         lift.currentWeight == lift.previousWeight && lift.currentReps > lift.previousReps ? "تكرارات أكثر عند الوزن نفسه" : "راجع الجهد وعدد الجولات مع الأرقام")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else { Text("لا توجد جولة سابقة بنفس نوع التسجيل ومعنى الوزن للمقارنة.").font(.caption).foregroundStyle(.secondary) }
                            }.padding().background(WateeraDesign.surface, in: RoundedRectangle(cornerRadius: WateeraDesign.Radius.card))
                        }
                    }
                    ShareLink(item: shareText(report)) { Label("مشاركة ملخص الأسبوع", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.bordered).accessibilityIdentifier("report.share")
                }
            }.padding()
        }.background(WateeraDesign.canvas)
            .navigationTitle("تقريرك الأسبوعي").navigationBarTitleDisplayMode(.inline)
            .task { refresh() }.refreshable { refresh() }
            .onChange(of: completedWeek) { _, _ in refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
            .arabicError($errorMessage)
    }
    private func comparison(_ title: String, current: Double, previous: Double, symbol: String, weight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack { values(current, previous, weight: weight) }
                VStack(alignment: .leading, spacing: 10) { values(current, previous, weight: weight) }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(WateeraDesign.surface, in: RoundedRectangle(cornerRadius: WateeraDesign.Radius.card))
    }
    @ViewBuilder private func values(_ current: Double, _ previous: Double, weight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text("الحالي").font(.caption).foregroundStyle(.secondary); Text(weight ? ArabicFormat.weight(current, settings: settings) : ArabicFormat.number(current, decimals: 0, arabic: settings.useArabicDigits)).font(.title2.bold()) }
        Spacer(minLength: 12)
        VStack(alignment: .leading, spacing: 4) { Text("السابق").font(.caption).foregroundStyle(.secondary); Text(weight ? ArabicFormat.weight(previous, settings: settings) : ArabicFormat.number(previous, decimals: 0, arabic: settings.useArabicDigits)).font(.title3) }
    }
    private func liftLabel(_ weight: Double, _ reps: Int) -> String { ArabicFormat.weight(weight, settings: settings) + " × " + ArabicFormat.integer(reps, arabic: settings.useArabicDigits) }
    private func refresh() {
        var calendar = Calendar(identifier: .gregorian); calendar.firstWeekday = settings.weekStart
        do { report = try TrainingEnhancementStore.report(context: context, now: .now, calendar: calendar, completedWeek: completedWeek) }
        catch { errorMessage = "تعذر إعداد تقرير الأسبوع؛ أعد المحاولة." }
    }
    private func shareText(_ report: WeeklyReport) -> String {
        let lifts = report.lifts.map { $0.name + ": " + liftLabel($0.currentWeight, $0.currentReps) + " • " + (LoadConvention(rawValue: $0.convention)?.arabicName ?? "الوزن الكلي") }.joined(separator: "\n")
        return "وتيرة • Coach : 3BIID - AB\n" + ArabicFormat.date(report.start) + "\nالجلسات: "
            + ArabicFormat.integer(report.currentSessions, arabic: settings.useArabicDigits) + "\nجولات العمل: "
            + ArabicFormat.integer(report.currentSets, arabic: settings.useArabicDigits) + "\n" + lifts
    }
}

@MainActor struct TrackingProgressView: View {
    @Environment(AppSettings.self) private var settings
    @Query private var sessions: [WorkoutSession]
    @Query private var movements: [SessionExercise]
    @Query private var sets: [LoggedSet]
    @Query private var measurements: [SetMeasurement]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var exerciseID: UUID?
    @State private var mode = SetTrackingMode.timed
    private struct Sample: Identifiable { let id: UUID; let date: Date; let value: Double }
    private var samples: [Sample] {
        let finished = Dictionary(sessions.filter { $0.statusRaw == "completed" }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = Dictionary(movements.filter { $0.exerciseID == exerciseID }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let details = Dictionary(measurements.filter { $0.modeRaw == mode.rawValue }.map { ($0.setID, $0) }, uniquingKeysWith: { first, _ in first })
        var values: [UUID: Double] = [:]
        for set in sets where set.isCompleted && set.kindRaw != "warmup" {
            guard let item = items[set.sessionExerciseID], finished[item.sessionID] != nil, let detail = details[set.id] else { continue }
            let value = mode == .timed ? detail.seconds : mode == .distance ? detail.distanceMeters : detail.assistanceKg
            if mode == .assisted { values[item.sessionID] = min(values[item.sessionID] ?? value, value) }
            else { values[item.sessionID, default: 0] += value }
        }
        return values.compactMap { id, value in finished[id].map { Sample(id: id, date: $0.start, value: value) } }.sorted { $0.date < $1.date }
    }
    private var unit: String { mode == .timed ? "ثانية" : mode == .distance ? "متر" : settings.weightLabel }
    var body: some View {
        List {
            Section {
                Picker("نوع التقدم", selection: $mode) {
                    Text("الثبات").tag(SetTrackingMode.timed); Text("المسافة").tag(SetTrackingMode.distance); Text("المساعدة").tag(SetTrackingMode.assisted)
                }.pickerStyle(.segmented)
                Picker("التمرين", selection: $exerciseID) {
                    Text("اختر تمرينًا").tag(Optional<UUID>.none)
                    ForEach(exercises) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if !samples.isEmpty {
                Section("تقدمك عبر الجلسات") {
                    Chart(samples) { sample in
                        LineMark(x: .value("التاريخ", sample.date), y: .value(unit, mode == .assisted ? settings.displayWeight(sample.value) : sample.value))
                        PointMark(x: .value("التاريخ", sample.date), y: .value(unit, mode == .assisted ? settings.displayWeight(sample.value) : sample.value))
                    }.chartXAxis { AxisMarks { value in AxisValueLabel { if let date = value.as(Date.self) { Text(ArabicFormat.date(date)) } } } }
                        .chartYAxis { AxisMarks(position: .leading) { value in AxisValueLabel { if let number = value.as(Double.self) { Text(ArabicFormat.number(number, arabic: settings.useArabicDigits)) } } } }
                        .frame(height: 220).accessibilityLabel("تقدم التمرين حسب الجلسة، " + unit)
                    ForEach(samples.reversed()) { value in
                        LabeledContent(ArabicFormat.date(value.date), value: ArabicFormat.number(mode == .assisted ? settings.displayWeight(value.value) : value.value, arabic: settings.useArabicDigits) + " " + unit)
                    }
                }
            } else { EmptyState(title: "سجّل جولات من هذا النوع", message: "تظهر الجلسات المكتملة المحتسبة في تقدمك هنا.", symbol: "chart.xyaxis.line") }
            Text(mode == .assisted ? "يُعرض أقل وزن مساعدة في الجلسة. راجع التكرارات معه؛ وزن المساعدة لا يُحتسب كوزن مرفوع." : "يُعرض مجموع الوقت أو المسافة للجولات المكتملة دون الإحماء.").font(.caption).foregroundStyle(.secondary)
        }.wateeraCanvas().navigationTitle("الوقت والمسافة والمساعدة").navigationBarTitleDisplayMode(.inline)
    }
}
