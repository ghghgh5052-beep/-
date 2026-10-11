import Foundation
import SwiftData

@MainActor enum SessionDeletionService {
    /// Delete every UUID-linked child and rebuild records in the same save.
    /// Fetch all dependencies first; failure must not leave a partial deletion.
    @discardableResult
    static func delete(sessionID: UUID, context: ModelContext,
                       commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> Bool {
        // Keep unrelated visible edits if the deletion later rolls back.
        try context.save()
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        do {
            let sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.id == sessionID }
            guard !sessions.isEmpty else { return false }
            let exercises = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.sessionID == sessionID }
            let ids = Set(exercises.map(\.id))
            let sets = try context.fetch(FetchDescriptor<LoggedSet>()).filter { ids.contains($0.sessionExerciseID) }
            let setIDs = Set(sets.map(\.id))
            for value in try context.fetch(FetchDescriptor<SetMeasurement>()) where setIDs.contains(value.setID) { context.delete(value) }
            for value in try context.fetch(FetchDescriptor<SessionFeedback>()) where value.sessionID == sessionID { context.delete(value) }
            for set in sets { context.delete(set) }
            for exercise in exercises { context.delete(exercise) }
            for session in sessions { context.delete(session) }
            // Explicit exclusion also handles pending-deletion fetches on older iOS releases.
            try PRService.rebuild(context: context, excludingSessionIDs: [sessionID], saveChanges: false)
            try commit(context)
            return true
        } catch {
            context.rollback()
            throw error
        }
    }
}
