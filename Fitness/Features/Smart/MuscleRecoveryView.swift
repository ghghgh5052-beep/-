import SwiftUI
import SwiftData

@MainActor struct MuscleRecoveryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    @State private var recoveries: [MuscleRecovery] = []
    @State private var selected: MuscleRegion = .chest
    @State private var errorMessage: String?
    @State private var unsupportedExerciseCount = 0
    @State private var refreshedAt = Date()

    private var byRegion: [MuscleRegion: MuscleRecovery] {
        Dictionary(recoveries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("حمل التدريب على جسمك", systemImage: "figure.stand")
                        .font(.title3.bold()).foregroundStyle(settings.color)
                    Text("خريطة تقديرية من الجولات المكتملة والوقت والجهد المسجل. النسبة تساعدك على التخطيط؛ شعورك بالتعب وأداؤك قد يختلفان عنها.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 16) {
                    RecoveryBodyDiagram(isBack: false, recoveries: byRegion, selected: selected)
                        .accessibilityIdentifier("recovery.diagram.front")
                    RecoveryBodyDiagram(isBack: true, recoveries: byRegion, selected: selected)
                        .accessibilityIdentifier("recovery.diagram.back")
                }.padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                legend
                selectedDetail
                if recoveries.allSatisfy({ $0.readiness == nil }) {
                    Label("أكمل جلسة تدريب وسجّل جولاتك لتظهر تقديرات الحمل. المناطق الرمادية تعني أن السجل غير كافٍ.", systemImage: "info.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("اختر عضلة للتفاصيل").font(.headline)
                VStack(spacing: 0) {
                    ForEach(MuscleRegion.allCases) { region in
                        regionButton(region)
                        if region != MuscleRegion.allCases.last { Divider().padding(.horizontal, 16) }
                    }
                }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 8) {
                    Text("كيف يُحسب التقدير؟").font(.headline)
                    Text("يزداد الحمل مع عدد الجولات والجهد المرتفع والفشل العضلي، ويقل أثره تدريجيًا خلال ثلاثة أيام. تُحسب العضلات المساعدة بحمل أقل. مجموع الجولات هنا يشمل آخر سبعة أيام، وقد تدخل الجولة نفسها في أكثر من عضلة.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("هذا تقدير للتخطيط من سجلك، ولا يقيس الاستشفاء الفعلي أو النوم أو الإصابات. لا يوجد سجل كافٍ لا تعني أن العضلة مستشفية بالكامل.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if unsupportedExerciseCount > 0 {
                        Text("لا تدخل التمارين الخاصة أو غير المعروفة في الخريطة الحالية؛ تظل محفوظة في سجل تدريبك.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("استشفاء العضلات").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("recovery.screen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { refresh() } label: { Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("تحديث تقدير الاستشفاء")
                        .accessibilityIdentifier("recovery.refresh")
                }
            }
            .task { refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
            .arabicError($errorMessage)
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
            legendItem("تقدير مرتفع", color: RecoveryPalette.color(1))
            legendItem("تقدير متوسط", color: RecoveryPalette.color(0.6))
            legendItem("حمل حديث مرتفع", color: RecoveryPalette.color(0.2))
            legendItem("سجل غير كافٍ", color: RecoveryPalette.color(nil))
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(title).font(.caption).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }

    private var selectedDetail: some View {
        let recovery = byRegion[selected]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selected.arabicName).font(.headline)
                Spacer(minLength: 8)
                Text(percentage(recovery?.readiness)).font(.title2.bold()).monospacedDigit()
                    .accessibilityLabel("تقدير الاستشفاء، " + percentage(recovery?.readiness))
                    .accessibilityIdentifier("recovery.detail.readiness")
            }
            if let readiness = recovery?.readiness {
                ProgressView(value: readiness, total: 1).tint(RecoveryPalette.color(readiness))
                    .accessibilityLabel("تقدير الاستشفاء")
                    .accessibilityValue(percentage(readiness))
            }
            Text(recovery?.summaryArabic ?? "لا يوجد سجل كافٍ للتقدير")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top) {
                Text("آخر تدريب مسجل").foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(recovery?.lastTrained.map { ArabicFormat.date($0, arabic: settings.useArabicDigits) } ?? "لا يوجد")
                    .multilineTextAlignment(.trailing)
            }.font(.subheadline).accessibilityElement(children: .combine)
                .accessibilityIdentifier("recovery.detail.date")
            HStack {
                Text("الجولات خلال آخر سبعة أيام").foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(ArabicFormat.integer(recovery?.recentSets ?? 0, arabic: settings.useArabicDigits))
            }.font(.subheadline).accessibilityElement(children: .combine)
                .accessibilityIdentifier("recovery.detail.sets")
            Text("التقدير محدّث في " + time(refreshedAt)).font(.caption).foregroundStyle(.tertiary)
        }.padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(RecoveryPalette.color(recovery?.readiness).opacity(0.5), lineWidth: 1))
    }

    private func regionButton(_ region: MuscleRegion) -> some View {
        let recovery = byRegion[region]
        return Button {
            if reduceMotion { selected = region }
            else { withAnimation(.easeInOut(duration: 0.2)) { selected = region } }
        } label: {
            HStack(spacing: 12) {
                Circle().fill(RecoveryPalette.color(recovery?.readiness)).frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(region.arabicName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(recovery?.summaryArabic ?? "لا يوجد سجل كافٍ للتقدير")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text(percentage(recovery?.readiness)).font(.subheadline).monospacedDigit().foregroundStyle(.primary)
                if selected == region {
                    Image(systemName: "checkmark").foregroundStyle(settings.color).accessibilityHidden(true)
                }
            }.frame(minHeight: 52).padding(.horizontal, 16).padding(.vertical, 10)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(region.arabicName + "، " + percentage(recovery?.readiness) + "، "
                                + (recovery?.summaryArabic ?? "لا يوجد سجل كافٍ للتقدير"))
            .accessibilityHint("عرض تاريخ التدريب وعدد الجولات")
            .accessibilityAddTraits(selected == region ? [.isSelected] : [])
            .accessibilityIdentifier("recovery.region.\(region.rawValue)")
    }

    private func percentage(_ value: Double?) -> String {
        guard let value else { return "غير محدد" }
        return ArabicFormat.integer(Int((min(1, max(0, value)) * 100).rounded()), arabic: settings.useArabicDigits) + "٪"
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_SA")
        formatter.dateFormat = "HH:mm"
        return ArabicFormat.digits(formatter.string(from: date), arabic: settings.useArabicDigits)
    }

    private func refresh() {
        do {
            let snapshot = try SmartTrainingStore.snapshot(context: context)
            let now = Date()
            recoveries = SmartTrainingEngine.recoveries(exercises: snapshot.recoveryExercises, history: snapshot.history, now: now)
            unsupportedExerciseCount = snapshot.unsupportedExerciseCount
            refreshedAt = now
        } catch {
            errorMessage = "تعذر تحديث خريطة العضلات. سجلاتك محفوظة؛ حاول مرة أخرى."
        }
    }
}

private enum RecoveryPalette {
    static func color(_ readiness: Double?) -> Color {
        guard let readiness else { return Color(uiColor: .systemGray3) }
        if readiness < 0.45 { return Color(red: 0.91, green: 0.39, blue: 0.16) }
        if readiness < 0.75 { return Color(red: 0.9, green: 0.65, blue: 0.1) }
        return Color(red: 0.06, green: 0.64, blue: 0.48)
    }
}

/// Original normalized vector regions remain crisp at any display scale.
@MainActor private struct RecoveryBodyDiagram: View {
    let isBack: Bool
    let recoveries: [MuscleRegion: MuscleRecovery]
    let selected: MuscleRegion

    private var visibleRegions: [MuscleRegion] {
        isBack ? [.back, .shoulders, .triceps, .forearms, .glutes, .hamstrings, .adductors, .calves]
               : [.chest, .shoulders, .biceps, .forearms, .core, .quadriceps, .adductors, .calves]
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RecoveryBodyOutline().fill(Color(uiColor: .tertiarySystemFill))
                RecoveryBodyOutline().stroke(Color.primary.opacity(0.1), lineWidth: 1)
                ForEach(visibleRegions, id: \.self) { region in
                    RecoveryMuscleShape(region: region)
                        .fill(RecoveryPalette.color(recoveries[region]?.readiness))
                        .opacity(selected == region ? 1 : 0.82)
                    RecoveryMuscleShape(region: region)
                        .stroke(selected == region ? Color.primary.opacity(0.75) : Color(uiColor: .secondarySystemGroupedBackground),
                                lineWidth: selected == region ? 1.6 : 1)
                }
            }.aspectRatio(100.0 / 250.0, contentMode: .fit)
                .environment(\.layoutDirection, .leftToRight)
            Text(isBack ? "من الخلف" : "من الأمام").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isBack ? "خريطة عضلات الجسم من الخلف" : "خريطة عضلات الجسم من الأمام")
            .accessibilityHint("اختر اسم العضلة من القائمة لقراءة تقديرها")
    }
}

private struct RecoveryBodyOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 43, y: 3, width: 14, height: 21))
        path.addRoundedRect(in: CGRect(x: 46, y: 21, width: 8, height: 12), cornerSize: CGSize(width: 3, height: 3))
        path.move(to: CGPoint(x: 40, y: 30))
        path.addQuadCurve(to: CGPoint(x: 26, y: 36), control: CGPoint(x: 27, y: 29))
        path.addQuadCurve(to: CGPoint(x: 23, y: 68), control: CGPoint(x: 20, y: 49))
        path.addLine(to: CGPoint(x: 18, y: 105))
        path.addQuadCurve(to: CGPoint(x: 21, y: 118), control: CGPoint(x: 15, y: 118))
        path.addLine(to: CGPoint(x: 27, y: 116))
        path.addLine(to: CGPoint(x: 30, y: 81))
        path.addLine(to: CGPoint(x: 34, y: 59))
        path.addLine(to: CGPoint(x: 39, y: 87))
        path.addQuadCurve(to: CGPoint(x: 34, y: 117), control: CGPoint(x: 34, y: 103))
        path.addLine(to: CGPoint(x: 33, y: 169))
        path.addLine(to: CGPoint(x: 37, y: 186))
        path.addLine(to: CGPoint(x: 35, y: 233))
        path.addQuadCurve(to: CGPoint(x: 31, y: 245), control: CGPoint(x: 31, y: 237))
        path.addQuadCurve(to: CGPoint(x: 44, y: 245), control: CGPoint(x: 36, y: 249))
        path.addLine(to: CGPoint(x: 46, y: 222))
        path.addLine(to: CGPoint(x: 47, y: 180))
        path.addLine(to: CGPoint(x: 50, y: 124))
        path.addLine(to: CGPoint(x: 53, y: 180))
        path.addLine(to: CGPoint(x: 54, y: 222))
        path.addLine(to: CGPoint(x: 56, y: 245))
        path.addQuadCurve(to: CGPoint(x: 69, y: 245), control: CGPoint(x: 64, y: 249))
        path.addQuadCurve(to: CGPoint(x: 65, y: 233), control: CGPoint(x: 69, y: 237))
        path.addLine(to: CGPoint(x: 63, y: 186))
        path.addLine(to: CGPoint(x: 67, y: 169))
        path.addLine(to: CGPoint(x: 66, y: 117))
        path.addQuadCurve(to: CGPoint(x: 61, y: 87), control: CGPoint(x: 66, y: 103))
        path.addLine(to: CGPoint(x: 66, y: 59))
        path.addLine(to: CGPoint(x: 70, y: 81))
        path.addLine(to: CGPoint(x: 73, y: 116))
        path.addLine(to: CGPoint(x: 79, y: 118))
        path.addQuadCurve(to: CGPoint(x: 82, y: 105), control: CGPoint(x: 85, y: 118))
        path.addLine(to: CGPoint(x: 77, y: 68))
        path.addQuadCurve(to: CGPoint(x: 74, y: 36), control: CGPoint(x: 80, y: 49))
        path.addQuadCurve(to: CGPoint(x: 60, y: 30), control: CGPoint(x: 73, y: 29))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 250)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

private struct RecoveryMuscleShape: Shape {
    let region: MuscleRegion

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func polygon(_ points: [CGPoint]) {
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        func paired(_ points: [CGPoint]) {
            polygon(points)
            polygon(points.map { CGPoint(x: 100 - $0.x, y: $0.y) })
        }
        switch region {
        case .chest:
            paired([CGPoint(x: 35, y: 37), CGPoint(x: 49, y: 37), CGPoint(x: 49, y: 57),
                    CGPoint(x: 40, y: 61), CGPoint(x: 34, y: 53)])
        case .back:
            paired([CGPoint(x: 40, y: 32), CGPoint(x: 49, y: 42), CGPoint(x: 49, y: 86),
                    CGPoint(x: 40, y: 85), CGPoint(x: 35, y: 63), CGPoint(x: 34, y: 43)])
        case .shoulders:
            paired([CGPoint(x: 28, y: 35), CGPoint(x: 34, y: 35), CGPoint(x: 33, y: 49),
                    CGPoint(x: 25, y: 51), CGPoint(x: 24, y: 44)])
        case .biceps, .triceps:
            paired([CGPoint(x: 25, y: 53), CGPoint(x: 32, y: 51), CGPoint(x: 29, y: 75),
                    CGPoint(x: 23, y: 75), CGPoint(x: 22, y: 64)])
        case .forearms:
            paired([CGPoint(x: 23, y: 80), CGPoint(x: 29, y: 79), CGPoint(x: 26, y: 103),
                    CGPoint(x: 20, y: 105), CGPoint(x: 20, y: 98)])
        case .core:
            paired([CGPoint(x: 41, y: 63), CGPoint(x: 49, y: 61), CGPoint(x: 49, y: 99),
                    CGPoint(x: 40, y: 95), CGPoint(x: 40, y: 81)])
        case .quadriceps:
            paired([CGPoint(x: 37, y: 109), CGPoint(x: 45, y: 113), CGPoint(x: 44, y: 154),
                    CGPoint(x: 42, y: 171), CGPoint(x: 36, y: 165), CGPoint(x: 35, y: 134)])
        case .hamstrings:
            paired([CGPoint(x: 36, y: 124), CGPoint(x: 45, y: 125), CGPoint(x: 44, y: 167),
                    CGPoint(x: 39, y: 173), CGPoint(x: 35, y: 153)])
        case .adductors:
            paired([CGPoint(x: 46, y: 121), CGPoint(x: 49, y: 125), CGPoint(x: 47, y: 164),
                    CGPoint(x: 45, y: 152), CGPoint(x: 45, y: 133)])
        case .glutes:
            paired([CGPoint(x: 39, y: 91), CGPoint(x: 49, y: 91), CGPoint(x: 49, y: 120),
                    CGPoint(x: 39, y: 120), CGPoint(x: 35, y: 115), CGPoint(x: 36, y: 104)])
        case .calves:
            paired([CGPoint(x: 38, y: 182), CGPoint(x: 45, y: 183), CGPoint(x: 45, y: 207),
                    CGPoint(x: 41, y: 225), CGPoint(x: 37, y: 215), CGPoint(x: 36, y: 196)])
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 250)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
