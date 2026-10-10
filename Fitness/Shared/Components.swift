import SwiftUI

@MainActor struct StatCard: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).minimumScaleFactor(0.65).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
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
    var body: some View {
        TextField(title, text: $value)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(title)
    }
}

extension View {
    func arabicError(_ message: Binding<String?>) -> some View {
        alert("تعذر إكمال العملية", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("حسنًا", role: .cancel) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "حاول مرة أخرى.") }
    }
}
