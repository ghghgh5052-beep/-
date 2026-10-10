import SwiftUI
import SwiftData

@MainActor struct ExerciseAdviceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    let exercise: SessionExercise
    @Query private var currentSets: [LoggedSet]
    @State private var proposal: TrainingPrescription?
    @State private var weightText = ""
    @State private var errorMessage: String?

    init(exercise: SessionExercise) {
        self.exercise = exercise
        let id = exercise.id
        _currentSets = Query(filter: #Predicate<LoggedSet> { $0.sessionExerciseID == id }, sort: \LoggedSet.order)
    }

    private var pendingCount: Int { currentSets.filter { !$0.isCompleted && $0.kindRaw == "working" }.count }
    private var externalLoad: Bool { SmartTrainingStore.requiresExternalLoad(exerciseID: exercise.exerciseID) }
    private var chosenWeight: Double? {
        guard let value = ArabicFormat.parse(weightText), value.isFinite, value >= 0 else { return nil }
        let kilograms = settings.kilograms(value)
        return kilograms <= 2_000 ? kilograms : nil
    }
    private var validWeight: Bool {
        if weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return !externalLoad }
        guard let chosenWeight else { return false }
        return !externalLoad || chosenWeight > 0
    }

    var body: some View {
        Form {
            Section {
                if let guide = ExerciseGuides.guide(for: exercise.exerciseID) {
                    HStack(spacing: 14) {
                        ExerciseGuideThumbnail(guide: guide)
                        Text(exercise.name).font(.headline)
                    }
                } else { Text(exercise.name).font(.headline) }
            }
            if let proposal {
                Section("اقتراح مبني على سجلك") {
                    LabeledContent("الجولات المقترحة", value: ArabicFormat.integer(proposal.sets, arabic: settings.useArabicDigits))
                    LabeledContent("التكرارات المقترحة", value: ArabicFormat.integer(proposal.reps, arabic: settings.useArabicDigits))
                    Text(proposal.reason).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("advice.reason")
                }
                Section {
                    NumericField(title: "الوزن (\(settings.weightLabel))", value: $weightText, selectOnFocus: true)
                        .accessibilityIdentifier("advice.weight")
                    if externalLoad && proposal.weightKg == nil {
                        Text("لا توجد بيانات كافية لاقتراح وزن. اختر وزن البداية قبل التطبيق.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !externalLoad && proposal.weightKg == nil {
                        Text("اترك الوزن فارغًا لتمرين وزن الجسم دون حمل إضافي.").font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("راجع الوزن قبل التطبيق") } footer: {
                    Text("يمكنك تعديل الوزن المقترح. سجّل مستوى الجهد في تفاصيل الجولة لتحسين اقتراحات الجلسات القادمة.")
                }
                Section {
                    Button {
                        do {
                            try SmartWorkoutAdjustments.apply(exercise: exercise, reps: proposal.reps,
                                weightKg: chosenWeight ?? (externalLoad ? nil : 0), context: context)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    } label: {
                        Text("تطبيق على الجولات غير المكتملة").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(pendingCount == 0 || !validWeight)
                    .accessibilityIdentifier("advice.apply")
                    Text("الجولات المشمولة: " + ArabicFormat.integer(pendingCount, arabic: settings.useArabicDigits) + ". تبقى الجولات المكتملة والإحماء كما سجلتها.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("تعذر إعداد الاقتراح لهذا التمرين.").foregroundStyle(.secondary)
                    Button("إعادة المحاولة") { load() }.frame(minHeight: 44)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("اقتراح الأوزان والتكرارات").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("تم") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }.accessibilityIdentifier("advice.keyboard.done")
            }
        }
        .task { load() }
        .arabicError($errorMessage)
    }

    private func load() {
        do {
            let snapshot = try SmartTrainingStore.snapshot(context: context)
            guard let entry = snapshot.recoveryExercises.first(where: { $0.id == exercise.exerciseID }), entry.mode == .reps else {
                errorMessage = "هذا التمرين لا يدعم اقتراح الأوزان والتكرارات حاليًا."; return
            }
            let preferences = try SmartTrainingStore.loadPreferences(context: context)
            let result = SmartTrainingEngine.prescription(for: entry, preferences: preferences, history: snapshot.history, now: .now)
            proposal = result
            weightText = result.weightKg.map { ArabicFormat.number(settings.displayWeight($0), decimals: 2, arabic: settings.useArabicDigits) } ?? ""
        } catch { errorMessage = "تعذر قراءة البيانات اللازمة للاقتراح. أعد المحاولة." }
    }
}

enum SmartAdjustmentError: LocalizedError {
    case inactive, invalidValues, noPendingSets
    var errorDescription: String? {
        switch self {
        case .inactive: return "استأنف جلسة التمرين قبل تطبيق الاقتراح."
        case .invalidValues: return "أدخل وزنًا وتكرارات صالحة قبل تطبيق الاقتراح."
        case .noPendingSets: return "لا توجد جولات عمل غير مكتملة لتطبيق الاقتراح عليها."
        }
    }
}

@MainActor enum SmartWorkoutAdjustments {
    static func apply(exercise: SessionExercise, reps: Int, weightKg: Double?, context: ModelContext) throws {
        guard (1...1_000).contains(reps), weightKg.map({ $0.isFinite && (0...2_000).contains($0) }) ?? true else {
            throw SmartAdjustmentError.invalidValues
        }
        if let weightKg, weightKg == 0, SmartTrainingStore.requiresExternalLoad(exerciseID: exercise.exerciseID) {
            throw SmartAdjustmentError.invalidValues
        }
        let sessionID = exercise.sessionID
        guard let session = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })).first,
              session.statusRaw == "active" else { throw SmartAdjustmentError.inactive }
        let exerciseID = exercise.id
        let pending = try context.fetch(FetchDescriptor<LoggedSet>(predicate: #Predicate { $0.sessionExerciseID == exerciseID }))
            .filter { !$0.isCompleted && $0.kindRaw == "working" }
        guard !pending.isEmpty else { throw SmartAdjustmentError.noPendingSets }
        try context.save()
        do {
            for set in pending {
                set.reps = reps
                if let weightKg { set.weightKg = weightKg }
                set.rpe = nil
                set.updatedAt = .now
            }
            exercise.updatedAt = .now; session.updatedAt = .now
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
