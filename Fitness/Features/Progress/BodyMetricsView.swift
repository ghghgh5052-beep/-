import SwiftUI
import SwiftData
import Charts

@MainActor struct BodyMetricsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \BodyMetric.date) private var metrics: [BodyMetric]
    @State private var showEditor = false
    @State private var selected = "weight"
    @State private var errorMessage: String?
    private var points: [MetricPoint] {
        metrics.compactMap { metric in
            let raw: Double?
            switch selected {
            case "fat": raw = metric.fatPercent
            case "waist": raw = metric.waistCm.map(settings.displayLength)
            case "chest": raw = metric.chestCm.map(settings.displayLength)
            case "arm": raw = metric.armCm.map(settings.displayLength)
            case "hips": raw = metric.hipsCm.map(settings.displayLength)
            case "thigh": raw = metric.thighCm.map(settings.displayLength)
            default: raw = metric.weightKg.map(settings.displayWeight)
            }
            return raw.map { MetricPoint(id: metric.id, date: metric.date, value: $0) }
        }
    }
    var body: some View {
        List {
            Section {
                Picker("القياس", selection: $selected) {
                    Text("الوزن").tag("weight"); Text("نسبة الدهون").tag("fat")
                    Text("الخصر").tag("waist"); Text("الصدر").tag("chest"); Text("الذراع").tag("arm")
                    Text("الأرداف").tag("hips"); Text("الفخذ").tag("thigh")
                }
                if !points.isEmpty {
                    let averages = ProgressMath.movingAverage(points.map(\.value))
                    Chart(Array(points.enumerated()), id: \.element.id) { index, point in
                        LineMark(x: .value("التاريخ", point.date), y: .value("القياس", point.value), series: .value("السلسلة", "القياس"))
                            .foregroundStyle(settings.color)
                        LineMark(x: .value("التاريخ", point.date), y: .value("المتوسط", averages[index]), series: .value("السلسلة", "المتوسط"))
                            .foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    }.chartXScale(domain: .automatic()).chartXAxis { AxisMarks { value in AxisValueLabel { if let date = value.as(Date.self) { Text(ArabicFormat.date(date)) } } } }
                        .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisValueLabel { if let n = value.as(Double.self) { Text(ArabicFormat.number(n, arabic: settings.useArabicDigits)) } } } }
                        .frame(height: 220)
                    Text("الخط البرتقالي: متوسط آخر سبع قراءات.").font(.caption).foregroundStyle(.secondary)
                } else { EmptyState(title: "تابع تغيرات جسمك", message: "أضف قياسًا أو استورد الوزن من تطبيق الصحة.", symbol: "scalemass") }
                if settings.healthEnabled {
                    Button("قراءة الوزن من تطبيق الصحة") { Task { await importHealthWeight() } }
                }
            }
            Section("القياسات المسجلة") {
                ForEach(metrics.reversed()) { metric in
                    NavigationLink { MetricEditor(metric: metric) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ArabicFormat.date(metric.date))
                            if let weight = metric.weightKg { Text(ArabicFormat.weight(weight, settings: settings)).font(.headline) }
                            if let fat = metric.fatPercent { Text("دهون " + ArabicFormat.number(fat, arabic: settings.useArabicDigits) + "٪").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }.onDelete { offsets in
                    let reversed = Array(metrics.reversed())
                    for index in offsets where reversed.indices.contains(index) { context.delete(reversed[index]) }
                    do { try context.save() } catch { errorMessage = "تعذر حذف القياس." }
                }
            }
        }.navigationTitle("قياسات الجسم")
            .toolbar { Button("إضافة", systemImage: "plus") { showEditor = true } }
            .sheet(isPresented: $showEditor) { NavigationStack { MetricEditor(metric: nil) } }
            .arabicError($errorMessage)
    }
    private func importHealthWeight() async {
        // The explicit HealthKit permission action is owned by the settings screen.
        do {
            let results = try await HealthService.shared.readBodyWeights()
            for reading in results {
                if !metrics.contains(where: { abs($0.date.timeIntervalSince(reading.date)) < 1 && $0.weightKg == reading.kilograms }) {
                    context.insert(BodyMetric(id: reading.id, date: reading.date, weightKg: reading.kilograms))
                }
            }
            try context.save()
        } catch { errorMessage = "تعذر قراءة الوزن. راجع صلاحية تطبيق الصحة ثم حاول مرة أخرى." }
    }
}
private struct MetricPoint: Identifiable { let id: UUID; let date: Date; let value: Double }

@MainActor struct MetricEditor: View {
    let metric: BodyMetric?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var date = Date()
    @State private var weight = ""
    @State private var fat = ""
    @State private var chest = ""
    @State private var waist = ""
    @State private var arm = ""
    @State private var hips = ""
    @State private var thigh = ""
    @State private var errorMessage: String?
    var body: some View {
        Form {
            DatePicker("التاريخ", selection: $date, in: ...Date(), displayedComponents: .date)
                .environment(\.calendar, Calendar(identifier: .gregorian))
            Section("الوزن والدهون") {
                NumericField(title: "الوزن (" + settings.weightLabel + ")", value: $weight)
                NumericField(title: "نسبة الدهون (٪)", value: $fat)
            }
            Section("المحيطات (" + settings.lengthLabel + ")") {
                NumericField(title: "الصدر", value: $chest); NumericField(title: "الخصر", value: $waist)
                NumericField(title: "الذراع", value: $arm); NumericField(title: "الأرداف", value: $hips); NumericField(title: "الفخذ", value: $thigh)
            }
            Text("يمكنك ترك أي قياس لا تحتاج إليه فارغًا.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle(metric == nil ? "قياس جديد" : "تعديل القياس")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("حفظ") { save() } }; ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
            .onAppear {
                guard let metric else { return }
                date = metric.date
                weight = metric.weightKg.map { ArabicFormat.number(settings.displayWeight($0), arabic: settings.useArabicDigits) } ?? ""
                fat = metric.fatPercent.map { ArabicFormat.number($0, arabic: settings.useArabicDigits) } ?? ""
                chest = string(metric.chestCm); waist = string(metric.waistCm); arm = string(metric.armCm); hips = string(metric.hipsCm); thigh = string(metric.thighCm)
            }.arabicError($errorMessage)
    }
    private func string(_ value: Double?) -> String { value.map { ArabicFormat.number(settings.displayLength($0), arabic: settings.useArabicDigits) } ?? "" }
    private func save() {
        let fields = [weight, fat, chest, waist, arm, hips, thigh]
        guard fields.contains(where: { !$0.isEmpty }), fields.allSatisfy({ $0.isEmpty || ((ArabicFormat.parse($0) ?? -1) > 0 && (ArabicFormat.parse($0) ?? 0) < 2000) }), (ArabicFormat.parse(fat) ?? 0) <= 100 else {
            errorMessage = "أدخل قياسًا صحيحًا. نسبة الدهون بين صفر ومئة."; return
        }
        let record = metric ?? BodyMetric()
        if metric == nil { context.insert(record) }
        record.date = date
        record.weightKg = ArabicFormat.parse(weight).map(settings.kilograms)
        record.fatPercent = ArabicFormat.parse(fat)
        record.chestCm = ArabicFormat.parse(chest).map(settings.centimeters)
        record.waistCm = ArabicFormat.parse(waist).map(settings.centimeters)
        record.armCm = ArabicFormat.parse(arm).map(settings.centimeters)
        record.hipsCm = ArabicFormat.parse(hips).map(settings.centimeters)
        record.thighCm = ArabicFormat.parse(thigh).map(settings.centimeters)
        record.updatedAt = Date()
        do { try context.save(); dismiss() } catch { errorMessage = "تعذر حفظ القياس. حاول مرة أخرى." }
    }
}
