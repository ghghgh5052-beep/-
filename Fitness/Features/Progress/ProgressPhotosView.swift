import SwiftUI
import SwiftData
import PhotosUI
import LocalAuthentication
import ImageIO

@MainActor struct ProgressPhotosView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUnlocked = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selected: [UUID] = []
    @State private var showComparison = false
    @State private var deletePhoto: ProgressPhoto?
    private var canView: Bool { !settings.photoLockEnabled || isUnlocked }
    var body: some View {
        Group {
            if canView {
                ScrollView {
                    if photos.isEmpty { EmptyState(title: "شاهد تقدمك بهدوء", message: "صورك خاصة وتُحفظ داخل بيانات التطبيق. اختر صورة لبدء سجل التقدم.", symbol: "photo.on.rectangle") }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 16) {
                        ForEach(photos) { photo in
                            VStack(alignment: .leading, spacing: 8) {
                                if let data = photo.imageData, let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(height: 180).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(alignment: .topTrailing) { if selected.contains(photo.id) { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(settings.color).padding(8) } }
                                }
                                Text(ArabicFormat.date(photo.date)).font(.caption)
                                if !photo.notes.isEmpty { Text(photo.notes).font(.caption).lineLimit(2) }
                            }.contentShape(Rectangle()).onTapGesture { toggle(photo.id) }
                                .contextMenu { Button("حذف الصورة", role: .destructive) { deletePhoto = photo } }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("صورة بتاريخ " + ArabicFormat.date(photo.date))
                        }
                    }.padding()
                    if loading { SwiftUI.ProgressView("جارٍ حفظ الصورة…") }
                    if selected.count == 2 { Button("مقارنة الصورتين") { showComparison = true }.buttonStyle(WateeraButtonStyle(color: .accentColor)).padding() }
                    if !photos.isEmpty { Text("اختر صورتين للمقارنة. اضغط مطولًا لحذف صورة.").font(.caption).foregroundStyle(.secondary).padding() }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield").font(.system(size: 52)).foregroundStyle(settings.color)
                    Text("صورك خاصة").font(.title2.bold())
                    Button("فتح الصور") { Task { await unlock() } }.buttonStyle(WateeraButtonStyle(color: .accentColor))
                }
            }
        }.wateeraCanvas().navigationTitle("صور التقدم")
            .toolbar { if canView { PhotosPicker(selection: $pickerItem, matching: .images) { Label("إضافة صورة", systemImage: "plus") } } }
            .task { if settings.photoLockEnabled { await unlock() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { isUnlocked = false; showComparison = false; selected = [] } }
            .onChange(of: pickerItem) { _, item in Task { await load(item) } }
            .sheet(isPresented: $showComparison) {
                NavigationStack {
                    ScrollView {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(photos.filter { selected.contains($0.id) }.sorted { $0.date < $1.date }) { photo in
                                VStack {
                                    if let data = photo.imageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
                                    Text(ArabicFormat.date(photo.date)).font(.caption)
                                }.frame(maxWidth: .infinity)
                            }
                        }.padding()
                    }.wateeraCanvas().navigationTitle("مقارنة التقدم").toolbar { Button("تم") { showComparison = false } }
                }.environment(\.layoutDirection, .rightToLeft)
            }
            .confirmationDialog("حذف الصورة نهائيًا؟", isPresented: Binding(get: { deletePhoto != nil }, set: { if !$0 { deletePhoto = nil } })) {
                Button("حذف الصورة", role: .destructive) {
                    if let photo = deletePhoto { context.delete(photo); do { try context.save() } catch { errorMessage = "تعذر حذف الصورة." } }
                    deletePhoto = nil
                }
            }.arabicError($errorMessage)
    }
    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.removeAll { $0 == id } }
        else { if selected.count == 2 { selected.removeFirst() }; selected.append(id) }
    }
    private func unlock() async {
        let authentication = LAContext()
        authentication.localizedCancelTitle = "إلغاء"
        do { isUnlocked = try await authentication.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "افتح صور تقدمك الخاصة") }
        catch { isUnlocked = false }
    }
    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        loading = true
        defer { loading = false; pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
                  let compressed = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.88) else {
                errorMessage = "تعذر قراءة الصورة. اختر صورة محفوظة على الجهاز."; return
            }
            context.insert(ProgressPhoto(imageData: compressed))
            try context.save()
        } catch { errorMessage = "تعذر حفظ الصورة. قد تحتاج الصورة إلى التنزيل من مكتبة الصور أولًا." }
    }
}
