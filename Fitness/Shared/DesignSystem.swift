import SwiftUI
import UIKit

/// The system Reduce Motion value is read-only. UI fixtures exercise the same conservative
/// rendering path without trying to mutate a system-owned environment key.
@propertyWrapper struct WateeraReduceMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var systemValue
    init() {}
    var wrappedValue: Bool {
        systemValue || (ProcessInfo.processInfo.arguments.contains("-ui-testing") && ProcessInfo.processInfo.environment["FITNESS_TEST_REDUCE_MOTION"] == "1")
    }
}

/// All visual tokens live here. Semantic colors adapt without rewriting stored preferences.
enum WateeraDesign {
    enum Space { static let xs: CGFloat = 6; static let small: CGFloat = 12; static let medium: CGFloat = 20; static let large: CGFloat = 28; static let page: CGFloat = 18 }
    enum Radius { static let control: CGFloat = 14; static let card: CGFloat = 24; static let hero: CGFloat = 30 }
    enum TypeStyle { static let title = Font.title2.bold(); static let metric = Font.title.bold(); static let body = Font.body; static let caption = Font.caption }
    static let canvas = adaptive(light: 0xF3F5F8, dark: 0x0B1018)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x171E2A)
    static let inset = adaptive(light: 0xEAF0F4, dark: 0x222C3B)
    static let ink = adaptive(light: 0x172534, dark: 0xF4F7FC)
    static let brand = adaptive(light: 0x007F64, dark: 0x62E8BF)
    static let blue = adaptive(light: 0x2464BB, dark: 0x8CB8FF)
    static let coral = adaptive(light: 0xBB5140, dark: 0xFFAC96)
    static let gold = adaptive(light: 0x956009, dark: 0xF5D089)
    static let hairline = adaptive(light: 0xDEE6ED, dark: 0x303B4C)
    static let shadow = Color.black.opacity(0.045)
    static let hero = LinearGradient(colors: [Color(uiColor: UIColor(red: 0.06, green: 0.17, blue: 0.23, alpha: 1)), Color(uiColor: UIColor(red: 0.03, green: 0.32, blue: 0.28, alpha: 1))], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

struct WateeraCard: ViewModifier {
    var padding: CGFloat = WateeraDesign.Space.medium
    func body(content: Content) -> some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(WateeraDesign.surface, in: RoundedRectangle(cornerRadius: WateeraDesign.Radius.card))
            .overlay { RoundedRectangle(cornerRadius: WateeraDesign.Radius.card).strokeBorder(WateeraDesign.hairline.opacity(0.5), lineWidth: 0.5) }
            .shadow(color: WateeraDesign.shadow, radius: 12, x: 0, y: 5)
    }
}

extension View {
    func wateeraCard(padding: CGFloat = WateeraDesign.Space.medium) -> some View { modifier(WateeraCard(padding: padding)) }
    func wateeraCanvas() -> some View {
        scrollContentBackground(.hidden).background(WateeraDesign.canvas).toolbarBackground(.visible, for: .tabBar)
    }
}

struct WateeraButtonStyle: ButtonStyle {
    var prominent = true
    var color: Color = WateeraDesign.brand
    var foreground: Color? = nil
    @WateeraReduceMotion private var reduceMotion: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 48)
            .foregroundStyle(foreground ?? (prominent ? WateeraDesign.surface : color))
            .background(prominent ? color : color.opacity(0.10), in: RoundedRectangle(cornerRadius: WateeraDesign.Radius.control))
            .opacity(enabled ? 1 : 0.45).scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct WateeraCardButtonStyle: ButtonStyle {
    @WateeraReduceMotion private var reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(RoundedRectangle(cornerRadius: WateeraDesign.Radius.card))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DestinationRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(WateeraDesign.brand)
                .frame(width: 44, height: 44).background(WateeraDesign.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline).foregroundStyle(.primary); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.caption.bold()).foregroundStyle(.secondary).accessibilityHidden(true)
        }.frame(minHeight: 48).wateeraCard(padding: 14)
    }
}

/// Static skeletons avoid perpetual animation during the very short local-store bootstrap.
struct DashboardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "dumbbell.fill").font(.largeTitle).foregroundStyle(WateeraDesign.brand)
            Text("وتيرة").font(.largeTitle.bold())
            RoundedRectangle(cornerRadius: 28).fill(WateeraDesign.inset).frame(height: 180)
            HStack { RoundedRectangle(cornerRadius: 24).fill(WateeraDesign.inset); RoundedRectangle(cornerRadius: 24).fill(WateeraDesign.inset) }.frame(height: 100)
            Text("جارٍ تجهيز يومك…").font(.subheadline).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(WateeraDesign.canvas).accessibilityElement(children: .ignore).accessibilityLabel("جارٍ تجهيز وتيرة")
    }
}
