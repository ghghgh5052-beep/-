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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(prominent ? Color.white : Color.accentColor)
            .background(prominent ? Color.accentColor : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
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
        default: return ArabicFormat.weight(set.weightKg, settings: settings) + " × " + ArabicFormat.integer(set.reps, arabic: settings.useArabicDigits)
        }
    }
}
