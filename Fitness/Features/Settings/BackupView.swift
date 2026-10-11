import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutCoordinator.self) private var workout
    @State private var exportFile: BackupFile?
    @State private var exportType = UTType.json
    @State private var exporting = false
    @State private var importing = false
    @State private var preview: BackupEnvelope?
    @State private var busy = false
    @State private var status: String?
    @State private var errorMessage: String?
    var body: some View {
        Form {
            exportSection
            importSection
            if busy { SwiftUI.ProgressView("جارٍ معالجة البيانات…") }
            if let status { Section { Label(status, systemImage: "checkmark.circle").foregroundStyle(settings.color) } }
            Section { Text("قد تحتوي النسخة على صور وبيانات شخصية. اختر المكان الذي تريد حفظها فيه. لا تُرسل البيانات إلى أي خادم داخل التطبيق.").font(.caption).foregroundStyle(.secondary) }
        }.wateeraCanvas().navigationTitle("بياناتك ونسخك الاحتياطية")
            .fileExporter(isPresented: $exporting, document: exportFile, contentType: exportType, defaultFilename: exportFilename) { result in
                switch result { case .success: status = "تم حفظ الملف."; case .failure: errorMessage = "تعذر حفظ الملف. اختر موقعًا آخر وحاول مرة أخرى." }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText, .plainText]) { result in
                switch result {
                case .success(let url): read(url)
                case .failure: errorMessage = "تعذر فتح الملف المحدد."
                }
            }.arabicError($errorMessage)
    }
    private var exportFilename: String {
        exportType == .json ? "وتيرة-نسخة-كاملة" : "وتيرة-جلسات-وقياسات"
    }
    private var exportSection: some View {
        Section("تصدير بياناتك") {
            Button("نسخة كاملة بصيغة جيسون") { export(csv: false) }
            Button("الجلسات والقياسات كجدول سي إس في") { export(csv: true) }
            Text("النسخة الكاملة تشمل الخطط والمكتبة والجلسات والقياسات والصور والأهداف والتذكيرات والتفضيلات. يمكن حفظها أو مشاركتها من تطبيق الملفات.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var importSection: some View {
        Section("استعادة أو دمج") {
            Button("اختيار ملف جيسون أو سي إس في") { importing = true }
            Text("تُدمج البيانات حسب المعرّف وتاريخ التعديل. تُحفظ السجلات الأحدث، وتبقى سجلاتك الأخرى. يُفضّل إكمال الجلسة النشطة قبل الاستيراد.")
                .font(.caption).foregroundStyle(.secondary)
            if let preview {
                Text(previewSummary(preview))
                Button("دمج الملف المحدد") { restore(preview) }
                    .disabled(busy || workout.activeSessionID != nil)
                Button("إلغاء الاختيار", role: .cancel) { self.preview = nil }
            }
        }
    }
    private func previewSummary(_ backup: BackupEnvelope) -> String {
        let sessions = ArabicFormat.integer(backup.sessions.count, arabic: settings.useArabicDigits)
        let metrics = ArabicFormat.integer(backup.metrics.count, arabic: settings.useArabicDigits)
        let photos = ArabicFormat.integer(backup.photos.count, arabic: settings.useArabicDigits)
        return "الملف يحتوي على \(sessions) جلسة، و\(metrics) قياس، و\(photos) صورة."
    }
    private func export(csv: Bool) {
        busy = true; defer { busy = false }
        do { exportFile = BackupFile(data: try csv ? CSVService.encode(context: context) : BackupService.encode(context: context)); exportType = csv ? .commaSeparatedText : .json; exporting = true }
        catch { errorMessage = "تعذر إنشاء النسخة. حاول مرة أخرى." }
    }
    private func read(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 512 * 1024 * 1024 else { throw BackupError.tooLarge }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            preview = try url.pathExtension.lowercased() == "json" ? BackupService.decode(data) : CSVService.decode(data)
            status = nil
        } catch let error as BackupError { errorMessage = error.errorDescription }
        catch { errorMessage = "تعذر قراءة الملف. تأكد من أنه صادر من وتيرة." }
    }
    private func restore(_ backup: BackupEnvelope) {
        guard workout.activeSessionID == nil else { errorMessage = "أكمل الجلسة النشطة أولًا لحماية تعديلاتك."; return }
        busy = true; defer { busy = false }
        do {
            try BackupService.merge(backup, context: context)
            try PersistenceController.reconcile(context: context)
            try PRService.rebuild(context: context)
            settings.reload()
            workout.recover(context: context)
            _ = WidgetSnapshotService.refresh(context: context, settings: settings)
            Task { if let reminders = try? context.fetch(FetchDescriptor<WorkoutReminder>()) { await NotificationService.shared.reschedule(reminders: reminders, requestPermission: false) } }
            preview = nil; status = "تم دمج البيانات وحفظها."
        } catch let error as BackupError { errorMessage = error.errorDescription }
        catch { errorMessage = "تعذر دمج النسخة. لم تُحذف بياناتك السابقة." }
    }
}
