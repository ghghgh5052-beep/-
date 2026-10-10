import SwiftUI

enum AppBranding {
    static let ownerName = "Coach : 3BIID - AB"
}

@MainActor struct AboutView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(settings.color)
                        .frame(width: 72, height: 72)
                        .background(settings.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityHidden(true)
                    Text("وتيرة").font(.largeTitle.bold())
                    Text("مخطط تمرينك، وسجل تقدمك.").foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
            }
            Section("ملكية التطبيق") {
                VStack(alignment: .leading, spacing: 12) {
                    Label("المدرب وصاحب التطبيق", systemImage: "checkmark.seal.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(AppBranding.ownerName).font(.title3.weight(.semibold))
                        .environment(\.layoutDirection, .leftToRight)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("app.owner.name")
                    Text("حقوق التطبيق واسمه محفوظة لصاحبه.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            Section("الرسوم التوضيحية") {
                Text("رسوم تشريحية أصلية أُعدّت خصيصًا لوتيرة، توضّح وضعيات التنفيذ وأدوات التمرين.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("الصور محفوظة داخل التطبيق ومتاحة دون اتصال. يمكنك فتحها بالحجم الكامل وتكبير تفاصيلها.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Text("الإصدار " + ArabicFormat.digits(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0", arabic: settings.useArabicDigits))
                Text("© " + ArabicFormat.integer(Calendar(identifier: .gregorian).component(.year, from: .now), arabic: settings.useArabicDigits) + " — " + AppBranding.ownerName)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("عن وتيرة")
        .navigationBarTitleDisplayMode(.inline)
    }
}
