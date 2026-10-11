import SwiftUI
import UIKit
import SwiftData

@MainActor struct KeyboardDoneButton: View {
    var body: some View {
        Spacer()
        Button("تم") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            .accessibilityLabel("إنهاء إدخال الأرقام")
    }
}

struct WorkoutActionButtonStyle: ButtonStyle {
    var prominent = true
    var color: Color = .accentColor
    var foreground: Color? = nil
    @WateeraReduceMotion private var reduceMotion: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        WateeraButtonStyle(prominent: prominent, color: color, foreground: foreground).makeBody(configuration: configuration)
            .frame(maxWidth: .infinity)
    }
}

@MainActor struct SetPerformanceLabel: View {
    @Environment(AppSettings.self) private var settings
    @Query private var measurements: [SetMeasurement]
    let set: LoggedSet
    init(set: LoggedSet) {
        self.set = set
        let id = set.id
        _measurements = Query(filter: #Predicate<SetMeasurement> { $0.setID == id })
    }
    private var value: SetMeasurement? { measurements.max { $0.updatedAt < $1.updatedAt } }
    var body: some View {
        Text(label).monospacedDigit().accessibilityLabel(label)
    }
    private var label: String {
        switch value?.modeRaw {
        case "timed": return ArabicFormat.duration(value?.seconds ?? 0, arabic: settings.useArabicDigits)
        case "distance": return ArabicFormat.number(value?.distanceMeters ?? 0, arabic: settings.useArabicDigits) + " متر • " + ArabicFormat.duration(value?.seconds ?? 0, arabic: settings.useArabicDigits)
        case "assisted": return "مساعدة " + ArabicFormat.weight(value?.assistanceKg ?? 0, settings: settings) + " × " + ArabicFormat.integer(set.reps, arabic: settings.useArabicDigits)
        default:
            let numbers = ArabicFormat.weight(set.weightKg, settings: settings) + " × " + ArabicFormat.integer(set.reps, arabic: settings.useArabicDigits)
            return value.map { numbers + " • " + (LoadConvention(rawValue: $0.conventionRaw)?.arabicName ?? "الوزن الكلي") } ?? numbers
        }
    }
}
