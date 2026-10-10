import Foundation
import SwiftData

struct CatalogEntry: Sendable {
    let code: Int
    let name: String
    let muscle: String
    let secondary: String
    let equipment: String
    var kind: String = "قوة"
}

enum SeedCatalog {
    // Codes are permanent identity values. Append new codes; never reuse an existing code.
    static let entries: [CatalogEntry] = [
        CatalogEntry(code: 1, name: "ضغط الصدر بالبار", muscle: "صدر", secondary: "ذراعان، أكتاف", equipment: "بار"),
        CatalogEntry(code: 2, name: "ضغط الصدر بالدمبل", muscle: "صدر", secondary: "ذراعان، أكتاف", equipment: "دمبل"),
        CatalogEntry(code: 3, name: "ضغط الصدر المائل بالبار", muscle: "صدر", secondary: "أكتاف، ذراعان", equipment: "بار"),
        CatalogEntry(code: 4, name: "ضغط الصدر المائل بالدمبل", muscle: "صدر", secondary: "أكتاف، ذراعان", equipment: "دمبل"),
        CatalogEntry(code: 5, name: "تفتيح الصدر بالدمبل", muscle: "صدر", secondary: "أكتاف", equipment: "دمبل"),
        CatalogEntry(code: 6, name: "تفتيح الصدر بالكابل", muscle: "صدر", secondary: "أكتاف", equipment: "كابل"),
        CatalogEntry(code: 7, name: "ضغط الصدر بالجهاز", muscle: "صدر", secondary: "ذراعان", equipment: "جهاز"),
        CatalogEntry(code: 8, name: "تمرين الضغط", muscle: "صدر", secondary: "ذراعان، بطن", equipment: "وزن الجسم"),
        CatalogEntry(code: 9, name: "المتوازي للصدر", muscle: "صدر", secondary: "ذراعان، أكتاف", equipment: "وزن الجسم"),
        CatalogEntry(code: 10, name: "تفتيح الصدر بالجهاز", muscle: "صدر", secondary: "أكتاف", equipment: "جهاز"),
        CatalogEntry(code: 11, name: "السحب العلوي", muscle: "ظهر", secondary: "ذراعان", equipment: "كابل"),
        CatalogEntry(code: 12, name: "العقلة", muscle: "ظهر", secondary: "ذراعان، بطن", equipment: "وزن الجسم"),
        CatalogEntry(code: 13, name: "التجديف بالبار", muscle: "ظهر", secondary: "ذراعان، بطن", equipment: "بار"),
        CatalogEntry(code: 14, name: "التجديف بالدمبل", muscle: "ظهر", secondary: "ذراعان", equipment: "دمبل"),
        CatalogEntry(code: 15, name: "السحب الأرضي بالكابل", muscle: "ظهر", secondary: "ذراعان", equipment: "كابل"),
        CatalogEntry(code: 16, name: "التجديف بالجهاز", muscle: "ظهر", secondary: "ذراعان", equipment: "جهاز"),
        CatalogEntry(code: 17, name: "السحب المستقيم بالكابل", muscle: "ظهر", secondary: "ذراعان", equipment: "كابل"),
        CatalogEntry(code: 18, name: "الرفعة الميتة", muscle: "ظهر", secondary: "أرجل، بطن", equipment: "بار"),
        CatalogEntry(code: 19, name: "تمديد أسفل الظهر", muscle: "ظهر", secondary: "أرجل", equipment: "وزن الجسم"),
        CatalogEntry(code: 20, name: "السحب بالمطاط", muscle: "ظهر", secondary: "أكتاف، ذراعان", equipment: "مطاط"),
        CatalogEntry(code: 21, name: "ضغط الكتف بالبار", muscle: "أكتاف", secondary: "ذراعان، بطن", equipment: "بار"),
        CatalogEntry(code: 22, name: "ضغط الكتف بالدمبل", muscle: "أكتاف", secondary: "ذراعان", equipment: "دمبل"),
        CatalogEntry(code: 23, name: "الرفرفة الجانبية", muscle: "أكتاف", secondary: "", equipment: "دمبل"),
        CatalogEntry(code: 24, name: "الرفرفة الأمامية", muscle: "أكتاف", secondary: "صدر", equipment: "دمبل"),
        CatalogEntry(code: 25, name: "الرفرفة الخلفية", muscle: "أكتاف", secondary: "ظهر", equipment: "دمبل"),
        CatalogEntry(code: 26, name: "سحب الوجه بالكابل", muscle: "أكتاف", secondary: "ظهر", equipment: "كابل"),
        CatalogEntry(code: 27, name: "ضغط الكتف بالجهاز", muscle: "أكتاف", secondary: "ذراعان", equipment: "جهاز"),
        CatalogEntry(code: 28, name: "هز الكتفين بالدمبل", muscle: "أكتاف", secondary: "ظهر", equipment: "دمبل"),
        CatalogEntry(code: 29, name: "القرفصاء بالبار", muscle: "أرجل", secondary: "بطن، ظهر", equipment: "بار"),
        CatalogEntry(code: 30, name: "القرفصاء الأمامية", muscle: "أرجل", secondary: "بطن", equipment: "بار"),
        CatalogEntry(code: 31, name: "القرفصاء بالدمبل", muscle: "أرجل", secondary: "بطن", equipment: "دمبل"),
        CatalogEntry(code: 32, name: "ضغط الأرجل", muscle: "أرجل", secondary: "", equipment: "جهاز"),
        CatalogEntry(code: 33, name: "تمديد الأرجل", muscle: "أرجل", secondary: "", equipment: "جهاز"),
        CatalogEntry(code: 34, name: "ثني الأرجل", muscle: "أرجل", secondary: "", equipment: "جهاز"),
        CatalogEntry(code: 35, name: "الرفعة الرومانية", muscle: "أرجل", secondary: "ظهر، بطن", equipment: "بار"),
        CatalogEntry(code: 36, name: "الاندفاع بالدمبل", muscle: "أرجل", secondary: "بطن", equipment: "دمبل"),
        CatalogEntry(code: 37, name: "القرفصاء البلغارية", muscle: "أرجل", secondary: "بطن", equipment: "دمبل"),
        CatalogEntry(code: 38, name: "دفع الورك بالبار", muscle: "أرجل", secondary: "بطن", equipment: "بار"),
        CatalogEntry(code: 39, name: "رفع الكعبين واقفًا", muscle: "أرجل", secondary: "", equipment: "جهاز"),
        CatalogEntry(code: 40, name: "رفع الكعبين جالسًا", muscle: "أرجل", secondary: "", equipment: "جهاز"),
        CatalogEntry(code: 41, name: "فتح الوركين بالجهاز", muscle: "أرجل", secondary: "", equipment: "جهاز"),
        CatalogEntry(code: 42, name: "ضم الوركين بالجهاز", muscle: "أرجل", secondary: "", equipment: "جهاز"),
        CatalogEntry(code: 43, name: "صعود الصندوق", muscle: "أرجل", secondary: "بطن", equipment: "وزن الجسم"),
        CatalogEntry(code: 44, name: "الجسر الأرضي", muscle: "أرجل", secondary: "بطن", equipment: "وزن الجسم"),
        CatalogEntry(code: 45, name: "ثني الذراع بالبار", muscle: "ذراعان", secondary: "", equipment: "بار"),
        CatalogEntry(code: 46, name: "ثني الذراع بالدمبل", muscle: "ذراعان", secondary: "", equipment: "دمبل"),
        CatalogEntry(code: 47, name: "ثني الذراع بالمطرقة", muscle: "ذراعان", secondary: "", equipment: "دمبل"),
        CatalogEntry(code: 48, name: "ثني الذراع بالكابل", muscle: "ذراعان", secondary: "", equipment: "كابل"),
        CatalogEntry(code: 49, name: "ثني الذراع على المقعد", muscle: "ذراعان", secondary: "", equipment: "جهاز"),
        CatalogEntry(code: 50, name: "دفع الذراع بالكابل", muscle: "ذراعان", secondary: "", equipment: "كابل"),
        CatalogEntry(code: 51, name: "تمديد الذراع فوق الرأس", muscle: "ذراعان", secondary: "", equipment: "دمبل"),
        CatalogEntry(code: 52, name: "تمديد الذراع بالبار مستلقيًا", muscle: "ذراعان", secondary: "", equipment: "بار"),
        CatalogEntry(code: 53, name: "ضغط الصدر بقبضة ضيقة", muscle: "ذراعان", secondary: "صدر، أكتاف", equipment: "بار"),
        CatalogEntry(code: 54, name: "ثني الرسغ بالدمبل", muscle: "ذراعان", secondary: "", equipment: "دمبل"),
        CatalogEntry(code: 55, name: "الثبات الأمامي", muscle: "بطن", secondary: "أكتاف", equipment: "وزن الجسم", kind: "ثبات"),
        CatalogEntry(code: 56, name: "الثبات الجانبي", muscle: "بطن", secondary: "أكتاف", equipment: "وزن الجسم", kind: "ثبات"),
        CatalogEntry(code: 57, name: "رفع الركبتين معلقًا", muscle: "بطن", secondary: "ذراعان", equipment: "وزن الجسم"),
        CatalogEntry(code: 58, name: "كرنش البطن", muscle: "بطن", secondary: "", equipment: "وزن الجسم"),
        CatalogEntry(code: 59, name: "كرنش البطن بالكابل", muscle: "بطن", secondary: "", equipment: "كابل"),
        CatalogEntry(code: 60, name: "عجلة البطن", muscle: "بطن", secondary: "أكتاف", equipment: "جهاز"),
        CatalogEntry(code: 61, name: "الالتفاف الروسي", muscle: "بطن", secondary: "", equipment: "كرة"),
        CatalogEntry(code: 62, name: "الحشرة الميتة", muscle: "بطن", secondary: "", equipment: "وزن الجسم"),
        CatalogEntry(code: 63, name: "المشي على السير", muscle: "أرجل", secondary: "", equipment: "جهاز", kind: "لياقة"),
        CatalogEntry(code: 64, name: "الدراجة الثابتة", muscle: "أرجل", secondary: "", equipment: "جهاز", kind: "لياقة"),
        CatalogEntry(code: 65, name: "التجديف الهوائي", muscle: "ظهر", secondary: "أرجل، ذراعان", equipment: "جهاز", kind: "لياقة"),
        CatalogEntry(code: 66, name: "قفز الحبل", muscle: "أرجل", secondary: "أكتاف", equipment: "حبل", kind: "لياقة")
    ]

    static let muscles = ["صدر", "ظهر", "أكتاف", "أرجل", "ذراعان", "بطن"]
    static let equipment = ["بار", "دمبل", "جهاز", "كابل", "وزن الجسم", "مطاط", "كرة", "حبل"]

    static func stableID(namespace: Int, code: Int) -> UUID {
        let text = String(format: "%08x-0000-4000-8000-%012llx", namespace, Int64(code))
        // All callers use nonnegative bounded constants; the fallback remains deterministic.
        return UUID(uuidString: text) ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 0))
    }

    @MainActor
    static func seedIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) throws {
        let marker = "fitness.catalog.seeded.v1"
        guard !defaults.bool(forKey: marker) else { return }
        let existingExercises = Set(try context.fetch(FetchDescriptor<Exercise>()).map(\.id))
        let seedDate = Date(timeIntervalSince1970: 1_704_499_200) // Saturday, January 6, 2024, UTC.
        for entry in entries {
            let id = stableID(namespace: 1, code: entry.code)
            guard !existingExercises.contains(id) else { continue }
            context.insert(Exercise(id: id, name: entry.name, primaryMuscleRaw: entry.muscle,
                                    secondaryMusclesRaw: entry.secondary, equipmentRaw: entry.equipment,
                                    kindRaw: entry.kind, updatedAt: seedDate))
        }

        let plans = try context.fetch(FetchDescriptor<WorkoutPlan>())
        let existingPlans = Set(plans.map(\.id))
        let existingDays = Set(try context.fetch(FetchDescriptor<PlanDay>()).map(\.id))
        let existingPlanExercises = Set(try context.fetch(FetchDescriptor<PlanExercise>()).map(\.id))
        let templates: [(Int, String, [(Int, String, [Int])])] = [
            (1, "الجسم كامل", [
                (7, "الجسم كامل — أ", [29, 1, 15, 23, 55]),
                (2, "الجسم كامل — ب", [35, 22, 11, 36, 58]),
                (4, "الجسم كامل — ج", [32, 4, 14, 46, 50])
            ]),
            (2, "تمارين الدفع والسحب والأرجل", [
                (7, "الدفع", [1, 4, 22, 23, 50]),
                (1, "السحب", [18, 11, 15, 26, 46]),
                (2, "الأرجل", [29, 35, 32, 34, 39]),
                (4, "الدفع", [7, 3, 27, 23, 51]),
                (5, "السحب", [12, 14, 17, 25, 47]),
                (6, "الأرجل", [30, 37, 33, 34, 40])
            ]),
            (3, "علوي وسفلي", [
                (7, "الجسم العلوي — أ", [1, 13, 22, 46, 50]),
                (1, "الجسم السفلي — أ", [29, 35, 33, 39, 55]),
                (3, "الجسم العلوي — ب", [4, 11, 23, 47, 51]),
                (4, "الجسم السفلي — ب", [32, 37, 34, 38, 58])
            ])
        ]
        for (code, name, workouts) in templates {
            let planID = stableID(namespace: 2, code: code)
            // Existing plans include edits and intentional schedules; never rebuild their children.
            guard !existingPlans.contains(planID) else { continue }
            context.insert(WorkoutPlan(id: planID, name: name,
                                       notes: "قالب قابل للتعديل. اختر الأوزان المناسبة لك وعدّل أيام التدريب حسب جدولك.",
                                       programStart: seedDate, isActive: code == 1 && !plans.contains(where: \.isActive),
                                       updatedAt: seedDate))
            for weekday in 1...7 {
                let workout = workouts.first { $0.0 == weekday }
                let dayID = stableID(namespace: 3, code: code * 100 + weekday)
                guard !existingDays.contains(dayID) else { continue }
                context.insert(PlanDay(id: dayID, planID: planID, weekday: weekday,
                                       isRest: workout == nil, title: workout?.1 ?? "راحة",
                                       updatedAt: seedDate))
                for (order, exerciseCode) in (workout?.2 ?? []).enumerated() {
                    let id = stableID(namespace: 4, code: code * 10_000 + weekday * 100 + order)
                    guard !existingPlanExercises.contains(id) else { continue }
                    context.insert(PlanExercise(id: id, dayID: dayID,
                                                exerciseID: stableID(namespace: 1, code: exerciseCode),
                                                order: order, targetSets: 3, targetReps: 10,
                                                restSeconds: 90, updatedAt: seedDate))
                }
            }
        }
        try context.save()
        defaults.set(true, forKey: marker)
    }
}
