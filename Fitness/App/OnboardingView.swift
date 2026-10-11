import SwiftUI

@MainActor struct OnboardingView: View {
    let finish: () -> Void
    @Environment(AppSettings.self) private var settings
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ZStack {
                    RoundedRectangle(cornerRadius: 36).fill(WateeraDesign.hero)
                    VStack(alignment: .leading, spacing: 22) {
                        Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 56, weight: .light)).foregroundStyle(WateeraDesign.heroAccent).accessibilityHidden(true)
                        Text("وتيرة").font(.largeTitle.bold())
                        Text("خطوة اليوم.\nفرق الغد.").font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(28)
                }.padding(.top, 16)
                Text("مساحتك للتمرّن والتقدّم").font(.title2.bold())
                Text("خطّط أسبوعك، سجّل كل جولة، وشاهد كيف تتطور أرقامك.").font(.body).foregroundStyle(.secondary)
                VStack(spacing: 14) {
                    onboardingRow("خطة على مقاسك", detail: "قوالب قابلة للتعديل وتمارين برسوم واضحة.", icon: "calendar")
                    onboardingRow("تسجيل سريع في النادي", detail: "أوزانك السابقة ومؤقت الراحة في متناولك.", icon: "checkmark.circle")
                    onboardingRow("تقدّم تراه", detail: "رسوم وأرقام شخصية، محفوظة على جهازك.", icon: "chart.xyaxis.line")
                }
                Text(AppBranding.ownerName).font(.caption).foregroundStyle(.secondary).environment(\.layoutDirection, .leftToRight)
            }.padding(24)
        }.safeAreaInset(edge: .bottom) {
            Button("لنبدأ") { finish() }.frame(maxWidth: .infinity).buttonStyle(WateeraButtonStyle(color: settings.color))
                .accessibilityIdentifier("onboarding.finish").padding(20).background(.regularMaterial)
        }.background(WateeraDesign.canvas).environment(\.layoutDirection, .rightToLeft).interactiveDismissDisabled()
    }
    private func onboardingRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(settings.color).frame(width: 36, height: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
