import SwiftUI
import SwiftData
import UIKit

@MainActor struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutCoordinator.self) private var coordinator
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var plans: [WorkoutPlan]
    @Query private var days: [PlanDay]
    @State private var historySession: WorkoutSession?
    @State private var showingCalculator = false
    @State private var showingSmartWorkout = false
    @State private var deletingHistorySession: WorkoutSession?
    @State private var confirmingHistoryDelete = false
    @State private var celebrating = false
    @State private var navigationPath: [WorkoutDashboardRoute] = []

    private var activeSession: WorkoutSession? {
        sessions.first { $0.id == coordinator.activeSessionID && ["active", "paused"].contains($0.statusRaw) }
    }
    private var todaysWorkout: PlanDay? {
        guard let plan = plans.filter({ $0.isActive && !$0.isArchived }).max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        guard calendar.startOfDay(for: plan.programStart) <= calendar.startOfDay(for: .now) else { return nil }
        let anchor = calendar.startOfDay(for: plan.programStart)
        let weekday = calendar.component(.weekday, from: anchor)
        let first = calendar.date(byAdding: .day, value: -((weekday - settings.weekStart + 7) % 7), to: anchor) ?? anchor
        let delta = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: .now)).day ?? 0
        let cycle = max(1, plan.cycleWeeks)
        let week = max(0, Int(floor(Double(delta) / 7))) % cycle + 1
        return days.first { $0.planID == plan.id && $0.weekday == calendar.component(.weekday, from: .now) && $0.week == week }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let session = activeSession {
                    ActiveWorkoutScreen(session: session)
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text(ArabicFormat.date(.now)).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                                    Spacer()
                                    Image(systemName: "figure.strengthtraining.traditional").font(.title).foregroundStyle(Color(red: 0.53, green: 0.96, blue: 0.77)).accessibilityHidden(true)
                                }
                                Text("كل جولة تقرّبك\nمن هدفك").font(.title2.bold()).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                                if let day = todaysWorkout, !day.isRest {
                                    Text("تمرين اليوم: \(day.title)").font(.headline).foregroundStyle(.white)
                                    Button { coordinator.start(day: day, context: context) } label: {
                                        Label("ابدأ تمرين اليوم", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
                                    }.buttonStyle(WorkoutActionButtonStyle(color: Color(red: 0.53, green: 0.96, blue: 0.77), foreground: .black)).accessibilityIdentifier("workout.startToday")
                                } else if todaysWorkout?.isRest == true {
                                    Label("يوم راحة في جدولك", systemImage: "moon.zzz").foregroundStyle(.white.opacity(0.8))
                                }
                                Button { coordinator.start(day: nil, context: context) } label: {
                                    Label("ابدأ تمرينًا حرًا", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(WorkoutActionButtonStyle(color: Color(red: 0.53, green: 0.96, blue: 0.77), foreground: .black)).accessibilityIdentifier("workout.start")
                                Button { showingSmartWorkout = true } label: {
                                    Label("اقترح لي تمرينًا", systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: 38)
                                }.buttonStyle(WorkoutActionButtonStyle(prominent: false, color: .white)).accessibilityIdentifier("workout.smart")
                            }.padding(22).background(WateeraDesign.hero, in: RoundedRectangle(cornerRadius: WateeraDesign.Radius.hero))
                        }
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0)).listRowSeparator(.hidden)
                        Section { DashboardOverview { navigationPath.append($0) } }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)).listRowSeparator(.hidden)
                        if sessions.contains(where: { ["completed", "excluded"].contains($0.statusRaw) }) {
                            Section("جلساتك السابقة") {
                                ForEach(sessions.filter { ["completed", "excluded"].contains($0.statusRaw) }) { session in
                                    Button { historySession = session } label: {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2).accessibilityHidden(true)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(session.title).font(.headline).foregroundStyle(.primary)
                                                if session.statusRaw == "excluded" { Text("تجريبية • لا تُحتسب في التقدم").font(.caption).foregroundStyle(.orange) }
                                                Text(ArabicFormat.date(session.start)).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(ArabicFormat.duration(session.activeDuration(), arabic: settings.useArabicDigits)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                        }.padding(.vertical, 5)
                                    }
                                    .accessibilityIdentifier("workout.history.\(session.id.uuidString)")
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("حذف", role: .destructive) {
                                            deletingHistorySession = session
                                            confirmingHistoryDelete = true
                                        }.disabled(coordinator.isBusy).accessibilityLabel("حذف جلسة \(session.title)")
                                    }
                                }
                            }
                        } else {
                            EmptyState(title: "تاريخك يبدأ من هنا", message: "ابدأ جلسة وسجّل أول جولة. تُحفظ تغييراتك خلال التمرين تلقائيًا.", symbol: "clock.arrow.circlepath")
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .wateeraCanvas()
            .navigationTitle(activeSession == nil ? "التمرين" : "جلسة التمرين")
            .navigationBarTitleDisplayMode(activeSession == nil ? .large : .inline)
            .navigationDestination(for: WorkoutDashboardRoute.self) { route in
                switch route {
                case .calendar: WorkoutCalendarView()
                case .records: PersonalRecordsView()
                }
            }
            .toolbar {
                if activeSession == nil {
                    ToolbarItem(placement: .topBarTrailing) { Button { showingCalculator = true } label: { Image(systemName: "plus.forwardslash.minus") }.accessibilityLabel("حاسبات الأوزان والإحماء") }
                }
            }
            .sheet(item: $historySession, onDismiss: { celebrating = false }) { session in WorkoutSummaryView(session: session, celebrate: celebrating) }
            .sheet(isPresented: $showingCalculator) { WorkoutCalculatorSheet() }
            .sheet(isPresented: $showingSmartWorkout) { NavigationStack { SmartWorkoutView() } }
            .alert("حذف الجلسة؟", isPresented: $confirmingHistoryDelete) {
                Button("حذف الجلسة", role: .destructive) {
                    guard let id = deletingHistorySession?.id else { return }
                    deletingHistorySession = nil
                    Task { await coordinator.deleteSession(id: id, context: context) }
                }.accessibilityIdentifier("workout.delete.confirm")
                Button("تراجع", role: .cancel) { deletingHistorySession = nil }
            } message: {
                Text(SessionDeletionCopy.message(healthExported: deletingHistorySession?.healthExported == true))
            }
            .onChange(of: coordinator.activeSessionID) { previous, current in
                if current != nil { navigationPath.removeAll() }
                if current == nil, let previous, let ended = sessions.first(where: { $0.id == previous && $0.statusRaw == "completed" }) { celebrating = true; historySession = ended }
            }
            .alert("تنبيه التمرين", isPresented: Binding(get: { coordinator.errorMessage != nil }, set: { if !$0 { coordinator.errorMessage = nil } })) {
                Button("حسنًا", role: .cancel) { coordinator.errorMessage = nil }
            } message: { Text(coordinator.errorMessage ?? "أعد المحاولة.") }
        }
    }
}

@MainActor private struct ActiveWorkoutScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutCoordinator.self) private var coordinator
    @Bindable var session: WorkoutSession
    @Query private var sessionExercises: [SessionExercise]
    @Query(sort: \LoggedSet.order) private var allSets: [LoggedSet]
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @State private var addingExercise = false
    @State private var showingOrder = false
    @State private var showingCalculator = false
    @State private var showingNotes = false
    @State private var confirmingFinish = false
    @State private var confirmingDiscard = false
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true

    private var items: [SessionExercise] { sessionExercises.filter { $0.sessionID == session.id }.sorted { $0.order < $1.order } }
    private var completedSets: [LoggedSet] {
        let ids = Set(items.map(\.id))
        return allSets.filter { ids.contains($0.sessionExerciseID) && $0.isCompleted }
    }
    private var paused: Bool { session.statusRaw == "paused" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                if coordinator.restDeadline != nil { restTimer }
                if paused {
                    Label("التمرين متوقف مؤقتًا. استأنف عند الاستعداد.", systemImage: "pause.circle.fill")
                        .font(.subheadline).foregroundStyle(.orange).padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
                if items.isEmpty {
                    EmptyState(title: "اختر أول تمرين", message: "أضف تمرينًا من المكتبة، ثم سجّل الأوزان والتكرارات واضغط علامة الإنجاز.", symbol: "dumbbell.fill")
                }
                ForEach(items) { item in
                    WorkoutExerciseCard(exercise: item, previousSets: previousSets(for: item), paused: paused)
                }
                Button { addingExercise = true } label: { Label("إضافة تمرين", systemImage: "plus.circle.fill").frame(maxWidth: .infinity, minHeight: 38) }
                    .buttonStyle(.bordered).disabled(paused).accessibilityIdentifier("workout.addExercise")
                Button { confirmingFinish = true } label: { Label("إنهاء وحفظ التمرين", systemImage: "checkmark.flag.fill").frame(maxWidth: .infinity, minHeight: 38) }
                    .buttonStyle(WorkoutActionButtonStyle(color: settings.color)).disabled(coordinator.isBusy).accessibilityIdentifier("workout.finish")
                Text("يُحفظ كل تغيير تلقائيًا على جهازك.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Button(role: .destructive) { confirmingDiscard = true } label: {
                    Label("إلغاء التمرين دون حفظ", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).tint(.red).disabled(coordinator.isBusy).accessibilityIdentifier("workout.discard")
            }.padding()
        }
        .background(WateeraDesign.canvas)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { updateIdleTimer() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, _ in updateIdleTimer() }
        .onChange(of: session.statusRaw) { _, _ in updateIdleTimer() }
        .onChange(of: keepScreenAwake) { _, _ in updateIdleTimer() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("إخفاء لوحة المفاتيح") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingNotes = true } label: { Label("ملاحظات الجلسة", systemImage: "note.text") }
                    Button { showingOrder = true } label: { Label("ترتيب التمارين والمجموعات", systemImage: "arrow.up.arrow.down") }
                    Button { showingCalculator = true } label: { Label("حاسبات الأوزان والإحماء", systemImage: "plus.forwardslash.minus") }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("خيارات الجلسة")
            }
        }
        .sheet(isPresented: $addingExercise) {
            ExercisePickerView { exercise in
                let item = SessionExercise(sessionID: session.id, exerciseID: exercise.id, name: exercise.name, order: (items.map(\.order).max() ?? -1) + 1, notes: exercise.notes, groupID: "", restSeconds: settings.defaultRestSeconds)
                context.insert(item)
                context.insert(LoggedSet(sessionExerciseID: item.id, order: 0, reps: 10))
                save()
                coordinator.refreshActivity()
            }
        }
        .sheet(isPresented: $showingOrder) { WorkoutOrderSheet(sessionID: session.id, paused: paused) }
        .sheet(isPresented: $showingCalculator) { WorkoutCalculatorSheet() }
        .sheet(isPresented: $showingNotes) {
            NavigationStack {
                Form {
                    Section("عنوان الجلسة") { TextField("اسم التمرين", text: $session.title).disabled(paused) }
                    Section("ملاحظات الجلسة") { TextField("كيف كان تمرينك اليوم؟", text: $session.notes, axis: .vertical).lineLimit(5...12).disabled(paused) }
                }
                .navigationTitle("ملاحظاتك")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { save(); coordinator.refreshActivity(); showingNotes = false } } }
                .onChange(of: session.title) { _, _ in save() }
                .onChange(of: session.notes) { _, _ in save() }
            }
        }
        .alert("إلغاء التمرين دون حفظ؟", isPresented: $confirmingDiscard) {
            Button("إلغاء دون حفظ", role: .destructive) {
                let id = session.id
                Task { await coordinator.deleteSession(id: id, context: context) }
            }.accessibilityIdentifier("workout.discard.confirm")
            Button("متابعة التمرين", role: .cancel) {}
        } message: {
            Text("ستُحذف هذه الجلسة وكل جولاتها، ولن تظهر في تاريخك أو تُحتسب في تقدمك. لا يمكن التراجع عن الحذف.")
        }
        .alert("إنهاء التمرين؟", isPresented: $confirmingFinish) {
            Button("إنهاء وحفظ") { Task { await coordinator.finish(context: context) } }
            Button("متابعة التمرين", role: .cancel) {}
        } message: {
            Text(completedSets.isEmpty ? "لا توجد جولات مكتملة. ستُحفظ الجلسة مع ملاحظاتك بدون حجم تدريب." : "ستُحفظ الجولات المكتملة ويُحدّث تقدمك وأرقامك الشخصية.")
        }
        .alert("تعذّر الحفظ", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("حسنًا", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "أعد المحاولة.") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.title2.bold())
                    Text(paused ? "متوقف مؤقتًا" : "حان وقت الإنجاز").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if paused { coordinator.resume(session: session, context: context) }
                    else { coordinator.pause(context: context) }
                } label: {
                    Label(paused ? "استئناف" : "إيقاف", systemImage: paused ? "play.fill" : "pause.fill")
                        .font(.subheadline.bold()).frame(minHeight: 44)
                }.buttonStyle(.bordered).accessibilityIdentifier("workout.pause")
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { summaryStats }
            } else {
                HStack(spacing: 12) { summaryStats }
            }
        }.wateeraCard()
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && scenePhase == .active && session.statusRaw == "active"
    }

    @ViewBuilder private var summaryStats: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            StatCard(title: "المدة", value: ArabicFormat.duration(session.activeDuration(at: timeline.date), arabic: settings.useArabicDigits), symbol: "clock", compact: !dynamicTypeSize.isAccessibilitySize)
        }
        StatCard(title: "جولات مكتملة", value: ArabicFormat.integer(completedSets.count, arabic: settings.useArabicDigits), symbol: "checkmark.circle", compact: !dynamicTypeSize.isAccessibilitySize, compactTitle: "الجولات")
        StatCard(title: "حجم التدريب", value: ArabicFormat.weight(WorkoutMath.volume(sets: completedSets.filter { $0.kindRaw != "warmup" }), settings: settings), symbol: "scalemass", compact: !dynamicTypeSize.isAccessibilitySize, compactTitle: "الحجم")
    }

    private var restTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = max(0, coordinator.restDeadline?.timeIntervalSince(timeline.date) ?? 0)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(remaining > 0 ? "وقت الراحة" : "حان موعد الجولة التالية", systemImage: "timer").font(.headline)
                        Text(ArabicFormat.duration(remaining, arabic: settings.useArabicDigits)).font(.largeTitle.monospacedDigit().bold())
                        HStack { restActions(remaining: remaining) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: "timer").font(.title2).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(remaining > 0 ? "وقت الراحة" : "حان موعد الجولة التالية").font(.subheadline.bold())
                            Text(ArabicFormat.duration(remaining, arabic: settings.useArabicDigits)).font(.largeTitle.monospacedDigit().bold())
                        }
                        Spacer(minLength: 0)
                        restActions(remaining: remaining)
                    }
                }
            }
            .padding(16).foregroundStyle(.tint)
            .background(settings.color.opacity(0.12), in: RoundedRectangle(cornerRadius: WateeraDesign.Radius.card))
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder private func restActions(remaining: TimeInterval) -> some View {
        Button { coordinator.startRest(seconds: Int(ceil(remaining)) + 30) } label: {
            Text("+\(ArabicFormat.integer(30, arabic: settings.useArabicDigits)) ث").font(.subheadline.bold()).frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.bordered).accessibilityLabel("إضافة ثلاثين ثانية للراحة")
        Button { coordinator.cancelRest() } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("إلغاء مؤقت الراحة")
    }

    private func previousSets(for item: SessionExercise) -> [LoggedSet] {
        let completedSessionIDs = Set(sessions.filter { $0.id != session.id && $0.statusRaw == "completed" && $0.start < session.start }.map(\.id))
        let pastItems = sessionExercises.filter { $0.exerciseID == item.exerciseID && completedSessionIDs.contains($0.sessionID) }
        let newestSession = sessions.first { candidate in pastItems.contains { $0.sessionID == candidate.id } }
        guard let newestSession else { return [] }
        let ids = Set(pastItems.filter { $0.sessionID == newestSession.id }.map(\.id))
        return allSets.filter { ids.contains($0.sessionExerciseID) && $0.isCompleted }.sorted { $0.order < $1.order }
    }

    private func save() {
        session.updatedAt = .now
        do { try context.save() }
        catch { context.rollback(); errorMessage = "لم يتم حفظ التغيير. حاول مرة أخرى." }
    }
}

@MainActor private struct WorkoutExerciseCard: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutCoordinator.self) private var coordinator
    @Bindable var exercise: SessionExercise
    @Query private var sets: [LoggedSet]
    let previousSets: [LoggedSet]
    let paused: Bool
    @State private var showingDetails = false
    @State private var showingWarmup = false
    @State private var showingGuide = false
    @State private var showingAdvice = false
    @State private var showingAlternatives = false
    @State private var showingTrainingOptions = false
    @State private var confirmingRemove = false
    @State private var errorMessage: String?

    init(exercise: SessionExercise, previousSets: [LoggedSet], paused: Bool) {
        self.exercise = exercise
        self.previousSets = previousSets
        self.paused = paused
        let id = exercise.id
        _sets = Query(filter: #Predicate<LoggedSet> { $0.sessionExerciseID == id }, sort: \LoggedSet.order)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(exercise.name).font(.headline)
                    if !exercise.groupID.isEmpty { Label("مجموعة: \(exercise.groupID)", systemImage: "link").font(.caption).foregroundStyle(.tint) }
                    Label("راحة \(ArabicFormat.duration(TimeInterval(exercise.restSeconds), arabic: settings.useArabicDigits))", systemImage: "timer").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button { showingDetails = true } label: { Label("الملاحظات والراحة", systemImage: "note.text") }
                    Button { showingAlternatives = true } label: { Label("استبدال بتمرين بديل", systemImage: "arrow.triangle.swap") }
                    Button { showingTrainingOptions = true } label: { Label("التسجيل وبرنامج التدرّج", systemImage: "slider.horizontal.3") }
                    Button { showingWarmup = true } label: { Label("إضافة جولات إحماء", systemImage: "flame") }
                    if SmartExerciseMetadata.forBuiltInID(exercise.exerciseID)?.mode == .reps {
                        Button { showingAdvice = true } label: { Label("اقتراح الأوزان والتكرارات", systemImage: "sparkles") }
                    }
                    Button { coordinator.startRest(seconds: exercise.restSeconds) } label: { Label("بدء الراحة", systemImage: "timer") }
                    Button(role: .destructive) { confirmingRemove = true } label: { Label("إزالة من الجلسة", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.disabled(paused).accessibilityLabel("خيارات \(exercise.name)")
                    .accessibilityIdentifier("workout.exercise.options.\(exercise.exerciseID.uuidString)")
            }
            if ExerciseGuides.guide(for: exercise.exerciseID) != nil {
                Button { showingGuide = true } label: {
                    Label("صورة التمرين وطريقة التنفيذ", systemImage: "photo")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("workout.exercise.guide.\(exercise.exerciseID.uuidString)")
                .accessibilityLabel("عرض صورة وطريقة تنفيذ \(exercise.name)")
            }
            if !exercise.notes.isEmpty { Text(exercise.notes).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    Text("جولة").frame(width: 44)
                    Text("القيمة").frame(maxWidth: .infinity)
                    Text("تكرار / مدة").frame(maxWidth: .infinity)
                    Text("تم").frame(width: 44)
                }.font(.caption2.bold()).foregroundStyle(.secondary)
            }
            ForEach(sets) { set in
                WorkoutSetRow(set: set, exercise: exercise, previous: previousSets.indices.contains(set.order) ? previousSets[set.order] : nil, paused: paused)
            }
            HStack(spacing: 12) {
                Button { addSet(copy: false) } label: { Label("جولة", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44) }
                    .accessibilityLabel("إضافة جولة لـ \(exercise.name)")
                Button { addSet(copy: true) } label: { Label("نسخ الأخيرة", systemImage: "doc.on.doc").frame(maxWidth: .infinity, minHeight: 44) }
                    .accessibilityLabel("نسخ آخر جولة لـ \(exercise.name)")
            }.buttonStyle(.bordered).font(.subheadline).disabled(paused)
        }
        .padding(16)
        .background(WateeraDesign.surface, in: RoundedRectangle(cornerRadius: WateeraDesign.Radius.card))
        .sheet(isPresented: $showingGuide) {
            if let guide = ExerciseGuides.guide(for: exercise.exerciseID) {
                ExerciseGuideSheet(guide: guide, exerciseName: exercise.name)
            }
        }
        .sheet(isPresented: $showingAdvice) { NavigationStack { ExerciseAdviceView(exercise: exercise) } }
        .sheet(isPresented: $showingAlternatives) { ExerciseAlternativesView(item: exercise) }
        .sheet(isPresented: $showingTrainingOptions) { TrainingOptionsView(exerciseID: exercise.exerciseID, name: exercise.name, sessionExerciseID: exercise.id) }
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                Form {
                    Section("ملاحظات التمرين") { TextField("ملاحظاتك لهذه الجلسة", text: $exercise.notes, axis: .vertical).lineLimit(4...10) }
                    Section {
                        Stepper("الراحة: \(ArabicFormat.duration(TimeInterval(exercise.restSeconds), arabic: settings.useArabicDigits))", value: $exercise.restSeconds, in: 0...900, step: 15)
                        TextField("اسم السوبرست أو الدائرة", text: $exercise.groupID)
                    } header: { Text("الراحة والمجموعات") } footer: { Text("استخدم الاسم نفسه في التمارين المرتبطة؛ يُعرض الاسم أثناء التسجيل والترتيب.") }
                }.wateeraCanvas().navigationTitle(exercise.name).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { save(); showingDetails = false } } }
                    .onChange(of: exercise.notes) { _, _ in save() }
                    .onChange(of: exercise.groupID) { _, _ in save() }
                    .onChange(of: exercise.restSeconds) { _, _ in save() }
            }
        }
        .sheet(isPresented: $showingWarmup) {
            WorkoutCalculatorSheet(initialMode: 1, initialWeightKg: sets.last?.weightKg ?? previousSets.last?.weightKg ?? 60) { warmups in
                let existingSets = sets
                for (index, value) in warmups.enumerated() {
                    context.insert(LoggedSet(sessionExerciseID: exercise.id, order: index, weightKg: settings.kilograms(value.weight), reps: value.reps, kindRaw: "warmup"))
                }
                for item in existingSets { item.order += warmups.count; item.updatedAt = .now }
                save()
            }
        }
        .confirmationDialog("إزالة التمرين من هذه الجلسة؟", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("إزالة التمرين وجولاته", role: .destructive) {
                let ids = Set(sets.map(\.id))
                do {
                    for value in try context.fetch(FetchDescriptor<SetMeasurement>()) where ids.contains(value.setID) { context.delete(value) }
                } catch { errorMessage = "تعذر قراءة تفاصيل الجولات؛ لم يُحذف التمرين."; return }
                for set in sets { context.delete(set) }
                context.delete(exercise)
                do { try context.save(); coordinator.refreshActivity() } catch { context.rollback(); errorMessage = "تعذّر إزالة التمرين. حاول مرة أخرى." }
            }
        } message: { Text("تبقى جلسات هذا التمرين السابقة محفوظة.") }
        .alert("تعذّر الحفظ", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("حسنًا", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "أعد المحاولة.") }
    }

    private func addSet(copy: Bool) {
        let last = sets.last ?? previousSets.last
        let new = LoggedSet(sessionExerciseID: exercise.id, order: (sets.map(\.order).max() ?? -1) + 1, weightKg: last?.weightKg ?? 0, reps: last?.reps ?? 10, rpe: copy ? last?.rpe : nil, kindRaw: copy ? last?.kindRaw ?? "working" : "working")
        context.insert(new)
        if copy, let last {
            do {
                if let prior = try context.fetch(FetchDescriptor<SetMeasurement>()).first(where: { $0.setID == last.id }) {
                    context.insert(SetMeasurement(setID: new.id, modeRaw: prior.modeRaw, seconds: prior.seconds,
                        distanceMeters: prior.distanceMeters, assistanceKg: prior.assistanceKg, conventionRaw: prior.conventionRaw))
                }
            } catch { context.delete(new); errorMessage = "تعذر نسخ الجولة؛ حاول مجددًا."; return }
        }
        save()
    }
    private func save() {
        exercise.updatedAt = .now
        do { try context.save() }
        catch { context.rollback(); errorMessage = "لم يتم حفظ التغيير. حاول مرة أخرى." }
    }
}

@MainActor private struct WorkoutSetRow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @WateeraReduceMotion private var reduceMotion: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutCoordinator.self) private var coordinator
    @Bindable var set: LoggedSet
    let exercise: SessionExercise
    let previous: LoggedSet?
    let paused: Bool
    @State private var showingDetails = false
    @State private var errorMessage: String?
    @Query private var measurements: [SetMeasurement]
    @State private var weightInputValid = true
    @State private var repsInputValid = true
    @State private var trackingInputValidity: [String: Bool] = [:]
    private var measurement: SetMeasurement? { measurements.max { $0.updatedAt < $1.updatedAt } }
    private var trackingMode: SetTrackingMode { measurement.flatMap { SetTrackingMode(rawValue: $0.modeRaw) } ?? .reps }

    init(set: LoggedSet, exercise: SessionExercise, previous: LoggedSet?, paused: Bool) {
        self.set = set; self.exercise = exercise; self.previous = previous; self.paused = paused
        let id = set.id
        _measurements = Query(filter: #Predicate<SetMeasurement> { $0.setID == id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if trackingMode == .timed || trackingMode == .distance || trackingMode == .assisted {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { indexButton; Text(trackingMode.arabicName).font(.subheadline.bold()); Spacer(); completionButton }
                    if let measurement {
                        if trackingMode == .timed || trackingMode == .distance {
                            HStack {
                                Text("ثواني"); Spacer(minLength: 12)
                                trackingField(Binding(get: { measurement.seconds }, set: { measurement.seconds = $0; measurement.updatedAt = .now; save() }), maximum: 86_400, label: "مدة الجولة بالثواني", identifier: "set.seconds.\(set.order)")
                            }
                            if trackingMode == .distance {
                                HStack {
                                    Text("متر"); Spacer(minLength: 12)
                                    trackingField(Binding(get: { measurement.distanceMeters }, set: { measurement.distanceMeters = $0; measurement.updatedAt = .now; save() }), maximum: 1_000_000, label: "مسافة الجولة بالمتر", identifier: "set.distance.\(set.order)")
                                }
                            }
                        } else {
                            HStack {
                                Text("المساعدة (\(settings.weightLabel))"); Spacer(minLength: 12)
                                trackingField(Binding(get: { settings.displayWeight(measurement.assistanceKg) }, set: { measurement.assistanceKg = settings.kilograms($0); measurement.updatedAt = .now; save() }), maximum: settings.displayWeight(2_000), label: "وزن المساعدة", identifier: "set.assistance.\(set.order)")
                            }
                            HStack { Text("التكرارات"); Spacer(minLength: 12); repsField.frame(maxWidth: 150) }
                        }
                    }
                }
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { indexButton; Spacer(); completionButton }
                    Text("الوزن (\(settings.weightLabel))").font(.subheadline)
                    weightField
                    Text("التكرارات").font(.subheadline)
                    repsField
                }
            } else {
                HStack(spacing: 8) { indexButton; weightField; repsField; completionButton }
            }
            if let previous {
                HStack {
                    HStack(spacing: 4) { Text("السابق:"); SetPerformanceLabel(set: previous) }
                    Spacer(minLength: 4)
                    if !set.isCompleted {
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            copyPrevious(previous)
                        } label: { Image(systemName: "arrow.down.doc").frame(minWidth: 44, minHeight: 44) }.disabled(paused).accessibilityLabel("استخدام أرقام الجلسة السابقة")
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let rpe = set.rpe { Text("الجهد: \(ArabicFormat.number(rpe, arabic: settings.useArabicDigits)) من \(ArabicFormat.integer(10, arabic: settings.useArabicDigits))").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(set.isCompleted ? Color.green.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: set.isCompleted)
        .onChange(of: trackingMode) { _, _ in trackingInputValidity = [:] }
        .task {
            guard measurement == nil, !set.isCompleted else { return }
            do { _ = try TrainingEnhancementStore.measurement(set: set, exerciseID: exercise.exerciseID, context: context); try context.save() }
            catch { errorMessage = "تعذر تجهيز تسجيل الجولة." }
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                Form {
                    Section("نوع الجولة") {
                        Picker("النوع", selection: $set.kindRaw) {
                            ForEach(SetKindLabels.values, id: \.self) { Text(SetKindLabels.name($0)).tag($0) }
                        }.disabled(set.isCompleted)
                    }
                    Section {
                        Toggle("تسجيل مستوى الجهد", isOn: Binding(get: { set.rpe != nil }, set: { set.rpe = $0 ? 8 : nil; save() }))
                            .disabled(set.isCompleted)
                        if set.rpe != nil {
                            Stepper("\(ArabicFormat.number(set.rpe ?? 8, arabic: settings.useArabicDigits)) من \(ArabicFormat.integer(10, arabic: settings.useArabicDigits))", value: Binding(get: { set.rpe ?? 8 }, set: { set.rpe = $0; save() }), in: 1...10, step: 0.5).disabled(set.isCompleted)
                        }
                    } header: { Text("الجهد المدرك (اختياري)") } footer: { Text("عشرة تعني أقصى جهد، وثمانية تعني أنك قادر على تكرارين إضافيين تقريبًا.") }
                    if set.isCompleted { Text("ألغِ إنجاز الجولة لتعديل قيمها.").font(.caption).foregroundStyle(.secondary) }
                    Section {
                        Button("حذف الجولة", role: .destructive) {
                            deleteSet()
                        }.disabled(set.isCompleted)
                    }
                }.wateeraCanvas().navigationTitle("تفاصيل الجولة").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { save(); showingDetails = false } } }
                    .onChange(of: set.kindRaw) { _, _ in save() }
            }
        }
        .alert("تحقّق من الجولة", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("حسنًا", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "أعد المحاولة.") }
    }

    private func trackingField(_ value: Binding<Double>, maximum: Double, label: String, identifier: String) -> some View {
        GymNumberField(value: value, decimals: 2, maximum: maximum, label: label, identifier: identifier,
            onValidityChange: { trackingInputValidity[identifier] = $0 }).disabled(paused || set.isCompleted).frame(maxWidth: 150)
    }

    private func copyPrevious(_ previous: LoggedSet) {
        do {
            let id = previous.id
            let prior = try context.fetch(FetchDescriptor<SetMeasurement>(predicate: #Predicate { $0.setID == id })).first
            let previousMode = SetTrackingMode(rawValue: prior?.modeRaw ?? "reps") ?? .reps
            guard (previousMode == trackingMode || previousMode.supportsWeightRecords && trackingMode.supportsWeightRecords),
                  (prior?.conventionRaw ?? "total") == (measurement?.conventionRaw ?? "total") else {
                errorMessage = "تغيّر نوع التسجيل أو معنى الوزن؛ راجع القيم السابقة وأدخل القيم المناسبة يدويًا."; return
            }
            set.weightKg = previous.weightKg; set.reps = previous.reps
            measurement?.seconds = prior?.seconds ?? 0
            measurement?.distanceMeters = prior?.distanceMeters ?? 0
            measurement?.assistanceKg = prior?.assistanceKg ?? 0
            measurement?.updatedAt = .now
            save()
        } catch { errorMessage = "تعذر قراءة الجولة السابقة." }
    }

    private var indexButton: some View {
        Button { showingDetails = true } label: {
            VStack(spacing: 3) {
                Text(ArabicFormat.integer(set.order + 1, arabic: settings.useArabicDigits)).font(.subheadline.bold())
                if set.kindRaw != "working" { Text(SetKindLabels.short(set.kindRaw)).font(.caption2) }
            }.frame(minWidth: 44, minHeight: 48).foregroundStyle(set.kindRaw == "warmup" ? Color.orange : Color.secondary)
        }.buttonStyle(.plain).disabled(paused).accessibilityLabel("تفاصيل الجولة \(ArabicFormat.integer(set.order + 1, arabic: settings.useArabicDigits))")
    }

    private var weightField: some View {
        GymNumberField(value: Binding(get: { settings.displayWeight(set.weightKg) }, set: { set.weightKg = settings.kilograms($0); save() }), decimals: 2, maximum: settings.displayWeight(2_000), label: "وزن الجولة \(ArabicFormat.integer(set.order + 1, arabic: settings.useArabicDigits))", identifier: "set.weight.\(set.order)", onValidityChange: { weightInputValid = $0 })
            .disabled(paused || set.isCompleted)
    }

    private var repsField: some View {
        GymNumberField(value: Binding(get: { Double(set.reps) }, set: { set.reps = Int($0); save() }), decimals: 0, maximum: 5_000, label: "تكرارات الجولة \(ArabicFormat.integer(set.order + 1, arabic: settings.useArabicDigits))", identifier: "set.reps.\(set.order)", onValidityChange: { repsInputValid = $0 })
            .disabled(paused || set.isCompleted)
    }

    private var completionButton: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            if set.isCompleted {
                set.isCompleted = false
                set.completedAt = nil
                save()
                coordinator.refreshActivity()
            } else if measurement.map({ TrainingEnhancementStore.validMeasurement($0, set: set) }) ?? (set.reps > 0 && set.weightKg >= 0 && set.weightKg.isFinite) {
                coordinator.complete(set: set, exercise: exercise, context: context)
            } else { errorMessage = "أدخل قيم الجولة كاملة قبل تسجيل الإنجاز؛ يجب أن تكون المدة والمسافة أو التكرارات أكبر من صفر." }
        } label: {
            Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 30, weight: .semibold)).frame(width: 44, height: 48)
                .foregroundStyle(set.isCompleted ? Color.green : Color.accentColor)
        }.buttonStyle(.plain).disabled(paused || !weightInputValid || !repsInputValid || trackingInputValidity.values.contains(false)).accessibilityIdentifier("set.complete.\(set.order)")
            .accessibilityLabel(set.isCompleted ? "إلغاء إنجاز الجولة \(ArabicFormat.integer(set.order + 1, arabic: settings.useArabicDigits))" : "إنجاز الجولة \(ArabicFormat.integer(set.order + 1, arabic: settings.useArabicDigits))")
    }

    private func save() {
        set.updatedAt = .now
        do { try context.save() }
        catch { context.rollback(); errorMessage = "لم يتم حفظ الجولة. حاول مرة أخرى." }
    }

    private func deleteSet() {
        let exerciseID = set.sessionExerciseID
        do {
            let siblings = try context.fetch(FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.sessionExerciseID == exerciseID }, sortBy: [SortDescriptor(\.order)]))
            let remaining = siblings.filter { $0.id != set.id }
            for value in try context.fetch(FetchDescriptor<SetMeasurement>()) where value.setID == set.id { context.delete(value) }
            context.delete(set)
            for (order, item) in remaining.enumerated() { item.order = order; item.updatedAt = .now }
            try context.save()
            showingDetails = false
            coordinator.refreshActivity()
        } catch { context.rollback(); errorMessage = "تعذّر حذف الجولة. حاول مرة أخرى." }
    }
}

enum SetKindLabels {
    static let values = ["warmup", "working", "drop", "failure"]
    static func name(_ kind: String) -> String {
        switch kind {
        case "warmup": return "إحماء"
        case "drop": return "خفض الوزن"
        case "failure": return "حتى الفشل"
        default: return "أساسية"
        }
    }
    static func short(_ kind: String) -> String {
        switch kind {
        case "warmup": return "إحماء"
        case "drop": return "خفض"
        case "failure": return "فشل"
        default: return "أساسية"
        }
    }
}

@MainActor struct GymNumberField: View {
    @Environment(AppSettings.self) private var settings
    @Binding var value: Double
    let decimals: Int
    let maximum: Double
    let label: String
    let identifier: String
    var onValidityChange: ((Bool) -> Void)? = nil
    @State private var text = ""
    @State private var valid = true
    @FocusState private var focused: Bool

    var body: some View {
        TextField(ArabicFormat.integer(0, arabic: settings.useArabicDigits), text: $text)
            .keyboardType(decimals == 0 ? .numberPad : .decimalPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 4).frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(valid ? Color.clear : Color.red, lineWidth: 1))
            .focused($focused)
            .accessibilityLabel(label).accessibilityIdentifier(identifier)
            .onAppear { refresh() }
            .onChange(of: text) { _, newValue in
                guard focused else { return }
                if let parsed = ArabicFormat.parse(newValue), parsed.isFinite, parsed >= 0, parsed <= maximum {
                    valid = true
                    let normalized = decimals == 0 ? parsed.rounded(.towardZero) : parsed
                    if abs(value - normalized) > 0.00001 { value = normalized }
                } else {
                    valid = false
                }
                onValidityChange?(valid)
            }
            .onChange(of: value) { _, _ in if !focused { refresh() } }
            .onChange(of: focused) { _, newValue in
                if newValue {
                    // One-handed editing replaces the existing number in either digit system.
                    DispatchQueue.main.async {
                        if focused {
                            UIApplication.shared.sendAction(#selector(UITextField.selectAll(_:)), to: nil, from: nil, for: nil)
                        }
                    }
                } else { refresh() }
            }
            .onChange(of: settings.useArabicDigits) { _, _ in refresh() }
            .onChange(of: settings.weightUnit) { _, _ in refresh() }
    }
    private func refresh() {
        text = ArabicFormat.number(value, decimals: decimals, arabic: settings.useArabicDigits)
        valid = value.isFinite && value >= 0 && value <= maximum
        onValidityChange?(valid)
    }
}

@MainActor private struct WorkoutOrderSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SessionExercise.order) private var allExercises: [SessionExercise]
    let sessionID: UUID
    let paused: Bool
    @State private var errorMessage: String?
    private var items: [SessionExercise] { allExercises.filter { $0.sessionID == sessionID } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { exercise in
                        WorkoutGroupRow(exercise: exercise, onChange: save).disabled(paused)
                    }.onMove { source, destination in
                        var reordered = items
                        reordered.move(fromOffsets: source, toOffset: destination)
                        for (order, item) in reordered.enumerated() { item.order = order; item.updatedAt = .now }
                        save()
                    }
                } footer: { Text("حرّك المقبض لترتيب التمارين. اربط تمارين السوبرست أو الدائرة بكتابة اسم المجموعة نفسه.") }
            }
            .environment(\.editMode, .constant(paused ? .inactive : .active))
            .navigationTitle("الترتيب والمجموعات").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
            .alert("تعذّر الحفظ", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("حسنًا", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "أعد المحاولة.") }
        }
    }
    private func save() {
        do { try context.save() }
        catch { context.rollback(); errorMessage = "لم يتم حفظ الترتيب. حاول مرة أخرى." }
    }
}

@MainActor private struct WorkoutGroupRow: View {
    @Bindable var exercise: SessionExercise
    let onChange: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.name).font(.headline)
            TextField("اسم السوبرست أو الدائرة (اختياري)", text: $exercise.groupID).font(.subheadline)
        }.padding(.vertical, 8).onChange(of: exercise.groupID) { _, _ in exercise.updatedAt = .now; onChange() }
    }
}

@MainActor private struct WorkoutSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutCoordinator.self) private var coordinator
    @State private var confirmingDelete = false
    @State private var deletionError: String?
    @State private var showingEdit = false
    @State private var showingFeedback = false
    let session: WorkoutSession
    var celebrate = false
    @State private var sharedAchievement: SharedAchievement?
    @State private var shareError: String?
    @Query private var exercises: [SessionExercise]
    @Query private var sets: [LoggedSet]
    @Query private var records: [PersonalRecord]
    private var items: [SessionExercise] { exercises.filter { $0.sessionID == session.id }.sorted { $0.order < $1.order } }
    private var completed: [LoggedSet] {
        let ids = Set(items.map(\.id))
        return sets.filter { ids.contains($0.sessionExerciseID) && $0.isCompleted }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        CompletionBadge(celebrate: celebrate && session.statusRaw == "completed", hasRecords: records.contains { $0.sessionID == session.id })
                        Text(session.statusRaw == "excluded" ? "جلسة تجريبية محفوظة" : "أحسنت، تمرينك محفوظ").font(.title2.bold()).foregroundStyle(settings.color)
                        Text(session.title).font(.headline)
                        Text(ArabicFormat.date(session.start)).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                    LabeledContent("المدة", value: ArabicFormat.duration(session.activeDuration(), arabic: settings.useArabicDigits))
                    LabeledContent("جولات مكتملة", value: ArabicFormat.integer(completed.count, arabic: settings.useArabicDigits))
                    LabeledContent("حجم التدريب", value: ArabicFormat.weight(WorkoutMath.volume(sets: completed.filter { $0.kindRaw != "warmup" }), settings: settings))
                }
                Section {
                    if session.statusRaw == "completed" {
                        Button { shareAchievement() } label: { Label("شارك إنجازك", systemImage: "square.and.arrow.up").frame(minHeight: 44) }.accessibilityIdentifier("workout.summary.share")
                    }
                    Button { showingEdit = true } label: { Label("تعديل الجلسة أو استبعادها", systemImage: "square.and.pencil") }.accessibilityIdentifier("workout.summary.edit")
                    Button { showingFeedback = true } label: { Label("تقييم الجهد والطاقة", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("workout.summary.feedback")
                }
                let sessionRecords = records.filter { $0.sessionID == session.id }
                if !sessionRecords.isEmpty {
                    Section("أرقام شخصية جديدة") {
                        ForEach(sessionRecords) { record in
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(.orange).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(items.first { $0.exerciseID == record.exerciseID }?.name ?? "تمرين").font(.headline)
                                    Text(record.kindRaw == "reps" ? "تكرارات عند نفس الوزن" : record.kindRaw == "weight" ? "أعلى وزن" : "أعلى تكرار أقصى تقديري").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(record.kindRaw == "reps" ? ArabicFormat.number(record.value, decimals: 0, arabic: settings.useArabicDigits) : ArabicFormat.weight(record.value, settings: settings)).font(.subheadline.bold())
                            }
                        }
                    }
                }
                ForEach(items) { item in
                    Section(item.name) {
                        ForEach(sets.filter { $0.sessionExerciseID == item.id && $0.isCompleted }.sorted { $0.order < $1.order }) { set in
                            HStack {
                                Text(SetKindLabels.name(set.kindRaw)).foregroundStyle(.secondary)
                                Spacer()
                                SetPerformanceLabel(set: set)
                            }
                        }
                        if !item.notes.isEmpty { Text(item.notes).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if !session.notes.isEmpty { Section("ملاحظات الجلسة") { Text(session.notes) } }
                Section {
                    if let deletionError { Text(deletionError).foregroundStyle(.red).accessibilityIdentifier("workout.summary.deleteError") }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("حذف الجلسة", systemImage: "trash").frame(minHeight: 44)
                    }.disabled(coordinator.isBusy).accessibilityIdentifier("workout.summary.delete")
                } footer: {
                    Text("حذف الجلسة يزيل جولاتها من تاريخك وحسابات تقدمك.")
                }
            }
            .wateeraCanvas()
            .navigationTitle("ملخص التمرين").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingEdit) { SessionEditorView(session: session) }
            .sheet(isPresented: $showingFeedback) { SessionFeedbackView(sessionID: session.id) }
            .sheet(item: $sharedAchievement) { AchievementShareSheet(achievement: $0).presentationDetents([.medium, .large]) }
            .arabicError($shareError)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() }.bold().accessibilityIdentifier("workout.summary.done") } }
            .alert("حذف الجلسة؟", isPresented: $confirmingDelete) {
                Button("حذف الجلسة", role: .destructive) {
                    let id = session.id
                    Task {
                        if await coordinator.deleteSession(id: id, context: context) { dismiss() }
                        else {
                            deletionError = coordinator.errorMessage ?? "تعذر حذف الجلسة. أعد المحاولة."
                            // A sheet must show its own error instead of relying on an alert behind it.
                            coordinator.errorMessage = nil
                        }
                    }
                }.accessibilityIdentifier("workout.delete.confirm")
                Button("تراجع", role: .cancel) {}
            } message: { Text(SessionDeletionCopy.message(healthExported: session.healthExported)) }
        }
    }
    private func shareAchievement() {
        let count = records.filter { $0.sessionID == session.id }.count
        let card = AchievementCard(title: session.title, date: ArabicFormat.date(session.start),
                                   duration: ArabicFormat.duration(session.activeDuration(), arabic: settings.useArabicDigits),
                                   volume: ArabicFormat.weight(WorkoutMath.volume(sets: completed.filter { $0.kindRaw != "warmup" }), settings: settings),
                                   sets: ArabicFormat.integer(completed.count, arabic: settings.useArabicDigits),
                                   records: count > 0 ? ArabicFormat.integer(count, arabic: settings.useArabicDigits) : "")
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .large))
        renderer.scale = 2
        guard let image = renderer.uiImage else { shareError = "تعذر تجهيز بطاقة الإنجاز. حاول مرة أخرى."; return }
        sharedAchievement = SharedAchievement(image: image)
    }
}

private enum SessionDeletionCopy {
    static func message(healthExported: Bool) -> String {
        let message = "ستُحذف الجلسة وكل جولاتها، وتُحدّث الأرقام الشخصية والاقتراحات من الجلسات المتبقية. لا يمكن التراجع عن الحذف."
        return healthExported ? message + " سبق تصدير هذه الجلسة إلى تطبيق الصحة؛ احذف نسختها من هناك أيضًا." : message
    }
}

@MainActor private struct WorkoutCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var mode: Int
    @State private var targetWeight: Double = 60
    @State private var barWeight: Double = 20
    @State private var increment: Double = 2.5
    @State private var enabledPlates: Set<Double> = [25, 20, 15, 10, 5, 2.5, 1.25]
    let initialWeightKg: Double
    let onApply: (([WarmupSet]) -> Void)?

    init(initialMode: Int = 0, initialWeightKg: Double = 60, onApply: (([WarmupSet]) -> Void)? = nil) {
        _mode = State(initialValue: initialMode)
        self.initialWeightKg = initialWeightKg
        self.onApply = onApply
    }

    private var denominations: [Double] { settings.weightUnit == "lb" ? [45, 35, 25, 10, 5, 2.5] : [25, 20, 15, 10, 5, 2.5, 1.25] }
    private var plateResult: PlateResult { PlateCalculator.calculate(targetWeight: targetWeight, barWeight: barWeight, availablePlates: Array(enabledPlates)) }
    private var warmups: [WarmupSet] { WarmupCalculator.calculate(workingWeight: targetWeight, barWeight: barWeight, increment: increment) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("الحاسبة", selection: $mode) { Text("الأقراص").tag(0); Text("الإحماء").tag(1) }.pickerStyle(.segmented)
                }
                Section("الأوزان بالـ\(settings.weightLabel)") {
                    calculatorField("وزن التمرين المستهدف", value: $targetWeight, identifier: "calculator.target")
                    calculatorField("وزن البار", value: $barWeight, identifier: "calculator.bar")
                }
                if mode == 0 {
                    let calculation = plateResult
                    Section("الأقراص المتاحة (أزواج)") {
                        ForEach(denominations, id: \.self) { plate in
                            Toggle("\(ArabicFormat.number(plate, decimals: 2, arabic: settings.useArabicDigits)) \(settings.weightLabel)", isOn: Binding(get: { enabledPlates.contains(plate) }, set: { if $0 { enabledPlates.insert(plate) } else { enabledPlates.remove(plate) } }))
                        }
                    }
                    Section("ضع على كل جانب من البار") {
                        if targetWeight < barWeight { Text("الوزن المستهدف أقل من وزن البار. اختر بارًا أخف.").foregroundStyle(.orange) }
                        else if calculation.platesPerSide.isEmpty { Text("البار فقط") }
                        else {
                            ForEach(Array(calculation.platesPerSide.enumerated()), id: \.offset) { index, plate in
                                Label("قرص \(ArabicFormat.integer(index + 1, arabic: settings.useArabicDigits)): \(ArabicFormat.number(plate, decimals: 2, arabic: settings.useArabicDigits)) \(settings.weightLabel)", systemImage: "circle.circle.fill")
                            }
                        }
                        LabeledContent("الوزن الإجمالي", value: "\(ArabicFormat.number(calculation.achievedWeight, decimals: 2, arabic: settings.useArabicDigits)) \(settings.weightLabel)")
                        if !calculation.isExact && targetWeight >= barWeight {
                            Text("ينقص \(ArabicFormat.number(calculation.remainder, decimals: 2, arabic: settings.useArabicDigits)) \(settings.weightLabel) للوصول إلى الوزن المطلوب.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("الإعداد") { calculatorField("خطوة زيادة الوزن", value: $increment, identifier: "calculator.increment") }
                    Section {
                        if warmups.isEmpty { Text("ارفع الوزن المستهدف عن وزن البار، وأدخل خطوة زيادة أكبر من صفر.").foregroundStyle(.secondary) }
                        ForEach(warmups) { set in
                            HStack {
                                Text("الجولة \(ArabicFormat.integer(set.id + 1, arabic: settings.useArabicDigits))")
                                Spacer()
                                Text("\(ArabicFormat.number(set.weight, decimals: 2, arabic: settings.useArabicDigits)) \(settings.weightLabel) × \(ArabicFormat.integer(set.reps, arabic: settings.useArabicDigits))").bold()
                            }
                        }
                        if let onApply, !warmups.isEmpty {
                            Button { onApply(warmups); dismiss() } label: { Label("إضافة الإحماء إلى التمرين", systemImage: "plus.circle.fill") }
                        }
                    } header: { Text("جولات الإحماء المقترحة") } footer: { Text("هذه نقطة بداية قابلة للتعديل. لا يُحتسب الإحماء في الأرقام الشخصية.") }
                }
            }
            .wateeraCanvas()
            .navigationTitle("حاسبات التمرين").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
            .onAppear {
                targetWeight = settings.displayWeight(initialWeightKg)
                barWeight = settings.weightUnit == "lb" ? 45 : 20
                increment = settings.weightUnit == "lb" ? 5 : 2.5
                enabledPlates = Set(denominations)
            }
        }
    }
    private func calculatorField(_ title: String, value: Binding<Double>, identifier: String) -> some View {
        HStack {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            GymNumberField(value: value, decimals: 2, maximum: 2_000, label: title, identifier: identifier).frame(maxWidth: 120)
        }
    }
}
