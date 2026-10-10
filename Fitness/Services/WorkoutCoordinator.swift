import Foundation
import AudioToolbox
import Observation
import SwiftData
import UIKit

@Observable
@MainActor
final class WorkoutCoordinator {
    private(set) var activeSessionID: UUID?
    private(set) var restDeadline: Date?
    var errorMessage: String?
    private(set) var isBusy = false
    private(set) var now = Date()
    let settings: AppSettings
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var restNotificationTask: Task<Void, Never>?

    var restRemaining: Int {
        guard let restDeadline else { return 0 }
        return max(0, Int(ceil(restDeadline.timeIntervalSince(now))))
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    deinit {
        clockTask?.cancel()
        restNotificationTask?.cancel()
    }

    func recover(context: ModelContext) {
        self.context = context
        do {
            let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.statusRaw == "active" || $0.statusRaw == "paused" },
                sortBy: [SortDescriptor(\.start, order: .reverse)]))
            guard let session = sessions.first else {
                activeSessionID = nil
                cancelRest()
                Task { await LiveActivityService.shared.endAll() }
                return
            }
            activeSessionID = session.id
            let defaults = UserDefaults.standard
            if defaults.string(forKey: "restSessionID") == session.id.uuidString,
               session.statusRaw == "active", let persisted = defaults.object(forKey: "restDeadline") as? Date,
               persisted > .now {
                restDeadline = persisted
                restNotificationTask = Task {
                    await NotificationService.shared.scheduleRest(deadline: persisted, requestPermission: false)
                }
            } else {
                cancelRest()
            }
            startClock()
            refreshActivity()
        } catch { errorMessage = "تعذر استعادة التمرين. أعد فتح التطبيق؛ لم تُحذف بياناتك." }
    }

    func start(day: PlanDay?, context: ModelContext) {
        guard !isBusy else { return }
        self.context = context
        var createdSession: WorkoutSession?
        var createdExercises: [SessionExercise] = []
        var createdSets: [LoggedSet] = []
        do {
            let existing = try context.fetch(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.statusRaw == "active" || $0.statusRaw == "paused" }))
            if let session = existing.sorted(by: { $0.start > $1.start }).first {
                activeSessionID = session.id
                startClock()
                refreshActivity()
                errorMessage = "لديك تمرين جارٍ. أكمله أولًا أو تابع من حيث توقفت."
                return
            }
            guard day?.isRest != true else {
                errorMessage = "هذا يوم راحة. يمكنك بدء تمرين حر إذا أردت."
                return
            }
            let session = WorkoutSession(planDayID: day?.id, title: day?.title ?? "تمرين حر")
            createdSession = session
            if let day {
                let dayID = day.id
                let planned = try context.fetch(FetchDescriptor<PlanExercise>(
                    predicate: #Predicate { $0.dayID == dayID }, sortBy: [SortDescriptor(\.order)]))
                let catalog = try context.fetch(FetchDescriptor<Exercise>())
                var catalogByID: [UUID: Exercise] = [:]
                for exercise in catalog { catalogByID[exercise.id] = exercise }
                for item in planned {
                    guard let definition = catalogByID[item.exerciseID] else { continue }
                    let exercise = SessionExercise(sessionID: session.id, exerciseID: definition.id,
                                                   name: definition.name, order: item.order, notes: definition.notes,
                                                   groupID: item.groupID, restSeconds: item.restSeconds)
                    createdExercises.append(exercise)
                    let previous = try previousSets(exerciseID: definition.id, excluding: session.id, context: context)
                    for index in 0..<max(1, item.targetSets) {
                        let prior = previous.indices.contains(index) ? previous[index] : previous.last
                        let set = LoggedSet(sessionExerciseID: exercise.id, order: index,
                                            weightKg: prior?.weightKg ?? 0, reps: item.targetReps)
                        createdSets.append(set)
                    }
                }
            }
            context.insert(session)
            for exercise in createdExercises { context.insert(exercise) }
            for set in createdSets { context.insert(set) }
            try context.save()
            activeSessionID = session.id
            now = .now
            errorMessage = nil
            startClock()
            refreshActivity()
            WidgetSnapshotService.refresh(context: context, settings: settings)
        } catch {
            // A failed start must not leave a half-created active session on the next attempt.
            for set in createdSets where set.modelContext != nil { context.delete(set) }
            for exercise in createdExercises where exercise.modelContext != nil { context.delete(exercise) }
            if let createdSession, createdSession.modelContext != nil { context.delete(createdSession) }
            errorMessage = "تعذر حفظ التمرين الجديد. تحقق من مساحة الجهاز وحاول مرة أخرى."
        }
    }

    func resume(session: WorkoutSession, context: ModelContext) {
        guard session.statusRaw != "completed", !isBusy else { return }
        self.context = context
        if let pausedAt = session.pausedAt {
            session.accumulatedPause += max(0, Date.now.timeIntervalSince(pausedAt))
            appendPauseEvent(to: session, at: .now)
        }
        session.pausedAt = nil
        session.statusRaw = "active"
        session.updatedAt = .now
        guard save(context) else { return }
        activeSessionID = session.id
        startClock()
        refreshActivity()
    }

    func pause(context: ModelContext) {
        guard let session = activeSession(context: context), session.statusRaw == "active" else { return }
        session.pausedAt = .now
        appendPauseEvent(to: session, at: .now)
        session.statusRaw = "paused"
        session.updatedAt = .now
        guard save(context) else { return }
        cancelRest()
        refreshActivity()
    }

    func finish(context: ModelContext) async {
        guard !isBusy, let session = activeSession(context: context) else { return }
        isBusy = true
        defer { isBusy = false }
        let finishedAt = Date.now
        if let pause = session.pausedAt {
            session.accumulatedPause += max(0, finishedAt.timeIntervalSince(pause))
            appendPauseEvent(to: session, at: finishedAt)
        }
        session.pausedAt = nil
        session.end = finishedAt
        session.statusRaw = "completed"
        session.updatedAt = finishedAt
        guard save(context) else { return }
        do { _ = try PRService.rebuild(context: context) }
        catch { errorMessage = "تم حفظ التمرين، وتعذر تحديث سجل الأرقام الشخصية. أعد فتح صفحة التقدم." }
        cancelRest()
        activeSessionID = nil
        clockTask?.cancel()
        clockTask = nil
        await LiveActivityService.shared.endAll()
        WidgetSnapshotService.refresh(context: context, settings: settings)
        HealthService.shared.isEnabled = settings.healthEnabled
        if settings.healthEnabled && !session.healthExported {
            do {
                session.healthExported = try await HealthService.shared.writeCompletedWorkout(session)
                if session.healthExported { _ = save(context) }
                else if let message = HealthService.shared.errorMessage { errorMessage = message }
            } catch { errorMessage = "تم حفظ التمرين؛ تعذرت إضافته إلى صحتي. أعد المحاولة من الإعدادات." }
        }
    }

    func complete(set: LoggedSet, exercise: SessionExercise, context: ModelContext) {
        guard let session = activeSession(context: context), session.statusRaw == "active",
              exercise.sessionID == session.id, set.sessionExerciseID == exercise.id else {
            errorMessage = "استأنف التمرين قبل تسجيل المجموعة."
            return
        }
        guard set.weightKg.isFinite, set.weightKg >= 0, set.reps > 0,
              set.rpe.map({ $0.isFinite && (0...10).contains($0) }) ?? true else {
            errorMessage = "أدخل وزنًا صالحًا وتكرارًا واحدًا على الأقل، وجهدًا بين صفر وعشرة."
            return
        }
        guard !set.isCompleted else { _ = save(context); return }
        set.isCompleted = true
        set.completedAt = .now
        set.updatedAt = .now
        session.updatedAt = .now
        guard save(context) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Supersets rest only after the final movement in the group.
        let shouldRest: Bool
        if exercise.groupID.isEmpty { shouldRest = true }
        else {
            let sessionID = session.id
            do {
                let exercises = try context.fetch(FetchDescriptor<SessionExercise>(predicate: #Predicate { $0.sessionID == sessionID }))
                let group = exercises.filter { $0.groupID == exercise.groupID }.sorted { $0.order < $1.order }
                shouldRest = group.isEmpty || group.last?.id == exercise.id
            } catch {
                shouldRest = true
                errorMessage = "تم حفظ المجموعة؛ تعذر قراءة ترتيب المجموعة المركبة، وبدأت الراحة."
            }
        }
        if shouldRest { startRest(seconds: exercise.restSeconds > 0 ? exercise.restSeconds : settings.defaultRestSeconds) }
        refreshActivity()
    }

    func startRest(seconds: Int) {
        guard let activeSessionID, seconds > 0 else { cancelRest(); return }
        let deadline = Date.now.addingTimeInterval(TimeInterval(seconds))
        now = .now
        restDeadline = deadline
        UserDefaults.standard.set(deadline, forKey: "restDeadline")
        UserDefaults.standard.set(activeSessionID.uuidString, forKey: "restSessionID")
        restNotificationTask?.cancel()
        restNotificationTask = Task {
            await NotificationService.shared.scheduleRest(deadline: deadline)
            if let message = NotificationService.shared.errorMessage { errorMessage = message }
        }
        startClock()
        refreshActivity()
    }

    func cancelRest() {
        restNotificationTask?.cancel()
        restNotificationTask = nil
        restDeadline = nil
        UserDefaults.standard.removeObject(forKey: "restDeadline")
        UserDefaults.standard.removeObject(forKey: "restSessionID")
        NotificationService.shared.cancelRest()
        refreshActivity()
    }

    @discardableResult
    func save(_ context: ModelContext) -> Bool {
        do { try context.save(); errorMessage = nil; return true }
        catch { errorMessage = "تعذر حفظ التغيير. أبقِ التطبيق مفتوحًا وحاول مجددًا."; return false }
    }

    func refreshActivity() {
        guard let context, let session = activeSession(context: context) else { return }
        let sessionID = session.id
        do {
            let exercises = try context.fetch(FetchDescriptor<SessionExercise>(predicate: #Predicate { $0.sessionID == sessionID }))
            var completedSets = 0
            for exercise in exercises {
                let exerciseID = exercise.id
                completedSets += try context.fetchCount(FetchDescriptor<LoggedSet>(predicate: #Predicate {
                    $0.sessionExerciseID == exerciseID && $0.isCompleted
                }))
            }
            LiveActivityService.shared.update(sessionID: session.id, title: session.title, startedAt: session.start,
                                              elapsedSeconds: Int(session.activeDuration()), completedSets: completedSets,
                                              restDeadline: restDeadline, paused: session.statusRaw == "paused",
                                              arabicDigits: settings.useArabicDigits)
            if let message = LiveActivityService.shared.errorMessage { errorMessage = message }
        } catch { errorMessage = "تعذر تحديث النشاط المباشر. تمرينك محفوظ في التطبيق." }
    }

    private func activeSession(context: ModelContext) -> WorkoutSession? {
        guard let id = activeSessionID else { return nil }
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        do { return try context.fetch(descriptor).first }
        catch { errorMessage = "تعذر قراءة التمرين الحالي. حاول مجددًا."; return nil }
    }

    private func previousSets(exerciseID: UUID, excluding sessionID: UUID, context: ModelContext) throws -> [LoggedSet] {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.statusRaw == "completed" },
                                                                        sortBy: [SortDescriptor(\.start, order: .reverse)]))
        let exercises = try context.fetch(FetchDescriptor<SessionExercise>(predicate: #Predicate { $0.exerciseID == exerciseID }))
        for session in sessions where session.id != sessionID {
            if let exercise = exercises.first(where: { $0.sessionID == session.id }) {
                let exerciseID = exercise.id
                return try context.fetch(FetchDescriptor<LoggedSet>(predicate: #Predicate {
                    $0.sessionExerciseID == exerciseID && $0.isCompleted
                }, sortBy: [SortDescriptor(\.order)]))
            }
        }
        return []
    }

    private func appendPauseEvent(to session: WorkoutSession, at date: Date) {
        var events = session.pauseEventsRaw.data(using: .utf8).flatMap { try? JSONDecoder().decode([TimeInterval].self, from: $0) } ?? []
        events.append(date.timeIntervalSince1970)
        if let encoded = try? JSONEncoder().encode(events), let value = String(data: encoded, encoding: .utf8) {
            session.pauseEventsRaw = value
        }
    }

    private func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.now = .now
                if let deadline = self.restDeadline, deadline <= self.now {
                    // Keep the scheduled system notification: removing it here would race delivery.
                    self.restDeadline = nil
                    UserDefaults.standard.removeObject(forKey: "restDeadline")
                    UserDefaults.standard.removeObject(forKey: "restSessionID")
                    if UIApplication.shared.applicationState == .active {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        if !NotificationService.shared.isAuthorized { AudioServicesPlaySystemSound(1007) }
                    }
                    self.refreshActivity()
                }
            }
        }
    }
}
