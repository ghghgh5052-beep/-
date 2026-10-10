import SwiftUI
import SwiftData

@MainActor struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \FitnessGoal.createdAt, order: .reverse) private var goals: [FitnessGoal]
    @Query(sort: \BodyMetric.date) private var metrics: [BodyMetric]
    @Query private var records: [PersonalRecord]
    @Query private var sessions: [WorkoutSession]
    @State private var showEditor = false
    @State private var errorMessage: String?
    var body: some View {
        List {
            if goals.isEmpty { EmptyState(title: "هدف واضح، خطوة صغيرة", message: "حدد وزنًا أو رقمًا في تمرين أو عدد جلسات أسبوعية.", symbol: "target") }
            ForEach(goals) { goal in
                NavigationLink { GoalEditor(goal: goal) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(goal.title).font(.headline)
                        HStack { Text("الحالي: " + formatted(current(goal), goal: goal)); Spacer(); Text("الهدف: " + formatted(goal.targetValue, goal: goal)) }.font(.subheadline)
                        SwiftUI.ProgressView(value: progress(goal)).tint(settings.color)
                        if let deadline = goal.deadline { Text("الموعد: " + ArabicFormat.date(deadline)).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }
            }.onDelete { offsets in
                for index in offsets where goals.indices.contains(index) { context.delete(goals[index]) }
                do { try context.save() } catch { errorMessage = "تعذر حذف الهدف." }
            }
        }.navigationTitle("أهدافي").toolbar { Button("إضافة", systemImage: "plus") { showEditor = true } }
            .sheet(isPresented: $showEditor) { NavigationStack { GoalEditor(goal: nil) } }.arabicError($errorMessage)
    }
    private func current(_ goal: FitnessGoal) -> Double {
        switch goal.kindRaw {
        case "bodyWeight": return metrics.reversed().compactMap(\.weightKg).first ?? 0
        case "lift": return records.filter { $0.exerciseID == goal.exerciseID && $0.kindRaw == "estimated1RM" }.map(\.value).max() ?? 0
        default:
            var calendar = Calendar(identifier: .gregorian); calendar.firstWeekday = settings.weekStart
            let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
            return Double(sessions.filter { $0.statusRaw == "completed" && $0.start >= start }.count)
        }
    }
    private func progress(_ goal: FitnessGoal) -> Double {
        let value = current(goal)
        if goal.kindRaw == "bodyWeight" {
            let initial = metrics.last(where: { $0.date <= goal.createdAt && $0.weightKg != nil })?.weightKg ?? metrics.first(where: { $0.date >= goal.createdAt && $0.weightKg != nil })?.weightKg
            guard let initial else { return 0 }
            if abs(initial - goal.targetValue) <= 0.01 { return abs(value - goal.targetValue) <= 0.1 ? 1 : 0 }
            return min(1, max(0, (value - initial) / (goal.targetValue - initial)))
        }
        return goal.targetValue > 0 ? min(1, max(0, value / goal.targetValue)) : 0
    }
    private func formatted(_ value: Double, goal: FitnessGoal) -> String {
        goal.kindRaw == "weeklyWorkouts" ? ArabicFormat.integer(Int(value), arabic: settings.useArabicDigits) + " جلسات" : ArabicFormat.weight(value, settings: settings)
    }
}

@MainActor struct GoalEditor: View {
    let goal: FitnessGoal?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var title = ""
    @State private var kind = "bodyWeight"
    @State private var target = ""
    @State private var exerciseID: UUID?
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var errorMessage: String?
    var body: some View {
        Form {
            TextField("اسم الهدف", text: $title)
            Picker("النوع", selection: $kind) { Text("وزن الجسم").tag("bodyWeight"); Text("أقصى تكرار تقديري").tag("lift"); Text("جلسات في الأسبوع").tag("weeklyWorkouts") }
            if kind == "lift" {
                Picker("التمرين", selection: $exerciseID) { Text("اختر تمرينًا").tag(Optional<UUID>.none); ForEach(exercises) { Text($0.name).tag(Optional($0.id)) } }
            }
            NumericField(title: kind == "weeklyWorkouts" ? "عدد الجلسات" : "الوزن المستهدف (" + settings.weightLabel + ")", value: $target)
            Toggle("موعد مستهدف", isOn: $hasDeadline)
            if hasDeadline { DatePicker("الموعد", selection: $deadline, displayedComponents: .date).environment(\.calendar, Calendar(identifier: .gregorian)) }
        }.navigationTitle(goal == nil ? "هدف جديد" : "تعديل الهدف")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("حفظ") { save() } }; ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
            .onAppear {
                if let goal { title = goal.title; kind = goal.kindRaw; target = ArabicFormat.number(goal.kindRaw == "weeklyWorkouts" ? goal.targetValue : settings.displayWeight(goal.targetValue), arabic: settings.useArabicDigits); exerciseID = goal.exerciseID; hasDeadline = goal.deadline != nil; deadline = goal.deadline ?? Date() }
            }.arabicError($errorMessage)
    }
    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let value = ArabicFormat.parse(target), value > 0, value <= 2000, (kind != "lift" || exerciseID != nil), (kind != "weeklyWorkouts" || (value <= 14 && value.rounded() == value)) else {
            errorMessage = "أدخل اسمًا وقيمة صحيحة، واختر التمرين عند الحاجة."; return
        }
        let record = goal ?? FitnessGoal()
        if goal == nil { context.insert(record) }
        record.title = title; record.kindRaw = kind; record.targetValue = kind == "weeklyWorkouts" ? value : settings.kilograms(value)
        record.exerciseID = kind == "lift" ? exerciseID : nil; record.deadline = hasDeadline ? deadline : nil; record.updatedAt = Date()
        do { try context.save(); dismiss() } catch { errorMessage = "تعذر حفظ الهدف." }
    }
}
