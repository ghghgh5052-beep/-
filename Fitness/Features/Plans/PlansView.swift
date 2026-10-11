import SwiftUI
import SwiftData

@MainActor struct PlansView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutCoordinator.self) private var coordinator
    @Query(sort: \WorkoutPlan.name) private var plans: [WorkoutPlan]
    @Query private var days: [PlanDay]
    @Query(sort: \PlanExercise.order) private var assignments: [PlanExercise]
    @Query private var exercises: [Exercise]
    @State private var selectedPlanID: UUID?
    @State private var selectedWeek = 1
    @State private var scheduleMode = 0
    @State private var monthOffset = 0
    @State private var selectedDate = Date.now
    @State private var showArchived = false
    @State private var showingTemplates = false
    @State private var pendingNewPlan: WorkoutPlan?
    @State private var creatingPlanID: UUID?
    @State private var previousActivePlanID: UUID?
    @State private var editingPlan: WorkoutPlan?
    @State private var editingDay: PlanDay?
    @State private var errorMessage: String?

    private var availablePlans: [WorkoutPlan] { plans.filter { $0.isArchived == showArchived } }
    private var selectedPlan: WorkoutPlan? {
        availablePlans.first { $0.id == selectedPlanID } ?? availablePlans.filter { $0.isActive }.max { $0.updatedAt < $1.updatedAt } ?? availablePlans.first
    }
    private var weekdays: [Int] { (0..<7).map { (settings.weekStart - 1 + $0) % 7 + 1 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let plan = selectedPlan {
                        planHeader(plan)
                        if !plan.notes.isEmpty { Text(plan.notes).font(.subheadline).foregroundStyle(.secondary) }
                        if plan.cycleWeeks > 1 {
                            HStack {
                                Text("أسبوع البرنامج").font(.subheadline)
                                Spacer()
                                Picker("أسبوع البرنامج", selection: $selectedWeek) {
                                    ForEach(1...max(1, plan.cycleWeeks), id: \.self) { week in
                                        Text("الأسبوع \(ArabicFormat.integer(week, arabic: settings.useArabicDigits))").tag(week)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            Text("استعرض أسابيع البرنامج وعدّلها. يبدأ التقويم من تاريخ بداية البرنامج.").font(.caption).foregroundStyle(.secondary)
                        }
                        if isDeloadWeek(for: scheduleMode == 1 ? selectedDate : .now, plan: plan) {
                            Label("أسبوع تخفيف: قلّل الأوزان أو عدد الجولات حسب احتياجك.", systemImage: "leaf")
                                .font(.subheadline).foregroundStyle(.green)
                                .padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        }
                        Picker("عرض الجدول", selection: $scheduleMode) {
                            Text("الأسبوع").tag(0)
                            Text("التقويم").tag(1)
                        }.pickerStyle(.segmented)
                        if scheduleMode == 0 {
                            ForEach(weekdays, id: \.self) { weekday in
                                if let day = day(plan: plan, weekday: weekday, week: selectedWeek) {
                                    scheduleCard(day, weekday: weekday)
                                }
                            }
                        } else {
                            calendar(plan)
                            if let selectedDay = scheduledDay(for: selectedDate, plan: plan) {
                                Text(ArabicFormat.date(selectedDate)).font(.headline)
                                scheduleCard(selectedDay, weekday: selectedDay.weekday)
                            } else {
                                Text("هذا التاريخ يسبق بداية البرنامج.").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if showArchived {
                            Button {
                                plan.isArchived = false
                                plan.updatedAt = .now
                                showArchived = false
                                save()
                            } label: { Label("استعادة هذه الخطة", systemImage: "arrow.uturn.backward") }
                                .buttonStyle(WateeraButtonStyle(color: .accentColor)).frame(maxWidth: .infinity)
                        }
                    } else {
                        EmptyState(title: showArchived ? "لا توجد خطط مؤرشفة" : "ابدأ بخطة تناسبك", message: "اختر قالبًا جاهزًا ثم عدّل أيامك وتمارينك، أو أنشئ خطة خاصة.", symbol: "calendar.badge.plus")
                            .frame(minHeight: 280)
                        Button { showingTemplates = true } label: { Label("إنشاء خطة", systemImage: "plus") }
                            .buttonStyle(WateeraButtonStyle(color: .accentColor)).frame(maxWidth: .infinity)
                            .accessibilityIdentifier("plans.add.empty")
                    }
                }
                .padding()
            }
            .background(WateeraDesign.canvas)
            .navigationTitle("خططي")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showArchived.toggle() } label: {
                        Image(systemName: showArchived ? "calendar" : "archivebox")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(showArchived ? "عرض الخطط الحالية" : "عرض الخطط المؤرشفة")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingTemplates = true } label: {
                        Image(systemName: "plus.circle").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("إنشاء خطة جديدة").accessibilityIdentifier("plans.add")
                }
            }
            .sheet(isPresented: $showingTemplates, onDismiss: {
                if let plan = pendingNewPlan { editingPlan = plan; pendingNewPlan = nil }
            }) {
                PlanTemplatePicker { template in
                    let created = createPlan(template: template)
                    selectedPlanID = created?.id
                    pendingNewPlan = created
                    creatingPlanID = created?.id
                    showArchived = false
                    selectedWeek = 1
                }
            }
            .sheet(item: $editingPlan, onDismiss: { creatingPlanID = nil; previousActivePlanID = nil }) { plan in
                PlanSettingsEditor(plan: plan, isNew: plan.id == creatingPlanID, onCancelCreation: { cancelCreation(plan) })
            }
            .sheet(item: $editingDay) { day in PlanDayEditor(day: day) }
            .onAppear { if let plan = selectedPlan { selectedWeek = programWeek(for: .now, plan: plan) } }
            .onChange(of: selectedPlan?.id) { _, _ in if let plan = selectedPlan { selectedWeek = programWeek(for: .now, plan: plan) } }
            .onChange(of: selectedPlan?.cycleWeeks) { _, newValue in selectedWeek = min(selectedWeek, max(1, newValue ?? 1)) }
            .alert("تعذّر حفظ الخطة", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("حسنًا", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "أعد المحاولة.") }
        }
    }

    private func planHeader(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top) {
            Menu {
                ForEach(availablePlans) { candidate in
                    Button {
                        selectedPlanID = candidate.id
                        selectedWeek = programWeek(for: .now, plan: candidate)
                    } label: {
                        if candidate.id == plan.id { Label(candidate.name, systemImage: "checkmark") }
                        else { Text(candidate.name) }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(plan.name).font(.title2.bold()).multilineTextAlignment(.leading)
                    Image(systemName: "chevron.down").font(.caption.bold())
                }.foregroundStyle(.primary)
            }
            Spacer(minLength: 8)
            Menu {
                Button { editingPlan = plan } label: { Label("تعديل الخطة", systemImage: "pencil") }
                if !plan.isActive && !plan.isArchived {
                    Button { activate(plan) } label: { Label("استخدام كخطة حالية", systemImage: "checkmark.circle") }
                }
                Button { duplicate(plan) } label: { Label("نسخ الخطة", systemImage: "doc.on.doc") }
                Button {
                    plan.isArchived.toggle()
                    if plan.isArchived { plan.isActive = false }
                    plan.updatedAt = .now
                    selectedPlanID = nil
                    save()
                } label: { Label(plan.isArchived ? "استعادة الخطة" : "أرشفة الخطة", systemImage: "archivebox") }
            } label: { Image(systemName: "ellipsis.circle").font(.title2).frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("خيارات الخطة")
        }
        if plan.isActive { Label("الخطة الحالية", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(settings.color) }
        }.wateeraCard()
    }

    private func scheduleCard(_ day: PlanDay, weekday: Int) -> some View {
        let items = assignments.filter { $0.dayID == day.id }
        let today = Calendar(identifier: .gregorian).component(.weekday, from: .now) == weekday
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(PlanWeekdays.name(weekday), systemImage: day.isRest ? "moon.zzz" : "dumbbell.fill")
                    .font(.headline).foregroundStyle(day.isRest ? Color.secondary : Color.accentColor)
                if today { Text("اليوم").font(.caption.bold()).foregroundStyle(.tint).padding(.horizontal, 8).padding(.vertical, 3).background(Color.accentColor.opacity(0.1), in: Capsule()) }
                Spacer()
                Button { editingDay = day } label: { Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("تعديل \(PlanWeekdays.name(weekday))")
            }
            Text(day.isRest ? "راحة واستشفاء" : day.title).font(.title3.bold())
            if day.isRest {
                Text("امنح جسمك فرصة للتعافي. يمكنك بدء تمرين حر من تبويب التمرين.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                if items.isEmpty {
                    Text("أضف تمارين لهذا اليوم من زر التعديل.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(items.compactMap { item in exercises.first { $0.id == item.exerciseID }?.name }.joined(separator: "، "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    Text("\(ArabicFormat.integer(items.count, arabic: settings.useArabicDigits)) تمارين · \(ArabicFormat.integer(items.reduce(0) { $0 + $1.targetSets }, arabic: settings.useArabicDigits)) جولة")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !showArchived {
                    Button { coordinator.start(day: day, context: context) } label: { Label("ابدأ التمرين", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(WateeraButtonStyle(color: .accentColor))
                        .disabled(coordinator.activeSessionID != nil)
                        .accessibilityIdentifier("startPlannedWorkoutButton")
                    if coordinator.activeSessionID != nil { Text("لديك تمرين جارٍ. تابعه من تبويب التمرين.").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(16)
        .background(WateeraDesign.surface, in: RoundedRectangle(cornerRadius: WateeraDesign.Radius.card))
    }

    private func calendar(_ plan: WorkoutPlan) -> some View {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(byAdding: .month, value: monthOffset, to: .now) ?? .now
        let components = calendar.dateComponents([.year, .month], from: base)
        let first = calendar.date(from: components) ?? base
        let totalDays = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: first)
        let padding = (firstWeekday - settings.weekStart + 7) % 7
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: settings.useArabicDigits ? "ar_SA" : "ar_SA@numbers=latn")
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM yyyy"
        return VStack(spacing: 16) {
            HStack {
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.backward").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("الشهر السابق")
                Spacer()
                Text(formatter.string(from: first)).font(.headline)
                Spacer()
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.forward").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("الشهر التالي")
            }
            if typeSize.isAccessibilitySize {
                ForEach(1...totalDays, id: \.self) { number in
                    let date = calendar.date(byAdding: .day, value: number - 1, to: first) ?? first
                    let scheduled = scheduledDay(for: date, plan: plan)
                    Button { selectedDate = date } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ArabicFormat.date(date)).font(.headline)
                            Text(scheduled?.isRest == false ? scheduled?.title ?? "تمرين" : "راحة").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(12)
                            .background(calendar.isDate(date, inSameDayAs: selectedDate) ? settings.color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityAddTraits(calendar.isDate(date, inSameDayAs: selectedDate) ? [.isSelected] : [])
                }
            } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 8) {
                ForEach(weekdays, id: \.self) { Text(PlanWeekdays.shortName($0)).font(.caption2.bold()).foregroundStyle(.secondary) }
                ForEach(0..<(padding + totalDays), id: \.self) { index in
                    if index < padding { Color.clear.frame(height: 46) }
                    else {
                        let number = index - padding + 1
                        let date = calendar.date(byAdding: .day, value: number - 1, to: first) ?? first
                        let scheduled = scheduledDay(for: date, plan: plan)
                        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
                        Button { selectedDate = date } label: {
                            VStack(spacing: 5) {
                                Text(ArabicFormat.integer(number, arabic: settings.useArabicDigits)).font(.subheadline.weight(calendar.isDateInToday(date) ? .bold : .regular))
                                Circle().fill(scheduled?.isRest == false ? Color.accentColor : Color.secondary.opacity(0.25)).frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(selected ? WateeraDesign.surface : WateeraDesign.ink)
                            .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(calendar.isDateInToday(date) && !selected ? Color.accentColor : Color.clear))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(ArabicFormat.date(date))، \(scheduled?.isRest == false ? scheduled?.title ?? "تمرين" : "راحة")")
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
            }
            }
        }
        .padding(14)
        .background(WateeraDesign.surface, in: RoundedRectangle(cornerRadius: WateeraDesign.Radius.card))
    }

    private func day(plan: WorkoutPlan, weekday: Int, week: Int) -> PlanDay? {
        days.first { $0.planID == plan.id && $0.weekday == weekday && $0.week == week }
    }

    private func programWeek(for date: Date, plan: WorkoutPlan) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let anchor = calendar.startOfDay(for: plan.programStart)
        let weekday = calendar.component(.weekday, from: anchor)
        let first = calendar.date(byAdding: .day, value: -((weekday - settings.weekStart + 7) % 7), to: anchor) ?? anchor
        let delta = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: date)).day ?? 0
        let offset = max(0, Int(floor(Double(delta) / 7)))
        let count = max(1, plan.cycleWeeks)
        return ((offset % count) + count) % count + 1
    }

    private func scheduledDay(for date: Date, plan: WorkoutPlan) -> PlanDay? {
        let calendar = Calendar(identifier: .gregorian)
        guard calendar.startOfDay(for: date) >= calendar.startOfDay(for: plan.programStart) else { return nil }
        return day(plan: plan, weekday: calendar.component(.weekday, from: date), week: programWeek(for: date, plan: plan))
    }

    private func isDeloadWeek(for date: Date, plan: WorkoutPlan) -> Bool {
        guard plan.deloadEvery > 0 else { return false }
        let calendar = Calendar(identifier: .gregorian)
        let anchor = calendar.startOfDay(for: plan.programStart)
        let weekday = calendar.component(.weekday, from: anchor)
        let first = calendar.date(byAdding: .day, value: -((weekday - settings.weekStart + 7) % 7), to: anchor) ?? anchor
        let delta = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: date)).day ?? 0
        let week = Int(floor(Double(delta) / 7)) + 1
        return week > 0 && week % plan.deloadEvery == 0
    }

    private func activate(_ plan: WorkoutPlan) {
        for candidate in plans where candidate.isActive { candidate.isActive = false; candidate.updatedAt = .now }
        plan.isActive = true
        plan.updatedAt = .now
        save()
    }

    private func createPlan(template: PlanTemplate) -> WorkoutPlan? {
        let plan = WorkoutPlan(name: template.name)
        previousActivePlanID = plans.filter { $0.isActive && !$0.isArchived }.max { $0.updatedAt < $1.updatedAt }?.id
        for candidate in plans where candidate.isActive { candidate.isActive = false; candidate.updatedAt = .now }
        plan.isActive = true
        context.insert(plan)
        for weekday in 1...7 {
            let templateDay = template.days[weekday]
            let newDay = PlanDay(planID: plan.id, weekday: weekday, week: 1, isRest: templateDay == nil, title: templateDay?.title ?? "راحة")
            context.insert(newDay)
            if let templateDay {
                let candidates = exercises.filter { !$0.isArchived && templateDay.muscles.contains($0.primaryMuscleRaw) }
                var selected: [Exercise] = []
                for muscle in templateDay.muscles {
                    let matches = candidates.filter { $0.primaryMuscleRaw == muscle }
                    selected.append(contentsOf: matches.prefix(muscle == "ذراعان" || muscle == "بطن" ? 1 : 2))
                }
                for (order, exercise) in selected.enumerated() {
                    context.insert(PlanExercise(dayID: newDay.id, exerciseID: exercise.id, order: order, targetSets: 3, targetReps: 10, restSeconds: settings.defaultRestSeconds, groupID: ""))
                }
            }
        }
        do { try context.save(); _ = WidgetSnapshotService.refresh(context: context, settings: settings); return plan }
        catch { context.rollback(); errorMessage = "تعذّر إنشاء الخطة. حاول مرة أخرى."; return nil }
    }

    private func cancelCreation(_ plan: WorkoutPlan) -> Bool {
        for day in days.filter({ $0.planID == plan.id }) {
            for item in assignments.filter({ $0.dayID == day.id }) { context.delete(item) }
            context.delete(day)
        }
        context.delete(plan)
        if let previous = plans.first(where: { $0.id == previousActivePlanID && !$0.isArchived }) {
            previous.isActive = true
            previous.updatedAt = .now
            selectedPlanID = previous.id
        } else { selectedPlanID = nil }
        do {
            try context.save()
            _ = WidgetSnapshotService.refresh(context: context, settings: settings)
            return true
        } catch {
            context.rollback()
            errorMessage = "تعذّر إلغاء إنشاء الخطة. حاول مرة أخرى."
            return false
        }
    }

    private func duplicate(_ source: WorkoutPlan) {
        let plan = WorkoutPlan(name: "\(source.name) — نسخة")
        plan.notes = source.notes
        plan.cycleWeeks = source.cycleWeeks
        plan.deloadEvery = source.deloadEvery
        plan.programStart = source.programStart
        context.insert(plan)
        for sourceDay in days.filter({ $0.planID == source.id }) {
            let copied = PlanDay(planID: plan.id, weekday: sourceDay.weekday, week: sourceDay.week, isRest: sourceDay.isRest, title: sourceDay.title)
            context.insert(copied)
            for item in assignments.filter({ $0.dayID == sourceDay.id }) {
                context.insert(PlanExercise(dayID: copied.id, exerciseID: item.exerciseID, order: item.order, targetSets: item.targetSets, targetReps: item.targetReps, restSeconds: item.restSeconds, groupID: item.groupID))
            }
        }
        save()
        selectedPlanID = plan.id
        selectedWeek = 1
    }

    private func save() {
        do { try context.save(); _ = WidgetSnapshotService.refresh(context: context, settings: settings) }
        catch { context.rollback(); errorMessage = "لم يتم حفظ التغيير. حاول مرة أخرى." }
    }
}

private enum PlanWeekdays {
    static func name(_ weekday: Int) -> String {
        let names = ["الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
        return names.indices.contains(weekday - 1) ? names[weekday - 1] : "اليوم"
    }
    static func shortName(_ weekday: Int) -> String {
        let names = ["أحد", "اثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"]
        return names.indices.contains(weekday - 1) ? names[weekday - 1] : "يوم"
    }
}

private struct PlanTemplate: Identifiable {
    struct Day { let title: String; let muscles: [String] }
    let id: String
    let name: String
    let description: String
    let days: [Int: Day]

    static let all: [PlanTemplate] = [
        .init(id: "ppl", name: "الدفع والسحب والأرجل", description: "ستة أيام تدريب ويوم راحة. عدّل عدد الأيام حسب قدرتك على الاستشفاء.", days: [7: .init(title: "الدفع", muscles: ["صدر", "أكتاف", "ذراعان"]), 1: .init(title: "السحب", muscles: ["ظهر", "ذراعان"]), 2: .init(title: "الأرجل", muscles: ["أرجل", "بطن"]), 4: .init(title: "الدفع", muscles: ["صدر", "أكتاف", "ذراعان"]), 5: .init(title: "السحب", muscles: ["ظهر", "ذراعان"]), 6: .init(title: "الأرجل", muscles: ["أرجل", "بطن"])]),
        .init(id: "upperLower", name: "علوي وسفلي", description: "أربعة أيام تدريب، مع راحة بين الجلسات.", days: [7: .init(title: "الجزء العلوي", muscles: ["صدر", "ظهر", "أكتاف"]), 1: .init(title: "الجزء السفلي", muscles: ["أرجل", "بطن"]), 3: .init(title: "الجزء العلوي", muscles: ["صدر", "ظهر", "ذراعان"]), 4: .init(title: "الجزء السفلي", muscles: ["أرجل", "بطن"])]),
        .init(id: "fullBody", name: "الجسم كامل", description: "ثلاث جلسات متوازنة خلال الأسبوع.", days: [7: .init(title: "الجسم كامل", muscles: ["صدر", "ظهر", "أرجل"]), 2: .init(title: "الجسم كامل", muscles: ["أكتاف", "ظهر", "أرجل"]), 4: .init(title: "الجسم كامل", muscles: ["صدر", "أرجل", "بطن"])]),
        .init(id: "custom", name: "خطتي الخاصة", description: "ابدأ بأسبوع فارغ وحدد تمارينك وأيام راحتك.", days: [:])
    ]
}

@MainActor private struct PlanTemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PlanTemplate) -> Void

    var body: some View {
        NavigationStack {
            List(PlanTemplate.all) { template in
                Button {
                    onSelect(template)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(template.name, systemImage: template.id == "custom" ? "square.and.pencil" : "dumbbell.fill").font(.headline)
                        Text(template.description).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 12).foregroundStyle(.primary)
                }
                .accessibilityIdentifier("planTemplate_\(template.id)")
            }
            .wateeraCanvas()
            .navigationTitle("اختر نقطة البداية")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
        }
    }
}

@MainActor private struct PlanSettingsEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query private var days: [PlanDay]
    @Query private var assignments: [PlanExercise]
    let plan: WorkoutPlan
    let isNew: Bool
    let onCancelCreation: () -> Bool
    @State private var name: String
    @State private var notes: String
    @State private var cycleWeeks: Int
    @State private var deloadEvery: Int
    @State private var programStart: Date
    @State private var confirmingReduction = false
    @State private var errorMessage: String?

    init(plan: WorkoutPlan, isNew: Bool = false, onCancelCreation: @escaping () -> Bool = { true }) {
        self.plan = plan
        self.isNew = isNew
        self.onCancelCreation = onCancelCreation
        _name = State(initialValue: plan.name)
        _notes = State(initialValue: plan.notes)
        _cycleWeeks = State(initialValue: max(1, plan.cycleWeeks))
        _deloadEvery = State(initialValue: plan.deloadEvery)
        _programStart = State(initialValue: plan.programStart)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("الخطة") {
                    TextField("اسم الخطة", text: $name).accessibilityIdentifier("plan.name")
                    TextField("ملاحظات الخطة", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    DatePicker("تاريخ بداية البرنامج", selection: $programStart, displayedComponents: .date)
                    Stepper("\(ArabicFormat.integer(cycleWeeks, arabic: settings.useArabicDigits)) أسابيع", value: $cycleWeeks, in: 1...16)
                    Picker("أسبوع تخفيف", selection: $deloadEvery) {
                        Text("بدون تكرار تلقائي").tag(0)
                        ForEach(2...8, id: \.self) { value in Text("كل \(ArabicFormat.integer(value, arabic: settings.useArabicDigits)) أسابيع").tag(value) }
                    }
                } header: { Text("برنامج متعدد الأسابيع") } footer: {
                    Text("عند إضافة أسابيع، تُنسخ أيام الأسبوع الأول لتبدأ منها ثم تعدّلها. أسبوع التخفيف إشارة في جدولك؛ تحدد الأوزان بنفسك.")
                }
            }
            .wateeraCanvas()
            .navigationTitle(isNew ? "خطة جديدة" : "تعديل الخطة").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") {
                        if isNew && !onCancelCreation() { errorMessage = "تعذّر إلغاء إنشاء الخطة. حاول مرة أخرى."; return }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        if cycleWeeks < plan.cycleWeeks { confirmingReduction = true }
                        else { save() }
                    }.bold().disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("plan.save")
                }
            }
            .alert("تقليل أسابيع البرنامج؟", isPresented: $confirmingReduction) {
                Button("تقليل وحفظ", role: .destructive, action: save)
                Button("إلغاء", role: .cancel) {}
            } message: { Text("ستُحذف أيام الأسابيع الزائدة من الخطة. تبقى جميع جلساتك السابقة محفوظة.") }
            .alert("تعذّر الحفظ", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("حسنًا", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "أعد المحاولة.") }
            .interactiveDismissDisabled(isNew)
        }
    }

    private func save() {
        let firstWeek = days.filter { $0.planID == plan.id && $0.week == 1 }
        for week in 1...cycleWeeks {
            for weekday in 1...7 where !days.contains(where: { $0.planID == plan.id && $0.week == week && $0.weekday == weekday }) {
                let source = firstWeek.first { $0.weekday == weekday }
                let created = PlanDay(planID: plan.id, weekday: weekday, week: week, isRest: source?.isRest ?? true, title: source?.title ?? "راحة")
                context.insert(created)
                if let source {
                    for item in assignments.filter({ $0.dayID == source.id }) {
                        context.insert(PlanExercise(dayID: created.id, exerciseID: item.exerciseID, order: item.order, targetSets: item.targetSets, targetReps: item.targetReps, restSeconds: item.restSeconds, groupID: item.groupID))
                    }
                }
            }
        }
        for extra in days.filter({ $0.planID == plan.id && $0.week > cycleWeeks }) {
            for item in assignments.filter({ $0.dayID == extra.id }) { context.delete(item) }
            context.delete(extra)
        }
        plan.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.notes = notes
        plan.cycleWeeks = cycleWeeks
        plan.deloadEvery = deloadEvery
        plan.programStart = programStart
        plan.updatedAt = .now
        do { try context.save(); _ = WidgetSnapshotService.refresh(context: context, settings: settings); dismiss() }
        catch { context.rollback(); errorMessage = "تعذّر حفظ الخطة. حاول مرة أخرى." }
    }
}

@MainActor private struct PlanDayEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \PlanExercise.order) private var assignments: [PlanExercise]
    @Query private var exercises: [Exercise]
    @Bindable var day: PlanDay
    @State private var addingExercise = false
    @State private var errorMessage: String?
    private var items: [PlanExercise] { assignments.filter { $0.dayID == day.id } }

    var body: some View {
        NavigationStack {
            List {
                Section("اليوم") {
                    Toggle("يوم راحة", isOn: $day.isRest)
                    if !day.isRest { TextField("اسم الجلسة", text: $day.title).accessibilityIdentifier("planDayTitleField") }
                }
                if !day.isRest {
                    Section {
                        ForEach(items) { item in
                            PlanExerciseEditorRow(item: item, name: exercises.first { $0.id == item.exerciseID }?.name ?? "تمرين محفوظ", onChange: save)
                        }
                        .onDelete(perform: delete)
                        .onMove(perform: move)
                        Button { addingExercise = true } label: { Label("إضافة تمرين", systemImage: "plus.circle.fill") }.frame(minHeight: 44)
                    } header: { Text("تمارين الجلسة") } footer: {
                        Text("اسحب المقبض لترتيب التمارين. استخدم اسم مجموعة موحدًا لربط تمارين السوبرست أو الدائرة.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(PlanWeekdays.name(day.weekday))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { save(); if errorMessage == nil { dismiss() } }.bold() } }
            .sheet(isPresented: $addingExercise) {
                ExercisePickerView { exercise in
                    let item = PlanExercise(dayID: day.id, exerciseID: exercise.id, order: items.count, targetSets: 3, targetReps: 10, restSeconds: settings.defaultRestSeconds, groupID: "")
                    context.insert(item)
                    save()
                }
            }
            .onChange(of: day.title) { _, _ in save() }
            .onChange(of: day.isRest) { _, _ in save() }
            .onDisappear { _ = WidgetSnapshotService.refresh(context: context, settings: settings) }
            .alert("تعذّر حفظ الجدول", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("حسنًا", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "أعد المحاولة.") }
        }
    }

    private func save() {
        day.updatedAt = .now
        do { try context.save() }
        catch { context.rollback(); errorMessage = "لم يتم حفظ التغيير. حاول مرة أخرى." }
    }
    private func delete(_ offsets: IndexSet) {
        let existing = items
        for index in offsets where existing.indices.contains(index) { context.delete(existing[index]) }
        let remaining = existing.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        for (order, item) in remaining.enumerated() { item.order = order; item.updatedAt = .now }
        save()
    }
    private func move(_ source: IndexSet, _ destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        for (order, item) in reordered.enumerated() { item.order = order; item.updatedAt = .now }
        save()
    }
}

@MainActor private struct PlanExerciseEditorRow: View {
    @Environment(AppSettings.self) private var settings
    @Bindable var item: PlanExercise
    let name: String
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name).font(.headline)
            Stepper("الجولات: \(ArabicFormat.integer(item.targetSets, arabic: settings.useArabicDigits))", value: $item.targetSets, in: 1...20)
            Stepper("التكرارات: \(ArabicFormat.integer(item.targetReps, arabic: settings.useArabicDigits))", value: $item.targetReps, in: 1...100)
            Stepper("الراحة: \(ArabicFormat.duration(TimeInterval(item.restSeconds), arabic: settings.useArabicDigits))", value: $item.restSeconds, in: 0...900, step: 15)
            TextField("مجموعة سوبرست أو دائرة (اختياري)", text: $item.groupID)
                .font(.subheadline)
        }
        .padding(.vertical, 8)
        .onChange(of: item.targetSets) { _, _ in changed() }
        .onChange(of: item.targetReps) { _, _ in changed() }
        .onChange(of: item.restSeconds) { _, _ in changed() }
        .onChange(of: item.groupID) { _, _ in changed() }
    }
    private func changed() { item.updatedAt = .now; onChange() }
}
