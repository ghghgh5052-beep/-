import SwiftUI
import UIKit

@MainActor struct ExerciseGuideThumbnail: View {
    let guide: ExerciseGuide

    var body: some View {
        Image(guide.assetName)
            .resizable()
            .renderingMode(guide.isTemplate ? .template : .original)
            .scaledToFit()
            .foregroundStyle(.black)
            .padding(4)
            .frame(width: 88, height: 64)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black.opacity(0.06), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

@MainActor struct ExerciseGuideContent: View {
    @Environment(AppSettings.self) private var settings
    let guide: ExerciseGuide
    let exerciseName: String
    @State private var selectedImage: GuideImageSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(guide.caption).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(guide.assetNames.enumerated()), id: \.offset) { index, assetName in
                VStack(alignment: .leading, spacing: 8) {
                    if guide.assetNames.count > 1 {
                        Text(frameTitle(index)).font(.subheadline.weight(.semibold))
                    }
                    Button {
                        selectedImage = GuideImageSelection(assetName: assetName, title: frameTitle(index), isTemplate: guide.isTemplate)
                    } label: {
                        VStack(spacing: 0) {
                            Image(assetName)
                                .resizable()
                                .renderingMode(guide.isTemplate ? .template : .original)
                                .scaledToFit()
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: guide.assetNames.count > 1 ? 280 : nil)
                                .background(.white)
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                Text("عرض الصورة بالحجم الكامل")
                                Spacer(minLength: 0)
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("صورة \(exerciseName)، \(imageDescription(index))")
                    .accessibilityHint("عرض الصورة وتكبيرها")
                    .accessibilityIdentifier("exercise.guide.image.\(index)")
                }
            }
            if guide.assetNames.count == 1 {
                ExerciseMotionPreview(guide: guide, exerciseName: exerciseName)
            }
            if !guide.cues.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("خطوات التنفيذ").font(.headline)
                    ForEach(Array(guide.cues.enumerated()), id: \.offset) { index, cue in
                        HStack(alignment: .top, spacing: 12) {
                            Text(ArabicFormat.integer(index + 1, arabic: settings.useArabicDigits))
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .foregroundStyle(.tint)
                                .background(Color.accentColor.opacity(0.1), in: Capsule())
                            Text(cue).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let attribution = guide.attribution, !attribution.isEmpty {
                Text(attribution).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fullScreenCover(item: $selectedImage) { selected in
            ExerciseImageViewer(assetName: selected.assetName, exerciseName: exerciseName, frameTitle: selected.title,
                caption: guide.caption,
                isTemplate: selected.isTemplate)
        }
    }

    private func frameTitle(_ index: Int) -> String {
        guard guide.assetNames.count > 1 else { return "طريقة التنفيذ" }
        return index == 0 ? "بداية الحركة" : "نهاية الحركة"
    }

    private func imageDescription(_ index: Int) -> String {
        // The catalog caption distinguishes moving repetitions from setup-and-hold exercises.
        guide.assetNames.count == 1 ? guide.caption : frameTitle(index)
    }
}

@MainActor struct ExerciseGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let guide: ExerciseGuide
    let exerciseName: String

    var body: some View {
        NavigationStack {
            ScrollView {
                ExerciseGuideContent(guide: guide, exerciseName: exerciseName).padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }.frame(minHeight: 44)
                        .accessibilityIdentifier("exercise.guide.done")
                }
            }
        }
    }
}

private struct GuideImageSelection: Identifiable {
    let assetName: String
    let title: String
    let isTemplate: Bool
    var id: String { assetName }
}

@MainActor private struct ExerciseImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let assetName: String
    let exerciseName: String
    let frameTitle: String
    let caption: String
    let isTemplate: Bool
    @State private var zoom: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZoomableExerciseImage(assetName: assetName, caption: "\(exerciseName)، \(frameTitle). \(caption)", isTemplate: isTemplate, zoom: $zoom)
                .background(.black)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 6) {
                        HStack(spacing: 20) {
                            Button { zoom = max(1, zoom / 1.5) } label: {
                                Image(systemName: "minus.magnifyingglass").frame(width: 48, height: 48)
                            }.disabled(zoom <= 1.01).accessibilityLabel("تصغير الصورة")
                            Button { zoom = 1 } label: {
                                Image(systemName: "arrow.counterclockwise").frame(width: 48, height: 48)
                            }
                                .accessibilityLabel("إعادة الصورة إلى حجمها الأصلي")
                            Button { zoom = min(4, zoom * 1.5) } label: {
                                Image(systemName: "plus.magnifyingglass").frame(width: 48, height: 48)
                            }.disabled(zoom >= 3.99).accessibilityLabel("تكبير الصورة")
                        }
                        .font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
                        Text("باعد بإصبعين للتكبير، واسحب لتحريك الصورة")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .frame(maxWidth: .infinity).background(.black)
                }
                .navigationTitle(frameTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("إغلاق") { dismiss() }.frame(minHeight: 44)
                            .accessibilityIdentifier("exercise.guide.image.close")
                    }
                }
        }
    }
}

@MainActor private struct ZoomableExerciseImage: UIViewRepresentable {
    let assetName: String
    let caption: String
    let isTemplate: Bool
    @Binding var zoom: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(zoom: $zoom) }

    func makeUIView(context: Context) -> ExerciseImageScrollView {
        let view = ExerciseImageScrollView(frame: .zero)
        view.delegate = context.coordinator
        view.minimumZoomScale = 1
        view.maximumZoomScale = 4
        view.bouncesZoom = true
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        // Keep the physical start/end positions in the artwork intact in the RTL interface.
        view.semanticContentAttribute = .forceLeftToRight
        view.imageView.semanticContentAttribute = .forceLeftToRight
        view.backgroundColor = .black
        view.imageView.image = UIImage(named: assetName)?.withRenderingMode(isTemplate ? .alwaysTemplate : .alwaysOriginal)
        if isTemplate { view.imageView.tintColor = .black }
        view.imageView.isAccessibilityElement = true
        view.imageView.accessibilityLabel = caption
        view.imageView.accessibilityTraits = .image
        view.onViewportReset = { [weak coordinator = context.coordinator] in
            DispatchQueue.main.async {
                guard let coordinator, abs(coordinator.zoom.wrappedValue - 1) > 0.01 else { return }
                coordinator.zoom.wrappedValue = 1
            }
        }
        return view
    }

    func updateUIView(_ view: ExerciseImageScrollView, context: Context) {
        context.coordinator.zoom = $zoom
        if abs(view.zoomScale - zoom) > 0.01 {
            view.setZoomScale(min(4, max(1, zoom)), animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate {
        var zoom: Binding<CGFloat>
        init(zoom: Binding<CGFloat>) { self.zoom = zoom }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ExerciseImageScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ExerciseImageScrollView)?.centerImage()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            // Publish the final pinch scale rather than each UIKit animation frame.
            zoom.wrappedValue = scale
        }
    }
}

@MainActor private final class ExerciseImageScrollView: UIScrollView {
    let imageView = UIImageView()
    var onViewportReset: (() -> Void)?
    private var viewportSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != viewportSize, bounds.width > 0, bounds.height > 0,
           let imageSize = imageView.image?.size, imageSize.width > 0, imageSize.height > 0 {
            viewportSize = bounds.size
            setZoomScale(1, animated: false)
            let fit = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            imageView.frame = CGRect(origin: .zero, size: CGSize(width: imageSize.width * fit, height: imageSize.height * fit))
            contentSize = imageView.frame.size
            onViewportReset?()
        }
        centerImage()
    }

    func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets { contentInset = insets }
    }
}
