import SwiftUI
import UIKit

@MainActor struct StatCard: View {
    let title: String
    let value: String
    let symbol: String
    var compact = false
    var compactTitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Label(compact ? (compactTitle ?? title) : title, systemImage: symbol)
                .font(compact ? .caption : .subheadline).foregroundStyle(WateeraDesign.brand)
                .lineLimit(compact ? 2 : nil)
                .frame(minHeight: compact ? 28 : nil, alignment: .leading)
            Text(value).font(compact ? .headline : WateeraDesign.TypeStyle.metric).monospacedDigit().minimumScaleFactor(0.75).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wateeraCard(padding: compact ? 12 : 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + "، " + value)
    }
}

@MainActor struct EmptyState: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 34, weight: .medium)).foregroundStyle(WateeraDesign.brand)
                .frame(width: 80, height: 80).background(WateeraDesign.brand.opacity(0.09), in: RoundedRectangle(cornerRadius: 26)).accessibilityHidden(true)
            Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 18)
    }
}

@MainActor struct NumericField: View {
    let title: String
    @Binding var value: String
    var selectOnFocus = false
    @FocusState private var focused: Bool
    var body: some View {
        TextField(title, text: $value)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(title)
            .focused($focused)
            .onChange(of: focused) { _, active in
                guard active && selectOnFocus else { return }
                DispatchQueue.main.async {
                    if focused {
                        UIApplication.shared.sendAction(#selector(UITextField.selectAll(_:)), to: nil, from: nil, for: nil)
                    }
                }
            }
    }
}

extension View {
    func arabicError(_ message: Binding<String?>) -> some View {
        alert("تعذر إكمال العملية", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("حسنًا", role: .cancel) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "حاول مرة أخرى.") }
    }
}
