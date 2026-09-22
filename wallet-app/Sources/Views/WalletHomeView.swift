import SwiftUI

struct WalletHomeView: View {
    @EnvironmentObject var store: WalletStore
    @State private var showingSend = false
    @State private var showingReceive = false
    @State private var showingWalletPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    walletSwitcher
                    balanceCard
                    actionButtons
                    activitySection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PampWallet")
        }
        .sheet(isPresented: $showingSend) {
            SendView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingReceive) {
            ReceiveView(wallet: store.selectedWallet)
        }
        .confirmationDialog("Активный кошелёк", isPresented: $showingWalletPicker, titleVisibility: .visible) {
            ForEach(store.state.wallets) { wallet in
                Button("\(wallet.title) · \(formatTon(wallet.balanceNanos)) TON") {
                    store.selectWallet(id: wallet.id)
                }
            }
        }
    }

    private var walletSwitcher: some View {
        Button {
            showingWalletPicker = true
        } label: {
            HStack {
                Text(store.selectedWallet.title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
        .foregroundColor(.primary)
    }

    private var balanceCard: some View {
        VStack(spacing: 8) {
            Text("Баланс")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.8))
            Text("\(formatTon(store.selectedWallet.balanceNanos)) TON")
                .font(.system(size: 38, weight: .bold, design: .rounded))
            Text(shortAddress(store.selectedWallet.address))
                .font(.footnote.monospaced())
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            LinearGradient(
                colors: [Color(red: 0.0, green: 0.66, blue: 0.95), Color(red: 0.0, green: 0.42, blue: 0.87)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundColor(.white)
        .cornerRadius(24)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            actionButton(title: "Отправить", systemImage: "arrow.up") { showingSend = true }
            actionButton(title: "Получить", systemImage: "arrow.down") { showingReceive = true }
        }
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
        .foregroundColor(.primary)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("АКТИВНОСТЬ")
                .font(.caption)
                .foregroundColor(.secondary)

            if store.selectedWallet.transactions.isEmpty {
                Text("Операций пока нет.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.selectedWallet.transactions.enumerated()), id: \.element.id) { index, tx in
                        if index > 0 {
                            Divider()
                        }
                        HStack {
                            Image(systemName: tx.outgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .foregroundColor(tx.outgoing ? .orange : .green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.outgoing ? "Исходящий перевод" : "Входящий перевод")
                                Text(tx.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(tx.outgoing ? "-" : "+")\(formatTon(tx.amountNanos)) TON")
                                .fontWeight(.medium)
                                .foregroundColor(tx.outgoing ? .primary : .green)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)
            }

            Text("Кошелёк полностью локальный: адрес нигде не зарегистрирован в сети TON, у него нет настоящего ключа, и он не может принять настоящие средства. «Отправить» переводит баланс только между этими двумя кошельками внутри приложения — сеть TON эта функция не трогает.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
