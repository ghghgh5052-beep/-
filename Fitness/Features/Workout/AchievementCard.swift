import SwiftUI
import UIKit

struct SharedAchievement: Identifiable { let id = UUID(); let image: UIImage }

struct AchievementShareSheet: UIViewControllerRepresentable {
    let achievement: SharedAchievement
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [achievement.image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct AchievementCard: View {
    let title: String
    let date: String
    let duration: String
    let volume: String
    let sets: String
    let records: String
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack { Text("وتيرة").font(.largeTitle.bold()); Spacer(); Image(systemName: "dumbbell.fill").font(.largeTitle) }
            Spacer(minLength: 24)
            Image(systemName: "checkmark.seal.fill").font(.system(size: 66)).foregroundStyle(Color(red: 0.53, green: 0.96, blue: 0.77))
            Text("خطوة جديدة\nنحو هدفك").font(.system(size: 42, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(title).font(.title2.bold())
            Text(date).font(.body).foregroundStyle(.white.opacity(0.8))
            Divider().overlay(.white.opacity(0.4))
            HStack(spacing: 24) {
                shareMetric("المدة", duration); shareMetric("الجولات", sets); shareMetric("الحجم", volume)
            }
            if records != "" { Label(records + " أرقام شخصية جديدة", systemImage: "trophy.fill").font(.headline).foregroundStyle(Color(red: 0.98, green: 0.84, blue: 0.54)) }
            Spacer(minLength: 12)
            Text(AppBranding.ownerName).font(.footnote).environment(\.layoutDirection, .leftToRight)
        }.foregroundStyle(.white).padding(36).frame(width: 600, height: 800).background(WateeraDesign.hero)
            .environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "ar_SA"))
    }
    private func shareMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.caption).foregroundStyle(.white.opacity(0.75)); Text(value).font(.title3.bold()).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompletionBadge: View {
    let celebrate: Bool
    let hasRecords: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        ZStack {
            Circle().fill(WateeraDesign.brand.opacity(0.1)).frame(width: 96, height: 96)
            if hasRecords {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(WateeraDesign.gold).offset(x: 44, y: -32).accessibilityHidden(true)
                Image(systemName: "sparkle").font(.subheadline).foregroundStyle(WateeraDesign.brand).offset(x: -42, y: 28).accessibilityHidden(true)
            }
            Image(systemName: hasRecords ? "trophy.fill" : "checkmark.seal.fill").font(.system(size: 44, weight: .medium)).foregroundStyle(hasRecords ? WateeraDesign.gold : WateeraDesign.brand)
        }.scaleEffect(!celebrate || appeared || reduceMotion ? 1 : 0.8)
            .onAppear {
                if celebrate {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    if hasRecords { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7) }
                }
                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            }.accessibilityHidden(true)
    }
}
