import SwiftUI
import SwiftData

@MainActor struct TrainingOptionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    let exerciseID: UUID
    let name: String
    var sessionExerciseID: UUID? = nil
    @State private var avoid = false
    @State private var mode = SetTrackingMode.reps
    @State private var convention = LoadConvention.total
    @State private var programEnabled = false
    @State private var lower = 8
    @State private var upper = 12
    @State private var targetSets = 3
    @State private var increment = 2.5
    @State private var weeks = 8
    @State private var programStart = Date()
    @State private var errorMessage: String?
    @State private var loaded = false
    private var supportsAdvice: Bool { SmartExerciseMetadata.forBuiltInID(exerciseID)?.mode == .reps && mode.supportsWeightRecords }

    var body: some View {
        NavigationStack {
            Form {
                Section(name) {
                    Toggle("تجنب هذا التمرين في الاقتراحات", isOn: $avoid)
                    Picker("طريقة التسجيل", selection: $mode) {
                        ForEach(SetTrackingMode.allCases, id: \.self) { Text($0.arabicName).tag($0) }
                    }.accessibilityIdentifier("training.mode")
                    if mode == .reps || mode == .bodyweight {
                        Picker("معنى الوزن والتكرارات", selection: $convention) {
                            ForEach(LoadConvention.allCases, id: \.self) { Text($0.arabicName).tag($0) }
                        }
                    }
                    Text("يُطبّق نوع التسجيل على الجولات الجديدة وغير المكتملة فقط. يبقى السجل السابق بمعناه الأصلي.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if supportsAdvice {
                    Section {
                        Toggle("برنامج تدرّج لهذا التمرين", isOn: $programEnabled).accessibilityIdentifier("training.program.enabled")
                        if programEnabled {
                            Stepper("الحد الأدنى: " + ArabicFormat.integer(lower, arabic: settings.useArabicDigits), value: $lower, in: 1...upper)
                            Stepper("الحد الأعلى: " + ArabicFormat.integer(upper, arabic: settings.useArabicDigits), value: $upper, in: lower...100)
                            Stepper("جولات العمل: " + ArabicFormat.integer(targetSets, arabic: settings.useArabicDigits), value: $targetSets, in: 1...20)
                            Picker("زيادة الوزن", selection: $increment) {
                                ForEach([0.25, 0.5, 1, 1.25, 2.5, 5, 10], id: \.self) { Text(ArabicFormat.weight($0, settings: settings)).tag($0) }
                            }
                            Stepper("الأسابيع: " + ArabicFormat.integer(weeks, arabic: settings.useArabicDigits), value: $weeks, in: 1...52)
                            DatePicker("بداية البرنامج", selection: $programStart, displayedComponents: .date)
                            let elapsed = max(0, Calendar.current.dateComponents([.day], from: programStart, to: Date.now).day ?? 0)
                            Text("الأسبوع " + ArabicFormat.integer(min(weeks, elapsed / 7 + 1), arabic: settings.useArabicDigits)
                                + " من " + ArabicFormat.integer(weeks, arabic: settings.useArabicDigits)).font(.subheadline)
                            Text("زد التكرارات ضمن النطاق أولًا. تُقترح زيادة الوزن بعد وصول جميع جولات العمل إلى الحد الأعلى بجهد مسجل مناسب؛ لا يغيّر البرنامج الأوزان دون اختيارك.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: { Text("تدرّج منظّم") }
                }
            }.navigationTitle("تفضيلات التمرين").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("تراجع") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("حفظ", action: save).disabled(!loaded).accessibilityIdentifier("training.options.save") }
            }.task { load() }.arabicError($errorMessage)
        }
    }
    private func load() {
        guard !loaded else { return }
        mode = TrainingEnhancementStore.defaultMode(exerciseID: exerciseID)
        if SmartExerciseMetadata.forBuiltInID(exerciseID)?.requiredEquipment.contains(.dumbbell) == true { convention = .perHand }
        do {
            if let value = try context.fetch(FetchDescriptor<ExercisePreference>()).filter({ $0.exerciseID == exerciseID }).max(by: { $0.updatedAt < $1.updatedAt }) {
                avoid = value.avoid; mode = SetTrackingMode(rawValue: value.modeRaw) ?? .reps
                convention = LoadConvention(rawValue: value.conventionRaw) ?? .total
            }
            if let program = try context.fetch(FetchDescriptor<ProgressionProgram>()).filter({ $0.exerciseID == exerciseID }).max(by: { $0.updatedAt < $1.updatedAt }) {
                programEnabled = program.enabled; lower = program.lowerReps; upper = program.upperReps
                targetSets = program.targetSets; increment = program.incrementKg; weeks = program.weeks; programStart = program.start
            }
            loaded = true
        } catch { errorMessage = "تعذر قراءة تفضيلات التمرين." }
    }
    private func save() {
        do {
            try TrainingEnhancementStore.transaction(context: context) {
                let preferences = try context.fetch(FetchDescriptor<ExercisePreference>()).filter { $0.exerciseID == exerciseID }.sorted { $0.updatedAt > $1.updatedAt }
                let value = preferences.first ?? ExercisePreference(exerciseID: exerciseID)
                if preferences.isEmpty { context.insert(value) }
                value.avoid = avoid; value.modeRaw = mode.rawValue; value.conventionRaw = convention.rawValue; value.updatedAt = .now
                for extra in preferences.dropFirst() { context.delete(extra) }
                let programs = try context.fetch(FetchDescriptor<ProgressionProgram>()).filter { $0.exerciseID == exerciseID }.sorted { $0.updatedAt > $1.updatedAt }
                if supportsAdvice || !programs.isEmpty {
                    let program = programs.first ?? ProgressionProgram(exerciseID: exerciseID)
                    if programs.isEmpty { context.insert(program) }
                    program.enabled = supportsAdvice && programEnabled; program.lowerReps = lower; program.upperReps = upper
                    program.targetSets = targetSets; program.incrementKg = increment; program.weeks = weeks
                    program.start = programStart; program.updatedAt = .now
                    for extra in programs.dropFirst() { context.delete(extra) }
                }
                if let sessionExerciseID {
                    let sets = try context.fetch(FetchDescriptor<LoggedSet>()).filter { $0.sessionExerciseID == sessionExerciseID && !$0.isCompleted }
                    for set in sets {
                        let measurement = try TrainingEnhancementStore.measurement(set: set, exerciseID: exerciseID, context: context)
                        measurement.modeRaw = mode.rawValue; measurement.conventionRaw = convention.rawValue; measurement.updatedAt = .now
                        if mode == .timed || mode == .distance { set.weightKg = 0; set.reps = 0 }
                        else { set.reps = max(1, set.reps); if mode == .assisted { set.weightKg = 0 } }
                        set.updatedAt = .now
                    }
                }
            }
            dismiss()
        } catch { errorMessage = "تعذر حفظ تفضيلاتك؛ أعد المحاولة." }
    }
}

@MainActor struct ExerciseAlternativesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutCoordinator.self) private var coordinator
    let item: SessionExercise
    @AppStorage("trainingPlace") private var placeKey = TrainingPlace.gym.rawValue
    @State private var alternatives: [TrainingExercise] = []
    @State private var definitions: [UUID: Exercise] = [:]
    @State private var errorMessage: String?
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("بدائل لـ " + item.name).font(.headline)
                    Text("نفس نمط الحركة وعضلات أساسية مشتركة، بحسب أدوات " + (TrainingPlace(rawValue: placeKey)?.arabicName ?? "النادي") + ". تبقى أرقام كل تمرين مستقلة.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if loaded && alternatives.isEmpty {
                    EmptyState(title: "لا يوجد بديل مطابق", message: "راجع أدوات المكان في التمرين المقترح، أو أضف تمرينًا تختاره من المكتبة.", symbol: "arrow.triangle.swap")
                }
                ForEach(alternatives) { candidate in
                    Button {
                        guard let definition = definitions[candidate.id] else { return }
                        do {
                            try TrainingEnhancementStore.replace(item: item, with: definition, context: context)
                            coordinator.refreshActivity(); dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    } label: {
                        HStack(spacing: 12) {
                            if let guide = ExerciseGuides.guide(for: candidate.id) { ExerciseGuideThumbnail(guide: guide) }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(candidate.name).font(.headline).foregroundStyle(.primary)
                                Text(candidate.requiredEquipment.map(\.arabicName).sorted().joined(separator: "، ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(minHeight: 64)
                    }.accessibilityIdentifier("alternatives.\(candidate.id.uuidString)")
                }
            }.navigationTitle("استبدال التمرين").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            .task {
                do {
                    let snapshot = try SmartTrainingStore.snapshot(context: context)
                    let preferences = try SmartTrainingStore.loadPreferences(context: context, key: placeKey)
                    let avoided = Set(try context.fetch(FetchDescriptor<ExercisePreference>()).filter(\.avoid).map(\.exerciseID))
                    definitions = Dictionary(try context.fetch(FetchDescriptor<Exercise>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    if let source = snapshot.recoveryExercises.first(where: { $0.id == item.exerciseID }) {
                        let availableDefinitions = snapshot.recoveryExercises.filter { definitions[$0.id]?.isArchived == false }
                        alternatives = ExerciseAlternativesEngine.alternatives(to: source, candidates: availableDefinitions, available: preferences.equipment, avoided: avoided)
                    }
                    loaded = true
                } catch { errorMessage = "تعذر إعداد بدائل التمرين." }
            }.arabicError($errorMessage)
        }
    }
}
