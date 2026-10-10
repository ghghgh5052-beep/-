import Foundation
import SwiftData

/// A single RFC 4180 table contains the exercise catalog, sessions, movements, sets, and body metrics.
/// Text cells use reversible apostrophe escaping, explicitly marked in each exported row.
@MainActor
enum CSVService {
    private enum Field: String, CaseIterable, Hashable {
        case type = "نوع السجل", id = "المعرّف", encoding = "ترميز النص", updated = "آخر تعديل"
        case name = "الاسم", muscle = "العضلة الأساسية", secondary = "العضلات المساعدة"
        case equipment = "المعدات", exerciseKind = "نوع التمرين", notes = "ملاحظات", media = "رابط الوسائط"
        case favorite = "مفضّل", custom = "مخصص", archived = "مؤرشف", planDay = "يوم الخطة"
        case start = "بداية الجلسة", end = "نهاية الجلسة", paused = "وقت التوقف"
        case pauseDuration = "مجموع التوقف بالثواني", pauseEvents = "أحداث التوقف", status = "حالة الجلسة"
        case healthExported = "مصدّر إلى الصحة", session = "الجلسة", exercise = "التمرين"
        case order = "الترتيب", group = "المجموعة المشتركة", rest = "مدة الراحة بالثواني"
        case movement = "حركة الجلسة", weight = "الوزن بالكجم", reps = "التكرارات"
        case rpe = "الجهد المدرك", setKind = "نوع المجموعة", completed = "مكتملة"
        case completedAt = "وقت إكمال المجموعة", date = "تاريخ القياس", fat = "نسبة الدهون"
        case chest = "محيط الصدر بالسم", waist = "محيط الخصر بالسم", arm = "محيط الذراع بالسم"
        case hips = "محيط الأرداف بالسم", thigh = "محيط الفخذ بالسم"
    }
    private static let textEncoding = "اقتباس-١"
    private static let maximumSize = 512 * 1024 * 1024
    private static let preciseDates: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let legacyDates = ISO8601DateFormatter()

    static func encode(context: ModelContext) throws -> Data {
        try context.save()
        var result = "\u{FEFF}" + Field.allCases.map { quote($0.rawValue) }.joined(separator: ",") + "\r\n"
        var byteCount = result.utf8.count
        func append(_ values: [Field: String]) throws {
            var row = values
            row[.encoding] = textEncoding
            let line = Field.allCases.map { quote(protect(row[$0] ?? "")) }.joined(separator: ",") + "\r\n"
            byteCount += line.utf8.count
            guard byteCount <= maximumSize else { throw BackupError.tooLarge }
            result += line
        }
        for item in try context.fetch(FetchDescriptor<Exercise>()).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            try append([.type: "تمرين", .id: item.id.uuidString, .updated: iso(item.updatedAt),
                        .name: item.name, .muscle: item.primaryMuscleRaw, .secondary: item.secondaryMusclesRaw,
                        .equipment: item.equipmentRaw, .exerciseKind: item.kindRaw, .notes: item.notes,
                        .media: item.mediaURL, .favorite: yes(item.isFavorite), .custom: yes(item.isCustom),
                        .archived: yes(item.isArchived)])
        }
        for item in try context.fetch(FetchDescriptor<WorkoutSession>()).sorted(by: { $0.start < $1.start }) {
            try append([.type: "جلسة", .id: item.id.uuidString, .updated: iso(item.updatedAt),
                        .planDay: item.planDayID?.uuidString ?? "", .name: item.title,
                        .start: iso(item.start), .end: iso(item.end), .paused: iso(item.pausedAt),
                        .pauseDuration: String(item.accumulatedPause), .pauseEvents: item.pauseEventsRaw,
                        .notes: item.notes, .status: sessionLabel(item.statusRaw), .healthExported: yes(item.healthExported)])
        }
        for item in try context.fetch(FetchDescriptor<SessionExercise>()).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            try append([.type: "حركة", .id: item.id.uuidString, .updated: iso(item.updatedAt),
                        .session: item.sessionID.uuidString, .exercise: item.exerciseID.uuidString,
                        .name: item.name, .order: String(item.order), .notes: item.notes,
                        .group: item.groupID, .rest: String(item.restSeconds)])
        }
        for item in try context.fetch(FetchDescriptor<LoggedSet>()).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            try append([.type: "مجموعة", .id: item.id.uuidString, .updated: iso(item.updatedAt),
                        .movement: item.sessionExerciseID.uuidString, .order: String(item.order),
                        .weight: String(item.weightKg), .reps: String(item.reps), .rpe: string(item.rpe),
                        .setKind: setLabel(item.kindRaw), .completed: yes(item.isCompleted),
                        .completedAt: iso(item.completedAt)])
        }
        for item in try context.fetch(FetchDescriptor<BodyMetric>()).sorted(by: { $0.date < $1.date }) {
            try append([.type: "قياس", .id: item.id.uuidString, .updated: iso(item.updatedAt), .date: iso(item.date),
                        .weight: string(item.weightKg), .fat: string(item.fatPercent), .chest: string(item.chestCm),
                        .waist: string(item.waistCm), .arm: string(item.armCm), .hips: string(item.hipsCm),
                        .thigh: string(item.thighCm)])
        }
        return Data(result.utf8)
    }

    static func decode(_ data: Data) throws -> BackupEnvelope {
        guard data.count <= maximumSize else { throw BackupError.tooLarge }
        let rows = try parse(data)
        guard let header = rows.first, header.contains(Field.type.rawValue), header.contains(Field.id.rawValue),
              Set(header).count == header.count else { throw BackupError.invalidFormat }
        let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })
        var envelope = BackupEnvelope(exercises: [], plans: [], days: [], planExercises: [], sessions: [],
                                      sessionExercises: [], sets: [], metrics: [], photos: [], goals: [],
                                      reminders: [], preferences: [], records: [])
        for cells in rows.dropFirst() where !cells.allSatisfy(\.isEmpty) {
            guard cells.count == header.count else { throw BackupError.invalidFormat }
            let encoded = indexes[Field.encoding.rawValue].map { cells[$0] == textEncoding } ?? false
            func value(_ field: Field) -> String {
                guard let index = indexes[field.rawValue] else { return "" }
                let text = cells[index]
                return encoded && text.hasPrefix("'") ? String(text.dropFirst()) : text
            }
            func uuid(_ field: Field) throws -> UUID {
                guard let id = UUID(uuidString: value(field)) else { throw BackupError.invalidValues }
                return id
            }
            func optionalUUID(_ field: Field) throws -> UUID? { value(field).isEmpty ? nil : try uuid(field) }
            func optionalDate(_ field: Field) throws -> Date? {
                let text = value(field)
                guard !text.isEmpty else { return nil }
                guard let date = Self.date(text) else { throw BackupError.invalidValues }
                return date
            }
            func requiredDate(_ field: Field, fallback: Date? = nil) throws -> Date {
                if let parsed = try optionalDate(field) { return parsed }
                if let fallback { return fallback }
                throw BackupError.invalidValues
            }
            func number(_ field: Field, fallback: Double? = nil) throws -> Double? {
                let text = value(field)
                guard !text.isEmpty else { return fallback }
                guard let result = Double(westernDigits(text)), result.isFinite else { throw BackupError.invalidValues }
                return result
            }
            func integer(_ field: Field, fallback: Int) throws -> Int {
                let text = value(field)
                guard !text.isEmpty else { return fallback }
                guard let result = Int(westernDigits(text)) else { throw BackupError.invalidValues }
                return result
            }
            func boolean(_ field: Field, fallback: Bool = false) throws -> Bool {
                switch value(field) {
                case "": return fallback
                case "نعم", "1", "١", "true": return true
                case "لا", "0", "٠", "false": return false
                default: throw BackupError.invalidValues
                }
            }
            let id = try uuid(.id)
            let updated = try requiredDate(.updated, fallback: Date(timeIntervalSince1970: 0))
            switch value(.type) {
            case "تمرين":
                envelope.exercises.append(ExerciseRecord(Exercise(id: id, name: value(.name),
                    primaryMuscleRaw: value(.muscle), secondaryMusclesRaw: value(.secondary),
                    equipmentRaw: value(.equipment), kindRaw: value(.exerciseKind).isEmpty ? "قوة" : value(.exerciseKind),
                    notes: value(.notes), mediaURL: value(.media), isFavorite: try boolean(.favorite),
                    isCustom: try boolean(.custom), isArchived: try boolean(.archived), updatedAt: updated)))
            case "جلسة":
                let status = try sessionRaw(value(.status).isEmpty ? "جارٍ" : value(.status))
                envelope.sessions.append(WorkoutSessionRecord(WorkoutSession(id: id, planDayID: try optionalUUID(.planDay),
                    title: value(.name), start: try requiredDate(.start), end: try optionalDate(.end),
                    pausedAt: try optionalDate(.paused), accumulatedPause: try number(.pauseDuration, fallback: 0) ?? 0,
                    pauseEventsRaw: value(.pauseEvents), notes: value(.notes), statusRaw: status,
                    healthExported: try boolean(.healthExported), updatedAt: updated)))
            case "حركة":
                let order = try integer(.order, fallback: 0), rest = try integer(.rest, fallback: 90)
                guard order >= 0, (0...3600).contains(rest) else { throw BackupError.invalidValues }
                envelope.sessionExercises.append(SessionExerciseRecord(SessionExercise(id: id,
                    sessionID: try uuid(.session), exerciseID: try uuid(.exercise), name: value(.name), order: order,
                    notes: value(.notes), groupID: value(.group), restSeconds: rest, updatedAt: updated)))
            case "مجموعة":
                let order = try integer(.order, fallback: 0)
                guard order >= 0 else { throw BackupError.invalidValues }
                envelope.sets.append(LoggedSetRecord(LoggedSet(id: id, sessionExerciseID: try uuid(.movement),
                    order: order, weightKg: try number(.weight, fallback: 0) ?? 0, reps: try integer(.reps, fallback: 10),
                    rpe: try number(.rpe), kindRaw: try setRaw(value(.setKind).isEmpty ? "أساسية" : value(.setKind)),
                    isCompleted: try boolean(.completed), completedAt: try optionalDate(.completedAt), updatedAt: updated)))
            case "قياس":
                envelope.metrics.append(BodyMetricRecord(BodyMetric(id: id, date: try requiredDate(.date),
                    weightKg: try number(.weight), fatPercent: try number(.fat), chestCm: try number(.chest),
                    waistCm: try number(.waist), armCm: try number(.arm), hipsCm: try number(.hips),
                    thighCm: try number(.thigh), updatedAt: updated)))
            default: throw BackupError.invalidFormat
            }
            guard envelope.totalCount < 2_000_000 else { throw BackupError.tooLarge }
        }
        try BackupService.validate(envelope)
        return envelope
    }

    /// Byte parsing retains UTF-8 and embedded CR/LF exactly, without building a Character array.
    private static func parse(_ data: Data) throws -> [[String]] {
        var cursor = data.startIndex
        if data.count >= 3, data.prefix(3) == Data([0xEF, 0xBB, 0xBF]) { cursor += 3 }
        var rows: [[String]] = [], row: [String] = [], cell = Data()
        var quoted = false, closedQuote = false, cellStarted = false
        func finishCell() throws {
            guard let value = String(data: cell, encoding: .utf8) else { throw BackupError.invalidFormat }
            row.append(value); cell.removeAll(keepingCapacity: true); closedQuote = false; cellStarted = false
        }
        while cursor < data.endIndex {
            let byte = data[cursor]
            if quoted {
                if byte == 0x22 {
                    if cursor + 1 < data.endIndex, data[cursor + 1] == 0x22 { cell.append(0x22); cursor += 1 }
                    else { quoted = false; closedQuote = true }
                } else { cell.append(byte) }
            } else {
                switch byte {
                case 0x22:
                    guard !cellStarted, !closedQuote else { throw BackupError.invalidFormat }
                    quoted = true; cellStarted = true
                case 0x2C:
                    try finishCell()
                case 0x0D, 0x0A:
                    try finishCell(); rows.append(row); row.removeAll(keepingCapacity: true)
                    if byte == 0x0D, cursor + 1 < data.endIndex, data[cursor + 1] == 0x0A { cursor += 1 }
                default:
                    guard !closedQuote else { throw BackupError.invalidFormat }
                    cell.append(byte); cellStarted = true
                }
            }
            cursor += 1
        }
        guard !quoted else { throw BackupError.invalidFormat }
        if cellStarted || closedQuote || !cell.isEmpty || !row.isEmpty { try finishCell(); rows.append(row) }
        return rows
    }

    private static func quote(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    private static func protect(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let dangerous = trimmed.first.map { "=+-@".contains($0) } ?? false
        return text.hasPrefix("'") || text.first == "\t" || text.first == "\r" || text.first == "\n" || dangerous ? "'" + text : text
    }
    private static func yes(_ value: Bool) -> String { value ? "نعم" : "لا" }
    private static func string(_ value: Double?) -> String { value.map { String($0) } ?? "" }
    private static func iso(_ value: Date?) -> String {
        guard let value else { return "" }
        return preciseDates.string(from: value)
    }
    private static func date(_ text: String) -> Date? {
        preciseDates.date(from: text) ?? legacyDates.date(from: text)
    }
    private static func westernDigits(_ text: String) -> String {
        String(text.map { character in
            if let number = character.wholeNumberValue, (0...9).contains(number),
               let result = String(number).first { return result }
            return character == "٫" ? "." : character
        })
    }
    private static func sessionLabel(_ raw: String) -> String {
        switch raw { case "active": return "جارٍ"; case "paused": return "متوقف"; case "completed": return "مكتمل"; default: return raw }
    }
    private static func sessionRaw(_ label: String) throws -> String {
        switch label { case "جارٍ", "active": return "active"; case "متوقف", "paused": return "paused"; case "مكتمل", "completed": return "completed"; default: throw BackupError.invalidValues }
    }
    private static func setLabel(_ raw: String) -> String {
        switch raw { case "warmup": return "إحماء"; case "working": return "أساسية"; case "drop": return "إسقاط"; case "failure": return "فشل"; default: return raw }
    }
    private static func setRaw(_ label: String) throws -> String {
        switch label { case "إحماء", "warmup": return "warmup"; case "أساسية", "working": return "working"; case "إسقاط", "drop": return "drop"; case "فشل", "failure": return "failure"; default: throw BackupError.invalidValues }
    }
}
