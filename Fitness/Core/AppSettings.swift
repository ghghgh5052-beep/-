import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor @Observable
final class AppSettings {
    var useArabicDigits = true { didSet { persist() } }
    var weightUnit = "kg" { didSet { persist() } }
    var lengthUnit = "cm" { didSet { persist() } }
    var defaultRestSeconds = 90 { didSet { persist() } }
    var weekStart = 7 { didSet { persist() } }
    var theme = "system" { didSet { persist() } }
    var accent = "mint" { didSet { persist() } }
    var lockEnabled = UserDefaults.standard.bool(forKey: "lockEnabled") {
        didSet { UserDefaults.standard.set(lockEnabled, forKey: "lockEnabled") }
    }
    var photoLockEnabled = UserDefaults.standard.bool(forKey: "photoLockEnabled") {
        didSet { UserDefaults.standard.set(photoLockEnabled, forKey: "photoLockEnabled") }
    }
    var healthEnabled = UserDefaults.standard.bool(forKey: "healthEnabled") {
        didSet { UserDefaults.standard.set(healthEnabled, forKey: "healthEnabled") }
    }
    var saveError: String?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var preferences: UserPreferences?
    @ObservationIgnored private var loading = false

    var color: Color {
        switch accent {
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        default: return Color(red: 0.06, green: 0.64, blue: 0.48)
        }
    }
    var colorScheme: ColorScheme? {
        theme == "dark" ? .dark : (theme == "light" ? .light : nil)
    }
    func displayWeight(_ kg: Double) -> Double { weightUnit == "lb" ? kg * 2.2046226218 : kg }
    func kilograms(_ displayWeight: Double) -> Double { weightUnit == "lb" ? displayWeight / 2.2046226218 : displayWeight }
    func displayLength(_ cm: Double) -> Double { lengthUnit == "in" ? cm / 2.54 : cm }
    func centimeters(_ displayLength: Double) -> Double { lengthUnit == "in" ? displayLength * 2.54 : displayLength }
    var weightLabel: String { weightUnit == "lb" ? "رطل" : "كجم" }
    var lengthLabel: String { lengthUnit == "in" ? "بوصة" : "سم" }

    func bind(context: ModelContext) {
        self.context = context
        reload()
    }
    func reload() {
        guard let context else { return }
        do {
            let records = try context.fetch(FetchDescriptor<UserPreferences>())
            let record: UserPreferences
            if let existing = records.filter({ $0.key == "settings" }).max(by: { $0.updatedAt < $1.updatedAt }) {
                record = existing
            } else {
                record = UserPreferences()
                context.insert(record)
                try context.save()
            }
            loading = true
            preferences = record
            useArabicDigits = record.useArabicDigits
            weightUnit = record.weightUnit
            lengthUnit = record.lengthUnit
            defaultRestSeconds = record.defaultRestSeconds
            weekStart = record.weekStart
            theme = record.theme
            accent = record.accent
            loading = false
            UserDefaults.standard.set(useArabicDigits, forKey: "useArabicDigits")
        } catch { loading = false; saveError = "تعذر قراءة تفضيلاتك. بياناتك محفوظة؛ حاول مرة أخرى." }
    }
    private func persist() {
        guard !loading, let preferences, let context else { return }
        preferences.useArabicDigits = useArabicDigits
        preferences.weightUnit = weightUnit
        preferences.lengthUnit = lengthUnit
        preferences.defaultRestSeconds = defaultRestSeconds
        preferences.weekStart = weekStart
        preferences.theme = theme
        preferences.accent = accent
        preferences.updatedAt = Date()
        UserDefaults.standard.set(useArabicDigits, forKey: "useArabicDigits")
        do { try context.save(); saveError = nil }
        catch { saveError = "تعذر حفظ الإعدادات. حاول مرة أخرى." }
    }
}

@MainActor enum ArabicFormat {
    static func number(_ value: Double, decimals: Int = 1, arabic: Bool = true) -> String {
        guard value.isFinite else { return "—" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: arabic ? "ar_SA" : "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = decimals
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }
    static func integer(_ value: Int, arabic: Bool = true) -> String { number(Double(value), decimals: 0, arabic: arabic) }
    static func weight(_ kg: Double, settings: AppSettings) -> String {
        number(settings.displayWeight(kg), arabic: settings.useArabicDigits) + " " + settings.weightLabel
    }
    static func date(_ date: Date, arabic: Bool? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_SA")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "d MMMM yyyy"
        let value = formatter.string(from: date)
        let useArabic = arabic ?? (UserDefaults.standard.object(forKey: "useArabicDigits") as? Bool ?? true)
        return digits(value, arabic: useArabic)
    }
    static func duration(_ seconds: TimeInterval, arabic: Bool = true) -> String {
        let total = max(0, Int(seconds))
        let raw = String(format: "%02d:%02d", total / 60, total % 60)
        return digits(raw, arabic: arabic)
    }
    static func digits(_ text: String, arabic: Bool) -> String {
        let western = Array("0123456789"), arabicDigits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(text.map { character in
            if let index = western.firstIndex(of: character) { return arabic ? arabicDigits[index] : character }
            if let index = arabicDigits.firstIndex(of: character) { return arabic ? character : western[index] }
            return character
        })
    }
    static func parse(_ text: String) -> Double? {
        Double(digits(text, arabic: false).replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "٬", with: ""))
    }
}
