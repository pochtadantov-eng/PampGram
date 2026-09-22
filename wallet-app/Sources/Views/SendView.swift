import SwiftUI

struct SendView: View {
    @EnvironmentObject var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var showingConfirm = false
    @State private var errorMessage: String?

    private var parsedAmount: Int64? {
        parseTon(amountText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0.0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("TON")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("С «\(store.selectedWallet.title)» на «\(store.otherWallet?.title ?? "—")»")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    } else {
                        Text("Баланс «\(store.selectedWallet.title)»: \(formatTon(store.selectedWallet.balanceNanos)) TON. Локальный перевод внутри приложения — реальные средства не переводятся.")
                    }
                }
            }
            .navigationTitle("Отправить TON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Далее") {
                        showingConfirm = true
                    }
                    .disabled(parsedAmount == nil || parsedAmount == 0)
                }
            }
            .confirmationDialog(
                "Отправить \(formatTon(parsedAmount ?? 0)) TON на «\(store.otherWallet?.title ?? "")»?",
                isPresented: $showingConfirm,
                titleVisibility: .visible
            ) {
                Button("Отправить") {
                    guard let amount = parsedAmount else { return }
                    if store.send(amountNanos: amount) {
                        dismiss()
                    } else {
                        errorMessage = "Недостаточно средств на «\(store.selectedWallet.title)»."
                    }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }
}
