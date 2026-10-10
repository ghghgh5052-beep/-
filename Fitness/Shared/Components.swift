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
                .font(compact ? .caption : .subheadline).foregroundStyle(.secondary)
                .lineLimit(compact ? 2 : nil)
                .frame(minHeight: compact ? 28 : nil, alignment: .leading)
            Text(value).font(compact ? .headline : .title2.bold()).minimumScaleFactor(0.65).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 10 : 16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + "، " + value)
    }
}

@MainActor struct EmptyState: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .padding(.vertical, 20)
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
