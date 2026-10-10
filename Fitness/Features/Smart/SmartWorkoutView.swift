import SwiftUI
import SwiftData

@MainActor struct SmartWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutCoordinator.self) private var coordinator
    @State private var preferences = TrainingPreferences()
    @State private var preview: SmartWorkoutPreview?
    @State private var showingEquipment = false
    @State private var editing: PrescriptionSelection?
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var unsupportedExerciseCount = 0
    @State private var bodyweightExerciseIDs: Set<UUID> = []

    private var configurationKey: String {
        [preferences.goal.rawValue, preferences.level.rawValue,
         String(preferences.durationMinutes), String(preferences.incrementKg),
         preferences.equipment.map(\.rawValue).sorted().joined(separator: ",")].joined(separator: "|")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("تمرين يناسب يومك", systemImage: "sparkles")
                        .font(.title3.bold()).foregroundStyle(settings.color)
                    Text("اختر هدفك ووقتك والأدوات المتاحة. نقترح تمارين وأوزانًا من جلساتك المكتملة، ثم تراجعها قبل البدء.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 6)
            }
            Section {
                Picker("الهدف", selection: $preferences.goal) {
                    ForEach(TrainingGoal.allCases, id: \.self) { Text($0.arabicName).tag($0) }
                }.accessibilityIdentifier("smart.goal")
                Picker("المستوى", selection: $preferences.level) {
                    ForEach(TrainingLevel.allCases, id: \.self) { Text($0.arabicName).tag($0) }
                }.accessibilityIdentifier("smart.level")
                Picker("الوقت المتاح", selection: $preferences.durationMinutes) {
                    ForEach(Array(Set([15, 20, 30, 45, 60, 75, 90, 120, preferences.durationMinutes])).sorted(), id: \.self) {
                        Text(ArabicFormat.integer($0, arabic: settings.useArabicDigits) + " دقيقة").tag($0)
                    }
                }.accessibilityIdentifier("smart.duration")
                Button { showingEquipment = true } label: {
                    HStack(alignment: .top) {
                        Text("الأدوات المتاحة").foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(equipmentSummary).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                        Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tertiary)
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier("smart.equipment")
                Picker("خطوة زيادة الوزن", selection: $preferences.incrementKg) {
                    ForEach(Array(Set([0.25, 0.5, 1, 1.25, 2.5, 5, 10, preferences.incrementKg])).sorted(), id: \.self) {
                        Text(ArabicFormat.weight($0, settings: settings)).tag($0)
                    }
                }.accessibilityIdentifier("smart.increment")
            } header: { Text("تفضيلات التدريب") } footer: {
                Text("اختر الزيادة الفعلية المتاحة لأوزانك. الوقت تقديري ويشمل الإحماء والراحة، وقد يختلف مع سرعة التنفيذ.")
            }
            Section {
                Button(action: generate) {
                    Label(preview == nil ? "اقترح تمريني" : "أعد اقتراح التمرين", systemImage: "sparkles")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent)
                    .disabled(!loaded || preferences.equipment.isEmpty)
                    .accessibilityIdentifier("smart.generate")
                if preferences.equipment.isEmpty {
                    Text("اختر أداة واحدة على الأقل؛ يمكنك الاكتفاء بوزن الجسم.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.listRowBackground(Color.clear)
            if let preview {
                previewContent(preview)
            } else {
                Section {
                    Label("لن تُنشأ جلسة أو تتغير أرقامك عند توليد الاقتراح.", systemImage: "checkmark.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.listRowBackground(Color.clear)
            }
        }
        .navigationTitle("تمرين مقترح")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("إغلاق") { dismiss() } }
        }
        .sheet(isPresented: $showingEquipment) {
            NavigationStack { TrainingEquipmentPicker(selection: $preferences.equipment) }
        }
        .sheet(item: $editing) { selected in
            NavigationStack {
                TrainingPrescriptionEditor(prescription: selected.value) { updated in
                    guard var revised = preview,
                          let index = revised.exercises.firstIndex(where: { $0.exerciseID == updated.exerciseID }) else { return }
                    revised.exercises[index] = updated
                    preview = revised
                }
            }
        }
        .task { load() }
        .onChange(of: configurationKey) { _, _ in preview = nil }
        .arabicError($errorMessage)
    }

    private var equipmentSummary: String {
        let selected = TrainingEquipment.allCases.filter { preferences.equipment.contains($0) }
        if selected.isEmpty { return "لم تُحدد أدوات" }
        if selected.count <= 2 { return selected.map(\.arabicName).joined(separator: "، ") }
        return ArabicFormat.integer(selected.count, arabic: settings.useArabicDigits) + " أدوات"
    }

    @ViewBuilder private func previewContent(_ value: SmartWorkoutPreview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(value.titleArabic).font(.headline).accessibilityIdentifier("smart.preview.title")
                Label("نحو " + ArabicFormat.integer(estimatedMinutes(value), arabic: settings.useArabicDigits) + " دقيقة", systemImage: "clock")
                    .font(.subheadline).foregroundStyle(.secondary)
                if estimatedMinutes(value) > preferences.durationMinutes {
                    Text("التعديلات زادت المدة عن الوقت الذي اخترته. خفّض الجولات أو التكرارات إذا أردت جلسة أقصر.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(Array(value.warnings.enumerated()), id: \.offset) { _, warning in
                Label(warning, systemImage: "info.circle").font(.footnote)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if unsupportedExerciseCount > 0 {
                Text("الاقتراحات تستخدم تمارين المكتبة الأساسية فقط. تبقى تمارينك الخاصة متاحة في المكتبة والتمرين الحر.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: { Text("راجع تمرينك") }
        ForEach(Array(value.exercises.enumerated()), id: \.element.exerciseID) { index, prescription in
            Section {
                prescriptionRow(prescription, number: index + 1)
            }
        }
        Section {
            if value.exercises.isEmpty {
                ContentUnavailableView("لا يوجد اقتراح مناسب", systemImage: "dumbbell",
                    description: Text("غيّر الأدوات أو الوقت المتاح، ثم أعد الاقتراح."))
            }
            if coordinator.activeSessionID != nil {
                Text("لديك تمرين جارٍ. أكمله أو ألغِه قبل بدء التمرين المقترح.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button { start(value) } label: {
                Label("ابدأ هذا التمرين", systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent)
                .disabled(value.exercises.isEmpty || coordinator.activeSessionID != nil || coordinator.isBusy)
                .accessibilityIdentifier("smart.start")
        } footer: {
            Text("الأوزان المقترحة نقطة بداية قابلة للتعديل. اختر وزنًا تستطيع التحكم فيه، ويمكنك تعديل الجولات أثناء التمرين.")
        }.listRowBackground(Color.clear)
    }

    private func prescriptionRow(_ value: TrainingPrescription, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if let guide = ExerciseGuides.guide(for: value.exerciseID) {
                    ExerciseGuideThumbnail(guide: guide)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(value.name).font(.headline)
                    Text("التمرين " + ArabicFormat.integer(number, arabic: settings.useArabicDigits))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { prescriptionNumbers(value) }
                VStack(alignment: .leading, spacing: 7) { prescriptionNumbers(value) }
            }.font(.subheadline)
            Text(value.reason).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { editing = PrescriptionSelection(value: value) } label: {
                Label("تعديل الجولات والأرقام", systemImage: "slider.horizontal.3")
                    .frame(minHeight: 44)
            }.accessibilityIdentifier("smart.edit.\(value.exerciseID.uuidString)")
        }.padding(.vertical, 4)
            .accessibilityIdentifier("smart.preview.exercise.\(value.exerciseID.uuidString)")
    }

    @ViewBuilder private func prescriptionNumbers(_ value: TrainingPrescription) -> some View {
        Text(ArabicFormat.integer(value.sets, arabic: settings.useArabicDigits) + " جولات × "
             + ArabicFormat.integer(value.reps, arabic: settings.useArabicDigits) + " " + repUnit(value))
        if let weight = value.weightKg { Text(ArabicFormat.weight(weight, settings: settings)) }
        else {
            Text(bodyweightExerciseIDs.contains(value.exerciseID) ? "وزن الجسم" : "اختر الوزن عند البدء")
                .foregroundStyle(.secondary)
        }
        Label(ArabicFormat.integer(value.restSeconds, arabic: settings.useArabicDigits) + " ثانية راحة", systemImage: "timer")
    }

    private func repUnit(_ value: TrainingPrescription) -> String {
        value.mode == .hold ? "ثانية" : "تكرارات"
    }

    private func estimatedMinutes(_ value: SmartWorkoutPreview) -> Int {
        guard !value.exercises.isEmpty else { return 0 }
        // Keep the estimate current when the user edits sets, reps or rest before starting.
        let seconds = value.exercises.reduce(300) { total, exercise in
            total + exercise.sets * (exercise.reps * 3 + exercise.restSeconds) + 60
        }
        return Int(ceil(Double(seconds) / 60))
    }

    private func load() {
        guard !loaded else { return }
        do {
            preferences = try SmartTrainingStore.loadPreferences(context: context)
            loaded = true
        } catch {
            loaded = true
            errorMessage = "تعذر قراءة تفضيلات التدريب. يمكنك تعديل التفضيلات وحفظها بإعادة الاقتراح."
        }
    }

    private func generate() {
        do {
            let snapshot = try SmartTrainingStore.snapshot(context: context)
            try SmartTrainingStore.savePreferences(preferences, context: context)
            unsupportedExerciseCount = snapshot.unsupportedExerciseCount
            bodyweightExerciseIDs = Set(snapshot.exercises.filter { $0.requiredEquipment.contains(.bodyweight) }.map(\.id))
            preview = SmartTrainingEngine.generate(exercises: snapshot.exercises,
                preferences: preferences, history: snapshot.history, now: .now,
                recoveryExercises: snapshot.recoveryExercises)
        } catch {
            errorMessage = "تعذر إعداد الاقتراح أو حفظ تفضيلاتك. لم تُنشأ جلسة؛ حاول مرة أخرى."
        }
    }

    private func start(_ value: SmartWorkoutPreview) {
        guard coordinator.activeSessionID == nil, !coordinator.isBusy else { return }
        coordinator.start(preview: value, context: context)
        if let message = coordinator.errorMessage { errorMessage = message }
        else if coordinator.activeSessionID != nil { dismiss() }
    }
}

private struct PrescriptionSelection: Identifiable {
    let value: TrainingPrescription
    var id: UUID { value.exerciseID }
}

@MainActor private struct TrainingEquipmentPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Binding var selection: Set<TrainingEquipment>
    private var groups: [(String, [TrainingEquipment])] {
        let basics: [TrainingEquipment] = [.bodyweight, .barbell, .dumbbell, .bench, .rack, .pullUpBar,
            .dipStation, .band, .medicineBall, .abWheel, .box]
        let cardio: [TrainingEquipment] = [.jumpRope, .treadmill, .bike, .rower]
        return [("الأدوات الأساسية", basics),
                ("الأجهزة", TrainingEquipment.allCases.filter { !basics.contains($0) && !cardio.contains($0) }),
                ("الكارديو", cardio)]
    }

    var body: some View {
        List {
            Section {
                Text("اختر الموجود في مكان تدريبك. المقعد والقفص أدوات مستقلة؛ اخترهما إذا كانا متاحين مع البار أو الدمبل.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("اختيار جميع الأدوات") { selection = Set(TrainingEquipment.allCases) }
                    .frame(minHeight: 44).accessibilityIdentifier("smart.equipment.all")
                Button("وزن الجسم فقط") { selection = [.bodyweight] }
                    .frame(minHeight: 44).accessibilityIdentifier("smart.equipment.bodyweightOnly")
            }
            ForEach(groups, id: \.0) { title, equipment in
                Section(title) {
                    ForEach(equipment, id: \.self) { item in
                        Button {
                            if selection.contains(item) { selection.remove(item) }
                            else { selection.insert(item) }
                        } label: {
                            HStack {
                                Text(item.arabicName).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                Image(systemName: selection.contains(item) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(item) ? settings.color : Color.secondary)
                                    .accessibilityHidden(true)
                            }.frame(minHeight: 44)
                        }.accessibilityValue(selection.contains(item) ? "متاح" : "غير متاح")
                            .accessibilityAddTraits(selection.contains(item) ? [.isSelected] : [])
                            .accessibilityIdentifier("smart.equipment.\(item.rawValue)")
                    }
                }
            }
        }.navigationTitle("الأدوات المتاحة").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
    }
}

@MainActor private struct TrainingPrescriptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    let prescription: TrainingPrescription
    let onSave: (TrainingPrescription) -> Void
    @State private var sets: Int
    @State private var reps: String
    @State private var weight = ""
    @State private var rest: Int
    @State private var errorMessage: String?
    @State private var loadedWeight = false

    init(prescription: TrainingPrescription, onSave: @escaping (TrainingPrescription) -> Void) {
        self.prescription = prescription
        self.onSave = onSave
        _sets = State(initialValue: prescription.sets)
        _reps = State(initialValue: String(prescription.reps))
        _rest = State(initialValue: prescription.restSeconds)
    }

    var body: some View {
        Form {
            Section {
                Stepper("الجولات: " + ArabicFormat.integer(sets, arabic: settings.useArabicDigits), value: $sets, in: 1...10)
                    .accessibilityIdentifier("smart.editor.sets")
                HStack {
                    Text(prescription.mode == .hold ? "المدة بالثواني" : "التكرارات")
                    NumericField(title: prescription.mode == .hold ? "المدة بالثواني" : "التكرارات", value: $reps, selectOnFocus: true)
                        .accessibilityIdentifier("smart.editor.reps")
                }
                HStack {
                    Text("الوزن (" + settings.weightLabel + ")")
                    NumericField(title: "الوزن المقترح", value: $weight, selectOnFocus: true).accessibilityIdentifier("smart.editor.weight")
                }
                Picker("الراحة بين الجولات", selection: $rest) {
                    ForEach(Array(Set([0, 30, 45, 60, 90, 120, 150, 180, 240, 300, rest])).sorted(), id: \.self) {
                        Text(ArabicFormat.integer($0, arabic: settings.useArabicDigits) + " ثانية").tag($0)
                    }
                }
            } header: { Text(prescription.name) } footer: {
                Text("اترك الوزن فارغًا لاختياره أثناء التمرين. هذه التعديلات تخص هذا الاقتراح فقط.")
            }
        }.navigationTitle("تعديل الاقتراح").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }.accessibilityIdentifier("smart.editor.save")
                }
            }
            .onAppear {
                guard !loadedWeight else { return }
                reps = ArabicFormat.integer(prescription.reps, arabic: settings.useArabicDigits)
                if let value = prescription.weightKg {
                    weight = ArabicFormat.number(settings.displayWeight(value), decimals: 2, arabic: settings.useArabicDigits)
                }
                loadedWeight = true
            }
            .arabicError($errorMessage)
    }

    private func save() {
        let maximum = prescription.mode == .reps ? 100 : 3_600
        guard let number = ArabicFormat.parse(reps), number.isFinite,
              number.rounded(.down) == number, (1...Double(maximum)).contains(number) else {
            errorMessage = "أدخل عددًا صحيحًا بين " + ArabicFormat.integer(1, arabic: settings.useArabicDigits)
                + " و" + ArabicFormat.integer(maximum, arabic: settings.useArabicDigits) + "."; return
        }
        let parsedWeight: Double?
        if weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parsedWeight = nil }
        else {
            guard let value = ArabicFormat.parse(weight), value.isFinite,
                  (0...2_000).contains(settings.kilograms(value)) else {
                errorMessage = "أدخل وزنًا صالحًا أو اترك الحقل فارغًا."; return
            }
            if SmartTrainingStore.requiresExternalLoad(exerciseID: prescription.exerciseID), value <= 0 {
                errorMessage = "لهذا التمرين وزن خارجي؛ أدخل وزنًا أكبر من صفر أو اترك الحقل فارغًا لاختياره عند البدء."; return
            }
            parsedWeight = settings.kilograms(value)
        }
        var updated = prescription
        updated.sets = sets
        updated.reps = Int(number)
        updated.weightKg = parsedWeight
        updated.restSeconds = rest
        onSave(updated)
        dismiss()
    }
}
