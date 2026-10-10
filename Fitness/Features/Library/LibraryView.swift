import SwiftUI
import SwiftData

@MainActor struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var muscle = "الكل"
    @State private var equipment = "الكل"
    @State private var favoritesOnly = false
    @State private var showingArchived = false
    @State private var showingEditor = false
    @State private var errorMessage: String?

    private var visibleExercises: [Exercise] {
        exercises.filter {
            $0.isArchived == showingArchived && (!favoritesOnly || $0.isFavorite)
                && (muscle == "الكل" || $0.primaryMuscleRaw == muscle || $0.secondaryMusclesRaw.contains(muscle))
                && (equipment == "الكل" || $0.equipmentRaw == equipment)
                && (search.isEmpty || $0.name.localizedStandardContains(search) || $0.primaryMuscleRaw.localizedStandardContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 10) { filterControls }
                    } else {
                        HStack(spacing: 12) { filterControls }
                    }
                }
                if visibleExercises.isEmpty {
                    EmptyState(title: "لا توجد تمارين مطابقة", message: "غيّر البحث أو أضف تمرينك الخاص إلى المكتبة.", symbol: "magnifyingglass")
                        .listRowSeparator(.hidden)
                } else {
                    Section("مكتبة التمارين") {
                        ForEach(visibleExercises) { exercise in
                            NavigationLink {
                                ExerciseDetailView(exercise: exercise)
                            } label: {
                                ExerciseLibraryRow(exercise: exercise)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    exercise.isFavorite.toggle()
                                    exercise.updatedAt = .now
                                    save()
                                } label: {
                                    Label(exercise.isFavorite ? "إزالة من المفضلة" : "إضافة للمفضلة", systemImage: "star")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("التمارين")
            .searchable(text: $search, prompt: "اسم التمرين أو العضلة")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingEditor = true } label: { Label("إضافة تمرين خاص", systemImage: "plus") }
                        Toggle("التمارين المخفية", isOn: $showingArchived)
                    } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel("إدارة مكتبة التمارين")
                }
            }
            .sheet(isPresented: $showingEditor) { ExerciseEditorView() }
            .onChange(of: showingArchived) { _, _ in muscle = "الكل"; equipment = "الكل"; favoritesOnly = false }
            .alert("تعذّر حفظ التغيير", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("حسنًا", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "أعد المحاولة.") }
        }
    }

    @ViewBuilder private var filterControls: some View {
        filterMenu(title: "العضلة", selection: $muscle, values: Set(exercises.filter { $0.isArchived == showingArchived }.map(\.primaryMuscleRaw)))
        filterMenu(title: "الأداة", selection: $equipment, values: Set(exercises.filter { $0.isArchived == showingArchived }.map(\.equipmentRaw)))
        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        Button { favoritesOnly.toggle() } label: {
            if dynamicTypeSize.isAccessibilitySize { Label("المفضلة فقط", systemImage: favoritesOnly ? "star.fill" : "star").frame(minHeight: 44) }
            else { Image(systemName: favoritesOnly ? "star.fill" : "star").frame(minWidth: 44, minHeight: 44) }
        }.buttonStyle(.borderless)
            .accessibilityLabel(favoritesOnly ? "عرض جميع التمارين" : "عرض التمارين المفضلة")
            .accessibilityAddTraits(favoritesOnly ? [.isSelected] : [])
    }

    private func filterMenu(title: String, selection: Binding<String>, values: Set<String>) -> some View {
        Menu {
            Picker(title, selection: selection) {
                Text("الكل").tag("الكل")
                ForEach(values.filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
            }
        } label: {
            Label(selection.wrappedValue == "الكل" ? title : selection.wrappedValue, systemImage: "line.3.horizontal.decrease")
                .font(.subheadline)
                .lineLimit(1)
                .frame(minHeight: 44)
        }
    }

    private func save() {
        do { try context.save() }
        catch { context.rollback(); errorMessage = "لم يتم حفظ التغيير. حاول مرة أخرى." }
    }
}

@MainActor private struct ExerciseLibraryRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: exercise.kindRaw == "كارديو" ? "figure.run" : "dumbbell.fill")
                .foregroundStyle(.tint)
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name).font(.headline)
                Text([exercise.primaryMuscleRaw, exercise.equipmentRaw].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if exercise.isFavorite {
                Image(systemName: "star.fill").foregroundStyle(.orange).accessibilityLabel("مفضّل")
            }
        }
        .padding(.vertical, 3)
    }
}

@MainActor struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var favoritesOnly = false
    let excludedIDs: Set<UUID>
    let onSelect: (Exercise) -> Void

    init(excludedIDs: Set<UUID> = [], onSelect: @escaping (Exercise) -> Void) {
        self.excludedIDs = excludedIDs
        self.onSelect = onSelect
    }

    private var filtered: [Exercise] {
        exercises.filter {
            !$0.isArchived && !excludedIDs.contains($0.id) && (!favoritesOnly || $0.isFavorite)
                && (search.isEmpty || $0.name.localizedStandardContains(search) || $0.primaryMuscleRaw.localizedStandardContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Toggle("المفضلة فقط", isOn: $favoritesOnly)
                if filtered.isEmpty {
                    EmptyState(title: "لا توجد نتائج", message: "ابحث باسم آخر أو أضف تمرينًا من تبويب التمارين.", symbol: "dumbbell")
                }
                ForEach(filtered) { exercise in
                    Button {
                        onSelect(exercise)
                        dismiss()
                    } label: { ExerciseLibraryRow(exercise: exercise).foregroundStyle(.primary) }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("اختيار تمرين")
            .searchable(text: $search, prompt: "ابحث في المكتبة")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
    }
}

@MainActor private struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var exercise: Exercise
    @State private var showingEditor = false
    @State private var confirmingArchive = false
    @State private var errorMessage: String?

    private var mediaLink: URL? {
        guard let url = URL(string: exercise.mediaURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "dumbbell.fill").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exercise.name).font(.title2.bold())
                        Text(exercise.isCustom ? "تمرين خاص" : "من المكتبة الأساسية").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 14)
                Button {
                    exercise.isFavorite.toggle()
                    save()
                } label: {
                    Label(exercise.isFavorite ? "إزالة من المفضلة" : "إضافة إلى المفضلة", systemImage: exercise.isFavorite ? "star.fill" : "star")
                }
            }
            Section("تفاصيل التمرين") {
                LabeledContent("العضلة الأساسية", value: exercise.primaryMuscleRaw)
                if !exercise.secondaryMusclesRaw.isEmpty {
                    LabeledContent("العضلات المساعدة", value: exercise.secondaryMusclesRaw)
                }
                LabeledContent("الأداة", value: exercise.equipmentRaw)
                LabeledContent("النوع", value: exercise.kindRaw)
            }
            Section("ملاحظاتك") {
                Text(exercise.notes.isEmpty ? "أضف طريقة التنفيذ أو ما تريد تذكّره من زر التعديل." : exercise.notes)
                    .foregroundStyle(exercise.notes.isEmpty ? .secondary : .primary)
            }
            if let mediaLink {
                Section("مرجع التمرين") {
                    Link(destination: mediaLink) { Label("فتح الصورة أو الفيديو", systemImage: "arrow.up.right.square") }
                    Text("يفتح الرابط في المتصفح عند اختيارك له.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                if exercise.isArchived {
                    Button { exercise.isArchived = false; save(); if errorMessage == nil { dismiss() } } label: { Label("استعادة التمرين إلى المكتبة", systemImage: "arrow.uturn.backward") }
                } else {
                    Button("إخفاء التمرين من المكتبة", role: .destructive) { confirmingArchive = true }
                }
            } footer: {
                Text("تبقى سجلات هذا التمرين محفوظة في تاريخك.")
            }
        }
        .navigationTitle("تفاصيل التمرين")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("تعديل") { showingEditor = true } } }
        .sheet(isPresented: $showingEditor) { ExerciseEditorView(exercise: exercise) }
        .confirmationDialog("إخفاء هذا التمرين؟", isPresented: $confirmingArchive, titleVisibility: .visible) {
            Button("إخفاء التمرين", role: .destructive) {
                exercise.isArchived = true
                save()
                if errorMessage == nil { dismiss() }
            }
        } message: { Text("يمكنك استعادته من خيار التمارين المخفية في المكتبة. لن يُحذف تاريخ التمرين.") }
        .alert("تعذّر الحفظ", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("حسنًا", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "أعد المحاولة.") }
    }

    private func save() {
        exercise.updatedAt = .now
        do { try context.save() }
        catch { context.rollback(); errorMessage = "لم يتم حفظ التغيير. حاول مرة أخرى." }
    }
}

@MainActor private struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    let exercise: Exercise?
    @State private var name: String
    @State private var primaryMuscle: String
    @State private var secondaryMuscles: String
    @State private var equipment: String
    @State private var kind: String
    @State private var notes: String
    @State private var mediaURL: String
    @State private var errorMessage: String?

    private let standardMuscles = ["صدر", "ظهر", "أكتاف", "أرجل", "ذراعان", "بطن", "جسم كامل", "قلب وتنفس"]
    private let standardEquipment = ["بار", "دمبل", "جهاز", "كابل", "وزن الجسم", "مطاط", "كرة", "كتل بل", "أخرى"]

    init(exercise: Exercise? = nil) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _primaryMuscle = State(initialValue: exercise?.primaryMuscleRaw ?? "صدر")
        _secondaryMuscles = State(initialValue: exercise?.secondaryMusclesRaw ?? "")
        _equipment = State(initialValue: exercise?.equipmentRaw ?? "دمبل")
        _kind = State(initialValue: exercise?.kindRaw ?? "قوة")
        _notes = State(initialValue: exercise?.notes ?? "")
        _mediaURL = State(initialValue: exercise?.mediaURL ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("اسم التمرين") {
                    TextField("مثل: ضغط الصدر بالدمبل", text: $name)
                        .accessibilityIdentifier("exerciseNameField")
                }
                Section("التصنيف") {
                    Picker("العضلة الأساسية", selection: $primaryMuscle) {
                        ForEach(Array(Set(standardMuscles + allExercises.map(\.primaryMuscleRaw))).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    TextField("العضلات المساعدة (اختياري)", text: $secondaryMuscles)
                    Picker("الأداة", selection: $equipment) {
                        ForEach(Array(Set(standardEquipment + allExercises.map(\.equipmentRaw))).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("النوع", selection: $kind) {
                        ForEach(Array(Set(["قوة", "كارديو", "إطالة", "مهارة"] + allExercises.map(\.kindRaw))).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("ملاحظات التنفيذ") {
                    TextField("الطريقة، وضعية الجسم أو نصائحك", text: $notes, axis: .vertical).lineLimit(3...8)
                }
                Section("رابط صورة أو فيديو (اختياري)") {
                    TextField("https://", text: $mediaURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .navigationTitle(exercise == nil ? "تمرين جديد" : "تعديل التمرين")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ", action: save).bold().disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveExerciseButton")
                }
            }
            .alert("تحقّق من البيانات", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("حسنًا", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "أعد المحاولة.") }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let link = mediaURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !link.isEmpty {
            guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                errorMessage = "أدخل رابطًا صحيحًا يبدأ بـ https:// أو http://."
                return
            }
        }
        let target = exercise ?? Exercise(name: cleanName)
        if exercise == nil { context.insert(target) }
        target.name = cleanName
        target.primaryMuscleRaw = primaryMuscle
        target.secondaryMusclesRaw = secondaryMuscles.trimmingCharacters(in: .whitespacesAndNewlines)
        target.equipmentRaw = equipment
        target.kindRaw = kind
        target.notes = notes
        target.mediaURL = link
        target.isCustom = exercise?.isCustom ?? true
        target.updatedAt = .now
        do {
            try context.save()
            dismiss()
        } catch { context.rollback(); errorMessage = "تعذّر حفظ التمرين. حاول مرة أخرى." }
    }
}
