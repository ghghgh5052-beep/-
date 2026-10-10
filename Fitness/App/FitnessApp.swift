import SwiftUI
import SwiftData
import Observation

@MainActor @Observable final class AppRuntime {
    static var isTesting: Bool {
        if ProcessInfo.processInfo.arguments.contains("-startup-smoke-test") { return false }
        return ProcessInfo.processInfo.arguments.contains("-ui-testing") ||
            ProcessInfo.processInfo.environment["FITNESS_TESTING"] == "1" ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    var container: ModelContainer?
    var warning: String?
    var errorMessage: String?
    var cloudEnabled = false
    func load() {
        do {
            let testing = Self.isTesting
            let requested = !testing && (Bundle.main.object(forInfoDictionaryKey: "CloudSyncEnabled") as? Bool ?? true)
            let result = try PersistenceController.makeContainer(useCloudKit: requested, inMemory: testing,
                cloudKitContainerIdentifier: Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String)
            container = result.container
            warning = result.warning
            cloudEnabled = result.syncMode == .cloudKit
            errorMessage = nil
        } catch { errorMessage = "تعذر فتح قاعدة بياناتك. أغلق التطبيق وحاول مرة أخرى. لن تُحذف بياناتك أو يُستبدَل ملفها." }
    }
}

@main @MainActor struct FitnessApp: App {
    @State private var runtime = AppRuntime()
    @State private var settings: AppSettings
    @State private var coordinator: WorkoutCoordinator
    @State private var sync = SyncStatusService()
    @State private var lock = AppLockService()
    init() {
        let preferences = AppSettings()
        _settings = State(initialValue: preferences)
        _coordinator = State(initialValue: WorkoutCoordinator(settings: preferences))
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if let container = runtime.container {
                    RootView(warning: runtime.warning, cloudEnabled: runtime.cloudEnabled)
                        .modelContainer(container)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 54)).foregroundStyle(settings.color)
                        if let error = runtime.errorMessage { Text(error).multilineTextAlignment(.center); Button("إعادة المحاولة") { runtime.load() } }
                        else { SwiftUI.ProgressView("جارٍ تجهيز وتيرة…") }
                    }.padding(32).task { if runtime.container == nil && runtime.errorMessage == nil { runtime.load() } }
                }
            }.environment(settings).environment(coordinator).environment(sync).environment(lock)
                .environment(\.locale, Locale(identifier: settings.useArabicDigits ? "ar_SA" : "ar_SA@numbers=latn"))
                .environment(\.calendar, Calendar(identifier: .gregorian))
                .environment(\.layoutDirection, .rightToLeft)
                .tint(settings.color).preferredColorScheme(settings.colorScheme)
        }
    }
}

@MainActor struct RootView: View {
    let warning: String?
    let cloudEnabled: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutCoordinator.self) private var workout
    @Environment(SyncStatusService.self) private var sync
    @Environment(AppLockService.self) private var lock
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var tab = 0
    @State private var warningDismissed = false
    @State private var startupError: String?
    private var protected: Bool { settings.lockEnabled && !lock.isUnlocked }
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let warning, !warningDismissed {
                    HStack(spacing: 8) {
                        Text(warning).font(.caption).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("startup.warning")
                        Button { warningDismissed = true } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }.accessibilityLabel("إخفاء التنبيه")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4).background(.orange.opacity(0.15))
                }
                TabView(selection: $tab) {
                    WorkoutView().tabItem { Label("التمرين", systemImage: "dumbbell.fill") }.tag(0)
                    PlansView().tabItem { Label("خططي", systemImage: "calendar") }.tag(1)
                    LibraryView().tabItem { Label("المكتبة", systemImage: "square.grid.2x2") }.tag(2)
                    ProgressDashboardView().tabItem { Label("تقدّمي", systemImage: "chart.xyaxis.line") }.tag(3)
                    SettingsView().tabItem { Label("الإعدادات", systemImage: "gearshape") }.tag(4)
                }.onChange(of: workout.activeSessionID) { _, id in if id != nil { tab = 0 } }
            }.disabled(protected).accessibilityHidden(protected)
            if protected {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield").font(.system(size: 52)).foregroundStyle(settings.color)
                    Text("وتيرة مقفل").font(.title2.bold())
                    Button("فتح التطبيق") { Task { if await lock.unlock() { consumeShortcut() } } }.buttonStyle(.borderedProminent).disabled(lock.isAuthenticating)
                    if let error = lock.errorMessage { Text(error).font(.caption).multilineTextAlignment(.center) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(uiColor: .systemBackground)).task { _ = await lock.unlock() }
            }
            if scenePhase != .active && (settings.lockEnabled || settings.photoLockEnabled) {
                Color(uiColor: .systemBackground).overlay { Image(systemName: "dumbbell.fill").font(.largeTitle).foregroundStyle(settings.color) }.ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !AppRuntime.isTesting && !onboardingComplete && !protected }, set: { if !$0 { onboardingComplete = true } })) { OnboardingView { onboardingComplete = true } }
        .task {
            do {
                if AppRuntime.isTesting { UserDefaults.standard.removeObject(forKey: "fitness.catalog.seeded.v1") }
                try SeedCatalog.seedIfNeeded(context: context)
                try PersistenceController.reconcile(context: context)
                try PRService.rebuild(context: context)
                settings.bind(context: context)
                workout.recover(context: context)
                sync.configure(isCloudEnabled: cloudEnabled)
                sync.onImportCompleted = {
                    do {
                        try PersistenceController.reconcile(context: context)
                        settings.reload(); workout.recover(context: context)
                        _ = WidgetSnapshotService.refresh(context: context, settings: settings)
                        Task { if let reminders = try? context.fetch(FetchDescriptor<WorkoutReminder>()) { await NotificationService.shared.reschedule(reminders: reminders, requestPermission: false) } }
                    }
                    catch { startupError = "تعذر دمج بعض بيانات المزامنة. يمكنك إعادة فتح التطبيق للمحاولة." }
                }
                if AppRuntime.isTesting {
                    onboardingComplete = true; settings.lockEnabled = false; settings.photoLockEnabled = false
                    if let theme = ProcessInfo.processInfo.environment["FITNESS_TEST_THEME"] { settings.theme = theme }
                    if ProcessInfo.processInfo.environment["FITNESS_TEST_DIGITS"] == "western" { settings.useArabicDigits = false }
                }
                _ = WidgetSnapshotService.refresh(context: context, settings: settings)
                Task { if let reminders = try? context.fetch(FetchDescriptor<WorkoutReminder>()) { await NotificationService.shared.reschedule(reminders: reminders, requestPermission: false) } }
                consumeShortcut()
            } catch { startupError = "تعذر تجهيز المكتبة أو حفظ البيانات. أعد فتح التطبيق للمحاولة." }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startTodayWorkoutRequested)) { _ in consumeShortcut() }
        .onReceive(NotificationCenter.default.publisher(for: .openActiveWorkout)) { _ in tab = 0 }
        .onOpenURL { url in
            guard url.scheme == "wateera" else { return }
            tab = url.host == "progress" ? 3 : 0
        }
        .onChange(of: lock.isUnlocked) { _, unlocked in if unlocked { consumeShortcut() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.sceneDidEnterBackground(enabled: settings.lockEnabled); do { try context.save(); _ = WidgetSnapshotService.refresh(context: context, settings: settings) } catch { startupError = "تعذر حفظ آخر تعديل." } }
            if phase == .active { _ = WidgetSnapshotService.refresh(context: context, settings: settings); consumeShortcut() }
        }
        .arabicError($startupError)
    }
    private func consumeShortcut() {
        guard !protected, SharedWorkoutStorage.consumeStartToday() else { return }
        do {
            let plans = try context.fetch(FetchDescriptor<WorkoutPlan>()).filter { $0.isActive && !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }
            let allDays = try context.fetch(FetchDescriptor<PlanDay>())
            var calendar = Calendar(identifier: .gregorian); calendar.firstWeekday = settings.weekStart
            let today = Date(); let weekday = calendar.component(.weekday, from: today)
            let plan = plans.first
            let week = plan.map { WidgetSnapshotService.programWeek(plan: $0, date: today, calendar: calendar) } ?? 1
            if let plan, calendar.startOfDay(for: today) < calendar.startOfDay(for: plan.programStart) { tab = 0; startupError = "لم يبدأ البرنامج بعد. يمكنك بدء تمرين حر."; return }
            let day = allDays.first { $0.planID == plan?.id && $0.weekday == weekday && $0.week == week && !$0.isRest }
            if let rest = allDays.first(where: { $0.planID == plan?.id && $0.weekday == weekday && $0.week == week }), rest.isRest { tab = 0; startupError = "اليوم يوم راحة في خطتك. يمكنك بدء تمرين حر."; return }
            workout.start(day: day, context: context); tab = 0
        } catch { startupError = "تعذر بدء تمرين اليوم." }
    }
}

@MainActor struct OnboardingView: View {
    let finish: () -> Void
    @Environment(AppSettings.self) private var settings
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Image(systemName: "dumbbell.fill").font(.system(size: 64)).foregroundStyle(settings.color)
            Text("مساحتك للتمرّن\nوالتقدّم").font(.largeTitle.bold())
            Text("وتيرة يساعدك على التخطيط وتسجيل مجموعاتك ومتابعة ما يتحسن، خطوة بخطوة.").font(.title3).foregroundStyle(.secondary)
            Label("ابدأ بقالب وعدّله على راحتك", systemImage: "calendar")
            Label("كل مجموعة تُحفظ أثناء تمرينك", systemImage: "checkmark.shield")
            Label("بياناتك على جهازك وآي كلاود الخاص بك", systemImage: "lock")
            Spacer()
            Button("لنبدأ") { finish() }.font(.headline).frame(maxWidth: .infinity).padding().background(settings.color, in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(.white)
                .accessibilityIdentifier("onboarding.finish")
        }.padding(28).environment(\.layoutDirection, .rightToLeft).interactiveDismissDisabled()
    }
}
