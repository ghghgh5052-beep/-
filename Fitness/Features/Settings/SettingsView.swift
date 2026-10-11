import SwiftUI
import SwiftData
import LocalAuthentication

@MainActor struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppLockService.self) private var lock
    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    var body: some View {
        @Bindable var preferences = settings
        NavigationStack {
            Form {
                Section {
                    Label("وتيرة يناسب يومك", systemImage: "slider.horizontal.3").font(.title2.bold()).padding(.vertical, 12)
                }
                Section("العرض") {
                    Picker("شكل الأرقام", selection: $preferences.useArabicDigits) { Text("٠١٢٣ — عربية هندية").tag(true); Text("0123 — غربية").tag(false) }
                    Picker("المظهر", selection: $preferences.theme) { Text("حسب النظام").tag("system"); Text("فاتح").tag("light"); Text("داكن").tag("dark") }
                    Picker("لون الواجهة", selection: $preferences.accent) { Text("نعناعي").tag("mint"); Text("أزرق").tag("blue"); Text("برتقالي").tag("orange"); Text("بنفسجي").tag("purple") }
                }
                Section("الوحدات والتدريب") {
                    Picker("الوزن", selection: $preferences.weightUnit) { Text("كجم").tag("kg"); Text("رطل").tag("lb") }
                    Picker("الطول", selection: $preferences.lengthUnit) { Text("سم").tag("cm"); Text("بوصة").tag("in") }
                    Picker("بداية الأسبوع", selection: $preferences.weekStart) {
                        ForEach([7,1,2,3,4,5,6], id: \.self) { Text(dayName($0)).tag($0) }
                    }
                    Stepper(value: $preferences.defaultRestSeconds, in: 15...600, step: 15) { Text("الراحة الافتراضية: " + ArabicFormat.duration(Double(settings.defaultRestSeconds), arabic: settings.useArabicDigits)) }
                    NavigationLink("التذكيرات", destination: RemindersView())
                }
                Section("الخصوصية") {
                    Toggle("قفل التطبيق", isOn: Binding(get: { settings.lockEnabled }, set: { value in Task { await changeLock(value, photos: false) } }))
                    Toggle("قفل صور التقدم", isOn: Binding(get: { settings.photoLockEnabled }, set: { value in Task { await changeLock(value, photos: true) } }))
                    Text("يستخدم القفل بصمة الوجه أو رمز قفل الجهاز. تُضبط إعدادات القفل لكل جهاز.").font(.caption).foregroundStyle(.secondary)
                }
                Section("على جهازك") {
                    Label("البيانات محفوظة على هذا الجهاز", systemImage: "internaldrive")
                        .accessibilityIdentifier("settings.sync.status")
                    Text("تمارينك وقياساتك وصورك متاحة دون اتصال. احتفظ بنسخة احتياطية من قسم بياناتك.").font(.caption).foregroundStyle(.secondary)
                    Toggle("إبقاء الشاشة مضاءة أثناء التمرين", isOn: $keepScreenAwake)
                }
                Section("بياناتك") { NavigationLink("تصدير واستيراد ونسخ احتياطي", destination: BackupView()) }
                Section("عن وتيرة") {
                    Text("مخطط تمرينك، وسجل تقدمك.")
                    NavigationLink { AboutView() } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("الملكية والحقوق", systemImage: "checkmark.seal")
                            Text(AppBranding.ownerName).font(.subheadline).foregroundStyle(.secondary)
                                .environment(\.layoutDirection, .leftToRight)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("settings.about")
                    Text("الإصدار " + ArabicFormat.digits(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0", arabic: settings.useArabicDigits)).font(.caption)
                }
            }.wateeraCanvas().navigationTitle("الإعدادات")
                .onChange(of: settings.useArabicDigits) { _, _ in _ = WidgetSnapshotService.refresh(context: context, settings: settings) }
                .onChange(of: settings.weekStart) { _, _ in _ = WidgetSnapshotService.refresh(context: context, settings: settings) }
                .onChange(of: settings.saveError) { _, message in if let message { errorMessage = message } }
                .arabicError($errorMessage)
        }
    }
    private func changeLock(_ enabled: Bool, photos: Bool) async {
        if !photos {
            if await lock.unlock(reason: "أكد هويتك لتغيير إعداد قفل التطبيق") { settings.lockEnabled = enabled }
            else { errorMessage = lock.errorMessage ?? "لم يتغير إعداد القفل." }
            return
        }
        let authentication = LAContext(); authentication.localizedCancelTitle = "إلغاء"
        do {
            guard try await authentication.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "أكد هويتك لتغيير إعداد القفل") else { return }
            if photos { settings.photoLockEnabled = enabled } else { settings.lockEnabled = enabled }
        } catch { errorMessage = "لم يتغير إعداد القفل. تأكد من تفعيل رمز قفل الجهاز." }
    }

}

func dayName(_ weekday: Int) -> String {
    [1:"الأحد",2:"الاثنين",3:"الثلاثاء",4:"الأربعاء",5:"الخميس",6:"الجمعة",7:"السبت"][weekday] ?? "اليوم"
}

@MainActor struct RemindersView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var reminders: [WorkoutReminder]
    @State private var adding = false
    @State private var errorMessage: String?
    var body: some View {
        List {
            if reminders.isEmpty { EmptyState(title: "موعد صغير لنفسك", message: "أضف تذكيرًا للتمرين أو الراحة أو قياس الوزن.", symbol: "bell") }
            ForEach(reminders) { reminder in
                NavigationLink { ReminderEditor(reminder: reminder) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reminderTitle(reminder.kindRaw)).font(.headline)
                        Text(ArabicFormat.duration(Double(reminder.hour * 60 + reminder.minute), arabic: settings.useArabicDigits))
                        Text(reminder.weekdays.map(dayName).joined(separator: "، ")).font(.caption).foregroundStyle(.secondary)
                        Text(reminder.enabled ? "مفعّل" : "متوقف").font(.caption).foregroundStyle(reminder.enabled ? settings.color : .secondary)
                    }
                }
            }.onDelete { offsets in
                for index in offsets where reminders.indices.contains(index) { context.delete(reminders[index]) }
                do { try context.save(); Task { await schedule() } } catch { errorMessage = "تعذر حذف التذكير." }
            }
            Text("التذكيرات محلية. الصوت يعتمد على إعدادات الإشعارات والتركيز في جهازك.").font(.caption).foregroundStyle(.secondary)
        }.wateeraCanvas().navigationTitle("التذكيرات").toolbar { Button("إضافة", systemImage: "plus") { adding = true } }
            .sheet(isPresented: $adding) { NavigationStack { ReminderEditor(reminder: nil) } }
            .arabicError($errorMessage)
    }
    private func schedule() async {
        await NotificationService.shared.reschedule(reminders: reminders, requestPermission: false)
        errorMessage = NotificationService.shared.errorMessage
    }
}

func reminderTitle(_ kind: String) -> String {
    switch kind { case "rest": return "تذكير يوم الراحة"; case "weighIn": return "تذكير قياس الوزن"; default: return "تذكير التمرين" }
}

@MainActor struct ReminderEditor: View {
    let reminder: WorkoutReminder?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "workout"
    @State private var time = Date()
    @State private var days: Set<Int> = [7,2,4]
    @State private var enabled = true
    @State private var errorMessage: String?
    var body: some View {
        Form {
            Picker("التذكير", selection: $kind) { Text("التمرين").tag("workout"); Text("الراحة").tag("rest"); Text("قياس الوزن").tag("weighIn") }
            DatePicker("الوقت", selection: $time, displayedComponents: .hourAndMinute)
            Section("الأيام") {
                ForEach([7,1,2,3,4,5,6], id: \.self) { day in
                    Toggle(dayName(day), isOn: Binding(get: { days.contains(day) }, set: { if $0 { days.insert(day) } else { days.remove(day) } }))
                }
            }
            Toggle("مفعّل", isOn: $enabled)
        }.wateeraCanvas().navigationTitle("إعداد التذكير")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("حفظ") { Task { await save() } } }; ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
            .onAppear {
                guard let reminder else { return }
                kind = reminder.kindRaw; days = Set(reminder.weekdays); enabled = reminder.enabled
                time = Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date()) ?? Date()
            }.arabicError($errorMessage)
    }
    private func save() async {
        guard !days.isEmpty else { errorMessage = "اختر يومًا واحدًا على الأقل."; return }
        let record = reminder ?? WorkoutReminder()
        if reminder == nil { context.insert(record) }
        record.kindRaw = kind; record.hour = Calendar.current.component(.hour, from: time); record.minute = Calendar.current.component(.minute, from: time)
        record.weekdaysRaw = days.sorted().map(String.init).joined(separator: ","); record.enabled = enabled; record.updatedAt = Date()
        do {
            try context.save()
            let all = try context.fetch(FetchDescriptor<WorkoutReminder>())
            await NotificationService.shared.reschedule(reminders: all, requestPermission: true)
            if let message = NotificationService.shared.errorMessage { errorMessage = message } else { dismiss() }
        } catch { errorMessage = "تعذر حفظ التذكير." }
    }
}
