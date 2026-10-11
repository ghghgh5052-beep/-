import SwiftUI
import UIKit

/// Native start/end playback uses the existing catalog poses, never invents interpolated joint anatomy.
/// The artwork keeps its physical orientation independently of the surrounding RTL controls.
@MainActor struct ExerciseMotionPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let guide: ExerciseGuide
    let exerciseName: String
    @State private var phase = 0
    @State private var playing = false
    private var previewAspect: CGFloat {
        guard let image = UIImage(named: guide.assetName), image.size.height > 0 else { return 0.75 }
        // The container below takes half the wide two-pose artwork; fit its full height.
        return image.size.width / 2 / image.size.height
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("معاينة بداية الحركة ونهايتها", systemImage: "play.rectangle").font(.headline)
            GeometryReader { geometry in
                Image(guide.assetName).resizable().scaledToFit()
                    .frame(width: geometry.size.width * 2)
                    .offset(x: phase == 0 ? -geometry.size.width : 0)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                    .clipped()
            }.aspectRatio(previewAspect, contentMode: .fit).background(.white, in: RoundedRectangle(cornerRadius: 18))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(exerciseName + ": " + (phase == 0 ? "البداية" : "النهاية"))
            Picker("الوضعية", selection: $phase) { Text("البداية").tag(0); Text("النهاية").tag(1) }
                .pickerStyle(.segmented).accessibilityIdentifier("guide.motion.phase")
            Button { playing.toggle() } label: {
                Label(playing ? "إيقاف المعاينة" : "تشغيل المعاينة", systemImage: playing ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered).disabled(reduceMotion).accessibilityIdentifier("guide.motion.play")
            Text(reduceMotion ? "تقليل الحركة مفعّل؛ اختر الوضعية يدويًا." : "معاينة متتابعة للوضعيتين. راجع الصورة الكاملة وخطوات التنفيذ لمسار الحركة.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: playing) {
            guard playing && !reduceMotion else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !Task.isCancelled, playing, scenePhase == .active else { playing = false; return }
                phase = phase == 0 ? 1 : 0
            }
        }
        .onChange(of: scenePhase) { _, value in if value != .active { playing = false } }
        .onChange(of: reduceMotion) { _, value in if value { playing = false } }
        .onDisappear { playing = false }
    }
}
