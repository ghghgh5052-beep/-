import Foundation

enum TrainingGoal: String, CaseIterable, Codable, Hashable, Sendable {
    case strength, hypertrophy, fitness
    var arabicName: String {
        switch self {
        case .strength: return "زيادة القوة"
        case .hypertrophy: return "بناء العضلات"
        case .fitness: return "اللياقة العامة"
        }
    }
    var repetitionRange: ClosedRange<Int> {
        switch self {
        case .strength: return 4...6
        case .hypertrophy: return 8...12
        case .fitness: return 10...15
        }
    }
}

enum TrainingLevel: String, CaseIterable, Codable, Hashable, Sendable {
    case beginner, intermediate, advanced
    var arabicName: String {
        switch self {
        case .beginner: return "مبتدئ"
        case .intermediate: return "متوسط"
        case .advanced: return "متقدم"
        }
    }
    var rank: Int {
        switch self {
        case .beginner: return 0
        case .intermediate: return 1
        case .advanced: return 2
        }
    }
}

enum TrainingEquipment: String, CaseIterable, Codable, Hashable, Sendable {
    case bodyweight, barbell, dumbbell, bench, rack, pullUpBar, dipStation, cable
    case chestPress, pecDeck, legPress, hackSquat, legExtension, legCurl, calfRaise
    case seatedCalf, preacherCurl, tricepsMachine, abWheel, band, medicineBall
    case jumpRope, treadmill, bike, rower, rowMachine, backExtension, shoulderPress
    case hipAbduction, hipAdduction, box, latPulldown, seatedCableRow

    var arabicName: String {
        switch self {
        case .bodyweight: return "وزن الجسم"
        case .barbell: return "بار وأقراص"
        case .dumbbell: return "دمبل"
        case .bench: return "مقعد تمرين قابل للميل"
        case .rack: return "حامل بار"
        case .pullUpBar: return "عارضة عقلة"
        case .dipStation: return "متوازي"
        case .cable: return "كابل قابل للضبط مع الملحقات"
        case .chestPress: return "جهاز ضغط الصدر"
        case .pecDeck: return "جهاز تفتيح الصدر"
        case .legPress: return "جهاز ضغط الأرجل"
        case .hackSquat: return "جهاز القرفصاء"
        case .legExtension: return "جهاز تمديد الأرجل"
        case .legCurl: return "جهاز ثني الأرجل"
        case .calfRaise: return "جهاز رفع الكعبين واقفًا"
        case .seatedCalf: return "جهاز رفع الكعبين جالسًا"
        case .preacherCurl: return "جهاز ثني الذراع على المقعد"
        case .tricepsMachine: return "جهاز تمديد الذراع"
        case .abWheel: return "عجلة البطن"
        case .band: return "مطاط مقاومة"
        case .medicineBall: return "كرة تمرين"
        case .jumpRope: return "حبل قفز"
        case .treadmill: return "سير مشي"
        case .bike: return "دراجة ثابتة"
        case .rower: return "جهاز تجديف هوائي"
        case .rowMachine: return "جهاز تجديف مقاومة"
        case .backExtension: return "مقعد تمديد أسفل الظهر"
        case .shoulderPress: return "جهاز ضغط الكتف"
        case .hipAbduction: return "جهاز فتح الوركين"
        case .hipAdduction: return "جهاز ضم الوركين"
        case .box: return "صندوق ثابت للصعود"
        case .latPulldown: return "جهاز سحب علوي بمقعد وتثبيت للفخذين"
        case .seatedCableRow: return "جهاز سحب أرضي بمقعد ومسند للقدمين"
        }
    }
}

enum MuscleRegion: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case chest, back, shoulders, biceps, triceps, forearms, core
    case quadriceps, hamstrings, glutes, calves, adductors
    var id: String { rawValue }
    var arabicName: String {
        switch self {
        case .chest: return "الصدر"
        case .back: return "الظهر"
        case .shoulders: return "الأكتاف"
        case .biceps: return "الذراع الأمامية"
        case .triceps: return "الذراع الخلفية"
        case .forearms: return "الساعدان"
        case .core: return "البطن والجذع"
        case .quadriceps: return "الفخذ الأمامي"
        case .hamstrings: return "الفخذ الخلفي"
        case .glutes: return "الأرداف"
        case .calves: return "السمانة"
        case .adductors: return "الفخذ الداخلي"
        }
    }
}

enum MovementPattern: String, CaseIterable, Codable, Hashable, Sendable {
    case squat, hinge, horizontalPush, verticalPush, horizontalPull, verticalPull, core, isolation
    var arabicName: String {
        switch self {
        case .squat: return "ثني الركبتين"
        case .hinge: return "مد الوركين"
        case .horizontalPush: return "دفع أفقي"
        case .verticalPush: return "دفع علوي"
        case .horizontalPull: return "سحب أفقي"
        case .verticalPull: return "سحب علوي"
        case .core: return "الجذع"
        case .isolation: return "عضلة محددة"
        }
    }
}

enum TrainingMode: String, CaseIterable, Codable, Hashable, Sendable {
    case reps, hold, cardio
    var arabicName: String {
        switch self {
        case .reps: return "تكرارات"
        case .hold: return "ثبات"
        case .cardio: return "لياقة"
        }
    }
}

struct TrainingPreferences: Codable, Equatable, Sendable {
    var goal: TrainingGoal
    var level: TrainingLevel
    var equipment: Set<TrainingEquipment>
    var durationMinutes: Int
    var incrementKg: Double

    init(goal: TrainingGoal = .hypertrophy, level: TrainingLevel = .beginner,
         equipment: Set<TrainingEquipment> = [.bodyweight], durationMinutes: Int = 45,
         incrementKg: Double = 2.5) {
        self.goal = goal; self.level = level; self.equipment = equipment
        self.durationMinutes = durationMinutes; self.incrementKg = incrementKg
    }
}

struct TrainingExercise: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let primaryMuscles: Set<MuscleRegion>
    let secondaryMuscles: Set<MuscleRegion>
    let requiredEquipment: Set<TrainingEquipment>
    let movementPattern: MovementPattern
    let mode: TrainingMode
    let difficulty: TrainingLevel
    let isFavorite: Bool

    init(id: UUID, name: String, primaryMuscles: Set<MuscleRegion>,
         secondaryMuscles: Set<MuscleRegion>, requiredEquipment: Set<TrainingEquipment>,
         movementPattern: MovementPattern, mode: TrainingMode = .reps,
         difficulty: TrainingLevel = .beginner, isFavorite: Bool = false) {
        self.id = id; self.name = name; self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles; self.requiredEquipment = requiredEquipment
        self.movementPattern = movementPattern; self.mode = mode
        self.difficulty = difficulty; self.isFavorite = isFavorite
    }
}

struct TrainingSetHistory: Equatable, Sendable {
    let sessionID: UUID
    let exerciseID: UUID
    let date: Date
    let weightKg: Double
    let reps: Int
    let rpe: Double?
    let kind: String
    let isCompleted: Bool
    let isDifficultSession: Bool

    init(sessionID: UUID, exerciseID: UUID, date: Date, weightKg: Double,
         reps: Int, rpe: Double? = nil, kind: String = "working", isCompleted: Bool = true,
         isDifficultSession: Bool = false) {
        self.sessionID = sessionID; self.exerciseID = exerciseID; self.date = date
        self.weightKg = weightKg; self.reps = reps; self.rpe = rpe
        self.kind = kind; self.isCompleted = isCompleted
        self.isDifficultSession = isDifficultSession
    }

    func isValid(at now: Date) -> Bool {
        isCompleted && date <= now && date.timeIntervalSince1970.isFinite &&
        weightKg.isFinite && weightKg >= 0 && weightKg <= 2_000 && reps > 0 && reps <= 10_000 &&
        ["working", "drop", "failure"].contains(kind) &&
        (rpe == nil || rpe.map { $0.isFinite && (1...10).contains($0) } == true)
    }
}

struct MuscleRecovery: Equatable, Sendable, Identifiable {
    let id: MuscleRegion
    /// A bounded estimate from logged work, never a measured physiological value.
    let readiness: Double?
    let lastTrained: Date?
    let recentSets: Int

    var summaryArabic: String {
        guard let readiness else { return "لا يوجد سجل كافٍ للتقدير" }
        if readiness < 0.45 { return "حمل حديث مرتفع — يُفضّل تخفيف التدريب" }
        if readiness < 0.75 { return "تقدير الاستشفاء متوسط" }
        return "تقدير الاستشفاء مرتفع"
    }
}

struct TrainingPrescription: Equatable, Sendable, Identifiable {
    let exerciseID: UUID
    let name: String
    var sets: Int
    var reps: Int
    var weightKg: Double?
    var restSeconds: Int
    let reason: String
    let mode: TrainingMode
    var id: UUID { exerciseID }
}

struct SmartWorkoutPreview: Equatable, Sendable {
    var exercises: [TrainingPrescription]
    let estimatedMinutes: Int
    let warnings: [String]
    let titleArabic: String
}

enum SmartTrainingEngine {
    /// Linear 72-hour decay is an explicit planning heuristic. Unknown stays unknown.
    static func recoveries(exercises: [TrainingExercise], history: [TrainingSetHistory],
                           now: Date) -> [MuscleRecovery] {
        let definitions = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let valid = history.filter { $0.isValid(at: now) }
        var load: [MuscleRegion: Double] = [:]
        var last: [MuscleRegion: Date] = [:]
        var recent: [MuscleRegion: Int] = [:]
        for set in valid {
            guard let exercise = definitions[set.exerciseID] else { continue }
            let age = max(0, now.timeIntervalSince(set.date))
            let decay = max(0, 1 - age / (72 * 3_600))
            let effort = set.rpe.map { $0 >= 9 ? 1.25 : ($0 <= 6 ? 0.8 : 1) } ?? 1
            let kindFactor = set.kind == "failure" ? 1.25 : (set.kind == "drop" ? 1.15 : 1)
            // Modes lacking duration/effort records contribute less than loaded resistance work.
            let modeFactor = exercise.mode == .reps ? 1.0 : 0.5
            for muscle in exercise.primaryMuscles.union(exercise.secondaryMuscles) {
                last[muscle] = max(last[muscle] ?? set.date, set.date)
                if age <= 7 * 86_400 { recent[muscle, default: 0] += 1 }
                let contribution = exercise.primaryMuscles.contains(muscle) ? 0.1 : 0.04
                load[muscle, default: 0] += contribution * effort * kindFactor * modeFactor * decay
            }
        }
        return MuscleRegion.allCases.map { muscle in
            MuscleRecovery(id: muscle, readiness: last[muscle] == nil ? nil : max(0, min(1, 1 - (load[muscle] ?? 0))),
                           lastTrained: last[muscle], recentSets: recent[muscle] ?? 0)
        }
    }

    static func prescription(for exercise: TrainingExercise, preferences: TrainingPreferences,
                             history: [TrainingSetHistory], now: Date) -> TrainingPrescription {
        let sets = preferences.level == .beginner ? 2 : (preferences.level == .intermediate ? 3 : 4)
        let range = preferences.goal.repetitionRange
        let defaultReps = preferences.goal == .strength ? 5 : (preferences.goal == .hypertrophy ? 10 : 12)
        let rest = preferences.goal == .strength ? 150 : (preferences.goal == .hypertrophy ? 90 : 60)
        func result(weight: Double? = nil, reps: Int = defaultReps, reason: String) -> TrainingPrescription {
            TrainingPrescription(exerciseID: exercise.id, name: exercise.name, sets: sets, reps: reps,
                                 weightKg: weight, restSeconds: rest, reason: reason, mode: exercise.mode)
        }
        guard exercise.mode == .reps else {
            return result(reps: 0, reason: "تمرين يعتمد على المدة؛ حدّد مدته بنفسك ولا يُقترح له وزن أو تكرارات.")
        }
        let sameExercise = history.filter { $0.exerciseID == exercise.id && $0.isValid(at: now) && $0.reps <= 100 }
        let bodyweight = exercise.requiredEquipment.contains(.bodyweight)
        guard !sameExercise.isEmpty else {
            return result(reason: bodyweight ? "ابدأ بتكرارات مريحة بوزن الجسم، وعدّلها حسب قدرتك؛ لا يوجد وزن إضافي مقترح."
                          : "لا توجد جولات عمل سابقة بوزن صالح لهذا التمرين؛ اختر وزن البداية بنفسك.")
        }
        let sessions = Dictionary(grouping: sameExercise, by: \.sessionID)
        let latestSession = sessions.values.sorted {
            let left = $0.map(\.date).max() ?? .distantPast
            let right = $1.map(\.date).max() ?? .distantPast
            if left == right {
                return ($0.first?.sessionID.uuidString ?? "") < ($1.first?.sessionID.uuidString ?? "")
            }
            return left > right
        }.first ?? []
        let latest = latestSession.filter { $0.kind == "working" && $0.weightKg > 0 }
        guard let latestDate = latestSession.map(\.date).max(), let base = latest.map(\.weightKg).min() else {
            return result(reason: bodyweight ? "آخر جلسة لا تتضمن جولات عمل بوزن إضافي؛ راجع تكرارات وزن الجسم حسب قدرتك."
                          : "آخر جلسة لا تتضمن جولات عمل بوزن صالح؛ لا نعتمد جولات الإسقاط أو الفشل وحدها لتحديد وزن جديد.")
        }
        let increment = preferences.incrementKg.isFinite && (0.05...50).contains(preferences.incrementKg)
            ? preferences.incrementKg : 2.5
        let age = now.timeIntervalSince(latestDate)
        let repeated = latest.filter { abs($0.weightKg - base) < 0.0001 }
        let priorReps = min(range.upperBound, max(range.lowerBound, repeated.map(\.reps).min() ?? defaultReps))
        // A break lowers the reference conservatively; never round a reduction upward.
        if age > 21 * 86_400 {
            let reduced = (base * 0.9 / increment).rounded(.down) * increment
            return result(weight: reduced > 0 ? reduced : nil, reps: range.lowerBound,
                          reason: "بعد انقطاع يتجاوز ثلاثة أسابيع، اقتراح أخف من آخر وزن للعمل. راجع قدرتك قبل اعتماده.")
        }
        let adverse = latestSession.contains {
            $0.kind == "failure" || ($0.rpe ?? 0) >= 9 || $0.isDifficultSession
        }
        if adverse {
            return result(weight: base, reps: max(range.lowerBound, priorReps - 1),
                          reason: latestSession.contains(where: \.isDifficultSession)
                            ? "أبلغت عن جلسة صعبة أو طاقة منخفضة؛ نحافظ على الوزن ونخفف التكرارات المقترحة."
                            : "آخر جلسة تضمنت جهدًا مرتفعًا أو وصولًا للفشل؛ نحافظ على الوزن ونخفف التكرارات المقترحة.")
        }
        guard age <= 7 * 86_400 else {
            return result(weight: base, reps: priorReps,
                          reason: "مرّ أكثر من أسبوع على آخر جلسة؛ كرّر الوزن السابق أولًا قبل التفكير في الزيادة.")
        }
        let sufficientlyConsistent = latest.count >= 2 && repeated.count == latest.count
        let comfortable = repeated.allSatisfy { $0.rpe.map { $0 <= 8 } == true }
        if sufficientlyConsistent && comfortable && repeated.allSatisfy({ $0.reps >= range.upperBound }) {
            let increased = ((base + increment) / increment).rounded(.down) * increment
            if increased > base + 0.0001 && increased <= min(2_000, base * 1.05) + 0.0001 {
                return result(weight: increased, reps: range.lowerBound,
                              reason: "أكملت جولتين أو أكثر عند أعلى نطاق التكرارات بجهد مسجل معتدل؛ زيادة صغيرة لا تتجاوز خمسة بالمئة.")
            }
            return result(weight: base, reps: range.upperBound,
                          reason: "ثبّت الوزن؛ الزيادة المتاحة تتجاوز خمسة بالمئة أو حد الوزن المقبول لهذا الاقتراح.")
        }
        if sufficientlyConsistent && comfortable && repeated.allSatisfy({ range.contains($0.reps) }) && priorReps < range.upperBound {
            return result(weight: base, reps: priorReps + 1,
                          reason: "جولات متسقة بجهد معتدل؛ جرّب تكرارًا إضافيًا مع الحفاظ على الوزن.")
        }
        return result(weight: base, reps: priorReps,
                      reason: "اقتراح من جولات العمل الأخيرة لهذا التمرين؛ لا نزيد الوزن دون جولات متسقة وجهد مسجل مناسب.")
    }

    static func generate(exercises: [TrainingExercise], preferences: TrainingPreferences,
                         history: [TrainingSetHistory], now: Date,
                         recoveryExercises: [TrainingExercise]? = nil) -> SmartWorkoutPreview {
        let title = "تمرين مقترح — \(preferences.goal.arabicName)"
        let scope = "الاقتراح الحالي لتمارين المقاومة بالتكرارات؛ يمكنك إضافة تمارين الثبات واللياقة يدويًا. المدة تقديرية وتشمل خمس دقائق للإحماء."
        guard (10...180).contains(preferences.durationMinutes) else {
            return SmartWorkoutPreview(exercises: [], estimatedMinutes: 0,
                                       warnings: ["اختر مدة من عشر دقائق إلى ثلاث ساعات لبناء اقتراح مناسب."], titleArabic: title)
        }
        let available = preferences.equipment.union([.bodyweight])
        let unique = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let eligible = unique.values.filter {
            $0.mode == .reps && !$0.primaryMuscles.isEmpty && !$0.requiredEquipment.isEmpty &&
            $0.difficulty.rank <= preferences.level.rank && $0.requiredEquipment.isSubset(of: available)
        }
        guard !eligible.isEmpty else {
            return SmartWorkoutPreview(exercises: [], estimatedMinutes: 0,
                                       warnings: ["لا توجد تمارين مقاومة مناسبة للمعدات والمستوى المحددين. راجع اختياراتك.", scope], titleArabic: title)
        }
        let recovery = Dictionary(recoveries(exercises: recoveryExercises ?? exercises, history: history, now: now).map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
        let historyByExercise = Dictionary(grouping: history, by: \.exerciseID)
        let familiarIDs = Set(history.filter { $0.isValid(at: now) && $0.kind == "working" }.map(\.exerciseID))
        func readiness(_ exercise: TrainingExercise) -> Double {
            exercise.primaryMuscles.compactMap { recovery[$0]?.readiness }.min() ?? 0.75
        }
        // Very recent heavy work is not a reason to train the same area again.
        var candidates = eligible.filter { readiness($0) >= 0.45 }
        var warnings = [scope]
        if candidates.count < eligible.count {
            warnings.append("استُبعدت بعض التمارين بسبب حمل مسجل مرتفع مؤخرًا؛ تقدير الاستشفاء لا يقيس حالتك الفعلية.")
        }
        guard !candidates.isEmpty else {
            return SmartWorkoutPreview(exercises: [], estimatedMinutes: 0,
                                       warnings: warnings + ["الحمل الحديث مرتفع على المناطق المتاحة؛ جرّب الراحة أو تمرينًا خفيفًا تختاره بنفسك."], titleArabic: title)
        }
        var selected: [TrainingPrescription] = []
        var usedPatterns: Set<MovementPattern> = []
        var usedPrimary: Set<MuscleRegion> = []
        var seconds = 5 * 60
        let budget = preferences.durationMinutes * 60
        func score(_ exercise: TrainingExercise) -> Double {
            let diversity = usedPatterns.contains(exercise.movementPattern) ? 0.0 : 8.0
            let freshMuscles = exercise.primaryMuscles.subtracting(usedPrimary).isEmpty ? 0.0 : 6.0
            let compound = exercise.movementPattern == .isolation || exercise.movementPattern == .core ? 0.0 : 3.0
            return readiness(exercise) * 10 + diversity + freshMuscles + compound +
                (exercise.isFavorite ? 1 : 0) + (familiarIDs.contains(exercise.id) ? 0.5 : 0)
        }
        while !candidates.isEmpty && selected.count < 8 {
            candidates.sort {
                let left = score($0), right = score($1)
                return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
            }
            let exercise = candidates.removeFirst()
            let proposed = prescription(for: exercise, preferences: preferences,
                                        history: historyByExercise[exercise.id] ?? [], now: now)
            // Include a rest period after every set and one minute for transitions.
            let cost = proposed.sets * (proposed.reps * 3 + proposed.restSeconds) + 60
            guard seconds + cost <= budget else { continue }
            selected.append(proposed); seconds += cost
            usedPatterns.insert(exercise.movementPattern); usedPrimary.formUnion(exercise.primaryMuscles)
        }
        if selected.isEmpty {
            return SmartWorkoutPreview(exercises: [], estimatedMinutes: 0,
                                       warnings: warnings + ["الوقت لا يكفي للإحماء والجولات المقترحة؛ زد المدة أو غيّر هدف التدريب."], titleArabic: title)
        }
        if selected.count < 3 {
            warnings.append("المعدات أو الوقت أو الحمل الأخير حدّت من تنوع الجلسة؛ هذا اقتراح محدود ويمكن تعديله قبل البدء.")
        }
        let pulling: Set<MovementPattern> = [.horizontalPull, .verticalPull]
        if usedPatterns.isDisjoint(with: pulling) {
            warnings.append("لا يحتوي الاقتراح على تمرين سحب؛ أضف معدات مناسبة أو عدّل الجلسة لتحقيق توازن أوسع.")
        }
        return SmartWorkoutPreview(exercises: selected, estimatedMinutes: (seconds + 59) / 60,
                                   warnings: warnings, titleArabic: title)
    }
}

struct SmartExerciseMetadata: Equatable, Sendable {
    let primaryMuscles: Set<MuscleRegion>
    let secondaryMuscles: Set<MuscleRegion>
    let requiredEquipment: Set<TrainingEquipment>
    let movementPattern: MovementPattern
    let mode: TrainingMode
    let difficulty: TrainingLevel

    private init(_ primary: Set<MuscleRegion>, _ secondary: Set<MuscleRegion>,
                 _ equipment: Set<TrainingEquipment>, _ pattern: MovementPattern,
                 mode: TrainingMode = .reps, level: TrainingLevel = .beginner) {
        primaryMuscles = primary; secondaryMuscles = secondary
        requiredEquipment = equipment; movementPattern = pattern; self.mode = mode; difficulty = level
    }

    /// Stable built-in identity, independent of editable Arabic names or broad legacy categories.
    static func forBuiltInID(_ id: UUID) -> SmartExerciseMetadata? {
        let identity = id.uuidString.lowercased()
        guard identity.hasPrefix("00000001-0000-4000-8000-"),
              let code = Int(identity.suffix(12), radix: 16) else { return nil }
        switch code {
        case 1, 3: return Self([.chest], [.triceps, .shoulders], [.barbell, .bench, .rack], .horizontalPush, level: .intermediate)
        case 2, 4: return Self([.chest], [.triceps, .shoulders], [.dumbbell, .bench], .horizontalPush)
        case 5: return Self([.chest], [.shoulders], [.dumbbell, .bench], .isolation)
        case 6: return Self([.chest], [.shoulders], [.cable], .isolation)
        case 7: return Self([.chest], [.triceps, .shoulders], [.chestPress], .horizontalPush)
        case 8: return Self([.chest], [.triceps, .shoulders, .core], [.bodyweight], .horizontalPush)
        case 9: return Self([.chest], [.triceps, .shoulders], [.bodyweight, .dipStation], .verticalPush, level: .intermediate)
        case 10: return Self([.chest], [.shoulders], [.pecDeck], .isolation)
        case 11: return Self([.back], [.biceps, .forearms], [.latPulldown], .verticalPull)
        case 12: return Self([.back], [.biceps, .forearms, .core], [.bodyweight, .pullUpBar], .verticalPull, level: .intermediate)
        case 13: return Self([.back], [.biceps, .forearms, .core], [.barbell], .horizontalPull, level: .intermediate)
        case 14: return Self([.back], [.biceps, .forearms], [.dumbbell, .bench], .horizontalPull)
        case 15: return Self([.back], [.biceps, .forearms], [.seatedCableRow], .horizontalPull)
        case 16: return Self([.back], [.biceps, .forearms], [.rowMachine], .horizontalPull)
        case 17: return Self([.back], [.triceps, .core], [.cable], .isolation)
        case 18: return Self([.back, .glutes, .hamstrings], [.quadriceps, .core, .forearms], [.barbell], .hinge, level: .advanced)
        case 19: return Self([.back], [.glutes, .hamstrings], [.bodyweight, .backExtension], .hinge)
        case 20: return Self([.back], [.shoulders, .biceps], [.band], .horizontalPull)
        case 21: return Self([.shoulders], [.triceps, .core], [.barbell, .rack], .verticalPush, level: .intermediate)
        case 22: return Self([.shoulders], [.triceps], [.dumbbell, .bench], .verticalPush)
        case 23: return Self([.shoulders], [], [.dumbbell], .isolation)
        case 24: return Self([.shoulders], [.chest], [.dumbbell], .isolation)
        case 25: return Self([.shoulders], [.back], [.dumbbell], .isolation)
        case 26: return Self([.shoulders], [.back], [.cable], .horizontalPull)
        case 27: return Self([.shoulders], [.triceps], [.shoulderPress], .verticalPush)
        case 28: return Self([.back], [.forearms], [.dumbbell], .isolation)
        case 29: return Self([.quadriceps, .glutes], [.hamstrings, .core, .back], [.barbell, .rack], .squat, level: .intermediate)
        case 30: return Self([.quadriceps, .glutes], [.core], [.barbell, .rack], .squat, level: .advanced)
        case 31: return Self([.quadriceps, .glutes], [.core], [.dumbbell], .squat)
        case 32: return Self([.quadriceps, .glutes], [.hamstrings], [.legPress], .squat)
        case 33: return Self([.quadriceps], [], [.legExtension], .isolation)
        case 34: return Self([.hamstrings], [], [.legCurl], .isolation)
        case 35: return Self([.hamstrings, .glutes], [.back, .core, .forearms], [.barbell], .hinge, level: .intermediate)
        case 36: return Self([.quadriceps, .glutes], [.hamstrings, .core], [.dumbbell], .squat)
        case 37: return Self([.quadriceps, .glutes], [.hamstrings, .core], [.dumbbell, .bench], .squat, level: .intermediate)
        case 38: return Self([.glutes], [.hamstrings, .core], [.barbell, .bench], .hinge, level: .intermediate)
        case 39: return Self([.calves], [], [.calfRaise], .isolation)
        case 40: return Self([.calves], [], [.seatedCalf], .isolation)
        case 41: return Self([.glutes], [], [.hipAbduction], .isolation)
        case 42: return Self([.adductors], [], [.hipAdduction], .isolation)
        case 43: return Self([.quadriceps, .glutes], [.hamstrings, .core], [.bodyweight, .box], .squat)
        case 44: return Self([.glutes], [.hamstrings, .core], [.bodyweight], .hinge)
        case 45: return Self([.biceps], [.forearms], [.barbell], .isolation)
        case 46: return Self([.biceps], [.forearms], [.dumbbell], .isolation)
        case 47: return Self([.biceps, .forearms], [], [.dumbbell], .isolation)
        case 48: return Self([.biceps], [.forearms], [.cable], .isolation)
        case 49: return Self([.biceps], [], [.preacherCurl], .isolation)
        case 50: return Self([.triceps], [], [.cable], .isolation)
        case 51: return Self([.triceps], [], [.dumbbell, .bench], .isolation)
        case 52: return Self([.triceps], [], [.barbell, .bench], .isolation)
        case 53: return Self([.triceps], [.chest, .shoulders], [.barbell, .bench, .rack], .horizontalPush, level: .intermediate)
        case 54: return Self([.forearms], [], [.dumbbell, .bench], .isolation)
        case 55, 56: return Self([.core], [.shoulders], [.bodyweight], .core, mode: .hold)
        case 57: return Self([.core], [.forearms], [.bodyweight, .pullUpBar], .core, level: .intermediate)
        case 58: return Self([.core], [], [.bodyweight], .core)
        case 59: return Self([.core], [], [.cable], .core)
        case 60: return Self([.core], [.shoulders, .back], [.abWheel], .core, level: .intermediate)
        case 61: return Self([.core], [], [.medicineBall], .core)
        case 62: return Self([.core], [], [.bodyweight], .core)
        case 63: return Self([.quadriceps, .calves, .glutes], [], [.treadmill], .squat, mode: .cardio)
        case 64: return Self([.quadriceps], [.glutes, .calves], [.bike], .squat, mode: .cardio)
        case 65: return Self([.back, .quadriceps], [.biceps, .glutes, .hamstrings], [.rower], .horizontalPull, mode: .cardio)
        case 66: return Self([.calves], [.quadriceps, .shoulders, .core], [.jumpRope], .squat, mode: .cardio)
        default: return nil
        }
    }
}
