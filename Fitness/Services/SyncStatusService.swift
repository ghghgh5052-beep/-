import CloudKit
import CoreData
import Foundation
import Observation

@Observable
@MainActor
final class SyncStatusService {
    enum State {
        case localOnly, checkingAccount, unavailable, waiting, syncing, error
    }

    private(set) var state: State = .localOnly
    private(set) var lastImport: Date?
    private(set) var lastExport: Date?
    private(set) var errorMessage: String?
    var onImportCompleted: (() -> Void)?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var activeEvents = Set<UUID>()
    @ObservationIgnored private var cloudEnabled = false

    var statusText: String {
        switch state {
        case .localOnly: return "البيانات محفوظة على هذا الجهاز"
        case .checkingAccount: return "جارٍ التحقق من آي كلاود"
        case .unavailable: return "آي كلاود غير متاح؛ بياناتك محفوظة محليًا"
        case .waiting: return "آي كلاود متاح؛ في انتظار أحداث المزامنة"
        case .syncing: return "جارٍ مزامنة البيانات مع آي كلاود"
        case .error: return errorMessage ?? "تعذرت المزامنة؛ بياناتك محفوظة محليًا"
        }
    }

    init() {
        lastImport = UserDefaults.standard.object(forKey: "lastCloudImport") as? Date
        lastExport = UserDefaults.standard.object(forKey: "lastCloudExport") as? Date
        observer = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                                          object: nil, queue: .main) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor [weak self] in self?.receive(event) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func configure(isCloudEnabled: Bool) {
        cloudEnabled = isCloudEnabled
        if !isCloudEnabled {
            activeEvents.removeAll()
            state = .localOnly
            errorMessage = nil
            return
        }
        Task { await refreshAccount() }
    }

    func refreshAccount() async {
        guard cloudEnabled else { state = .localOnly; return }
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerIdentifier") as? String,
              SigningCapabilities.current.allowsCloudKit(container: identifier) else {
            state = .unavailable
            errorMessage = "لم يتم إعداد حاوية آي كلاود في التطبيق."
            return
        }
        state = .checkingAccount
        do {
            let accountStatus = try await CKContainer(identifier: identifier).accountStatus()
            guard cloudEnabled else { state = .localOnly; return }
            if accountStatus == .available {
                state = activeEvents.isEmpty ? .waiting : .syncing
                errorMessage = nil
            } else {
                state = .unavailable
                errorMessage = "سجّل الدخول إلى آي كلاود من إعدادات الجهاز لتفعيل المزامنة."
            }
        } catch {
            guard cloudEnabled else { return }
            state = .unavailable
            errorMessage = "تعذر التحقق من آي كلاود. ستبقى البيانات محفوظة على الجهاز."
        }
    }

    private func receive(_ event: NSPersistentCloudKitContainer.Event) {
        guard cloudEnabled else { return }
        guard let endDate = event.endDate else {
            activeEvents.insert(event.identifier)
            state = .syncing
            return
        }
        activeEvents.remove(event.identifier)
        guard event.succeeded else {
            state = .error
            errorMessage = "تعذرت آخر عملية مزامنة. ستُعاد المحاولة تلقائيًا عند توفر آي كلاود."
            return
        }
        switch event.type {
        case .import:
            lastImport = endDate
            UserDefaults.standard.set(endDate, forKey: "lastCloudImport")
            onImportCompleted?()
        case .export:
            lastExport = endDate
            UserDefaults.standard.set(endDate, forKey: "lastCloudExport")
        case .setup: break
        @unknown default: break
        }
        errorMessage = nil
        // A finished event is not proof that every record has reached another device.
        state = activeEvents.isEmpty ? .waiting : .syncing
    }
}
