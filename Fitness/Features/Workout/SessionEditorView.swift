import SwiftUI
import SwiftData

@MainActor struct SessionEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    let session: WorkoutSession
    @State private var title = ""
    @State private var start = Date()
    @State private var duration = 0.0
    @State private var notes = ""
    @State private var excluded = false
    @State private var edits: [SessionSetEdit] = []
    @State private var names: [UUID: String] = [:]
    @State private var errorMessage: String?
    @State private var loaded = false
    var onSaved: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("الجلسة") {
                    TextField("اسم الجلسة", text: $title).accessibilityIdentifier("session.edit.title")
                    DatePicker("التاريخ والبداية", selection: $start, in: ...Date.now)
                    Stepper("المدة: " + ArabicFormat.duration(duration, arabic: settings.useArabicDigits), value: $duration, in: 0...86_400, step: 60)
                    TextField("ملاحظاتك", text: $notes, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    Toggle("جلسة تجريبية، خارج إحصاءات التقدم", isOn: $excluded)
                        .accessibilityIdentifier("session.edit.excluded")
                } footer: {
                    Text("تبقى الجلسة في تاريخك ويمكن احتسابها مجددًا. تستبعد الجلسات التجريبية من الأرقام الشخصية والمقارنات واقتراحات التدريب.")
                }
                ForEach($edits) { $value in
                    Section(names[value.id] ?? "جولة") {
                        if value.modeRaw == "timed" || value.modeRaw == "distance" {
                            number("المدة بالثواني", value: $value.seconds, identifier: "session.edit.seconds")
                            if value.modeRaw == "distance" { number("المسافة بالمتر", value: $value.distanceMeters, identifier: "session.edit.distance") }
                        } else {
                            if value.modeRaw == "assisted" {
                                number("وزن المساعدة (\(settings.weightLabel))", value: Binding(get: { settings.displayWeight(value.assistanceKg) }, set: { value.assistanceKg = settings.kilograms($0) }), identifier: "session.edit.assistance")
                            } else {
                                number("الوزن (\(settings.weightLabel))", value: Binding(get: { settings.displayWeight(value.weightKg) }, set: { value.weightKg = settings.kilograms($0) }), identifier: "session.edit.weight")
                            }
                            Stepper("التكرارات: " + ArabicFormat.integer(value.reps, arabic: settings.useArabicDigits), value: $value.reps, in: 1...10_000)
                        }
                        Text(LoadConvention(rawValue: value.conventionRaw)?.arabicName ?? "الوزن الكلي").font(.caption).foregroundStyle(.secondary)
                        Picker("نوع الجولة", selection: $value.kindRaw) {
                            ForEach(SetKindLabels.values, id: \.self) { Text(SetKindLabels.name($0)).tag($0) }
                        }
                        Toggle("تسجيل الجهد", isOn: Binding(get: { value.rpe != nil }, set: { value.rpe = $0 ? 8 : nil }))
                        if value.rpe != nil {
                            Stepper("الجهد: " + ArabicFormat.number(value.rpe ?? 8, arabic: settings.useArabicDigits), value: Binding(get: { value.rpe ?? 8 }, set: { value.rpe = $0 }), in: 1...10, step: 0.5)
                        }
                    }
                }
                if session.healthExported {
                    Section { Text("هذه الجلسة لها نسخة في تطبيق الصحة. تعديلها أو استبعادها هنا لا يعدّل نسخة الصحة؛ راجعها هناك إن لزم.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("تعديل الجلسة").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("تراجع") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("حفظ", action: save).bold().disabled(!loaded).accessibilityIdentifier("session.edit.save") }
                ToolbarItemGroup(placement: .keyboard) { KeyboardDoneButton() }
            }
            .task { load() }.arabicError($errorMessage)
        }
    }

    private func number(_ label: String, value: Binding<Double>, identifier: String) -> some View {
        HStack {
            Text(label); Spacer(minLength: 12)
            GymNumberField(value: value, decimals: 2, maximum: 1_000_000, label: label, identifier: identifier)
                .frame(maxWidth: 150)
        }
    }
    private func load() {
        guard !loaded else { return }
        title = session.title; start = session.start; duration = session.activeDuration()
        notes = session.notes; excluded = session.statusRaw == "excluded"
        do {
            let items = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.sessionID == session.id }
                .sorted { $0.order < $1.order }
            let sets = try context.fetch(FetchDescriptor<LoggedSet>())
            let measurements = try context.fetch(FetchDescriptor<SetMeasurement>())
            for item in items {
                for set in sets.filter({ $0.sessionExerciseID == item.id }).sorted(by: { $0.order < $1.order }) {
                    let value = measurements.filter { $0.setID == set.id }.max(by: { $0.updatedAt < $1.updatedAt })
                    names[set.id] = item.name + " • " + ArabicFormat.integer(set.order + 1, arabic: settings.useArabicDigits)
                    edits.append(SessionSetEdit(id: set.id, weightKg: set.weightKg, reps: set.reps, rpe: set.rpe,
                        kindRaw: set.kindRaw, seconds: value?.seconds ?? 0, distanceMeters: value?.distanceMeters ?? 0,
                        assistanceKg: value?.assistanceKg ?? 0, modeRaw: value?.modeRaw ?? "reps", conventionRaw: value?.conventionRaw ?? "total"))
                }
            }
            loaded = true
        } catch { errorMessage = "تعذر قراءة الجلسة؛ أعد المحاولة." }
    }
    private func save() {
        do {
            try TrainingEnhancementStore.edit(session: session, title: title, start: start, duration: duration,
                notes: notes, excluded: excluded, edits: edits, context: context)
            WidgetSnapshotService.refresh(context: context, settings: settings)
            onSaved?(); dismiss()
        } catch { errorMessage = TrainingEditError.arabicMessage(for: error) }
    }
}

@MainActor struct SessionFeedbackView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    @State private var difficulty = 0
    @State private var energy = 0
    @State private var fatigue: Set<MuscleRegion> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("كيف كان تمرينك؟") {
                    Picker("صعوبة الجلسة", selection: $difficulty) {
                        Text("لم أحدد").tag(0); Text("سهلة").tag(1); Text("مناسبة").tag(2); Text("صعبة").tag(3)
                    }.accessibilityIdentifier("feedback.difficulty")
                    Picker("طاقتك", selection: $energy) {
                        Text("لم أحدد").tag(0); Text("منخفضة").tag(1); Text("متوسطة").tag(2); Text("مرتفعة").tag(3)
                    }
                }
                Section {
                    ForEach(MuscleRegion.allCases) { muscle in
                        Toggle(muscle.arabicName, isOn: Binding(get: { fatigue.contains(muscle) }, set: { if $0 { fatigue.insert(muscle) } else { fatigue.remove(muscle) } }))
                    }
                } header: { Text("عضلات تشعر فيها بتعب") } footer: {
                    Text("تساعد ملاحظاتك في تخفيف الاقتراحات. تُراعى العضلات المحددة لمدة يومين بعد الجلسة؛ لا تمثل هذه الملاحظات قياسًا طبيًا للتعافي.")
                }
            }.navigationTitle("تقييم الجلسة").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("تراجع") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("حفظ", action: save).accessibilityIdentifier("feedback.save") }
            }.task {
                do {
                    if let value = try context.fetch(FetchDescriptor<SessionFeedback>()).filter({ $0.sessionID == sessionID }).max(by: { $0.updatedAt < $1.updatedAt }) {
                        difficulty = value.difficulty; energy = value.energy
                        fatigue = Set(value.fatigueRaw.split(separator: ",").compactMap { MuscleRegion(rawValue: String($0)) })
                    }
                } catch { errorMessage = "تعذر قراءة تقييمك." }
            }.arabicError($errorMessage)
        }
    }
    private func save() {
        do {
            try TrainingEnhancementStore.transaction(context: context) {
                let records = try context.fetch(FetchDescriptor<SessionFeedback>()).filter { $0.sessionID == sessionID }.sorted { $0.updatedAt > $1.updatedAt }
                let value = records.first ?? SessionFeedback(sessionID: sessionID)
                if records.isEmpty { context.insert(value) }
                value.difficulty = difficulty; value.energy = energy
                value.fatigueRaw = fatigue.map(\.rawValue).sorted().joined(separator: ","); value.updatedAt = .now
                for extra in records.dropFirst() { context.delete(extra) }
            }
            dismiss()
        } catch { errorMessage = "تعذر حفظ تقييمك. أعد المحاولة." }
    }
}
