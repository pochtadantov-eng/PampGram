import Foundation

/// One entry in a wallet's own activity list.
struct WalletTransaction: Codable, Equatable, Identifiable {
    let id: UUID
    let outgoing: Bool
    let amountNanos: Int64
    let date: Date

    init(id: UUID = UUID(), outgoing: Bool, amountNanos: Int64, date: Date = Date()) {
        self.id = id
        self.outgoing = outgoing
        self.amountNanos = amountNanos
        self.date = date
    }
}

/// One local, play-money wallet. Nothing here is a real TON wallet: there is no seed
/// phrase, no private key, and no connection to the TON network anywhere in this app —
/// `balanceNanos` is just a number this app stores for itself. See
/// `generatePhantomTonAddress` for why `address` can never receive real TON either.
struct Wallet: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    let address: String
    var balanceNanos: Int64
    var transactions: [WalletTransaction]

    init(id: UUID = UUID(), title: String, address: String = generatePhantomTonAddress(), balanceNanos: Int64 = 0, transactions: [WalletTransaction] = []) {
        self.id = id
        self.title = title
        self.address = address
        self.balanceNanos = balanceNanos
        self.transactions = transactions
    }
}

/// The app's entire local state: exactly two wallets and which one is currently showing.
/// More could be added later, but the app was asked for "send to yourself, to another
/// wallet" — two is the whole feature, so that's all this models.
struct WalletState: Codable, Equatable {
    var wallets: [Wallet]
    var selectedWalletId: UUID

    static func fresh() -> WalletState {
        let first = Wallet(title: "Кошелёк 1")
        let second = Wallet(title: "Кошелёк 2")
        return WalletState(wallets: [first, second], selectedWalletId: first.id)
    }
}

/// A cosmetic, TON-address-shaped string for display only. It uses the real user-friendly
/// TON address layout — 1 flag byte + 1 workchain byte + 32 "account id" bytes + 2 checksum
/// bytes, all base64url, 48 characters — so it reads exactly like a real TonKeeper address
/// at a glance. `0x51 0x00` as the first two bytes lands on the same "UQ" prefix a real
/// non-bounceable mainnet address shows.
///
/// The difference: the last 2 bytes here are random, not the real CRC16-CCITT of the rest,
/// and the 32 "account id" bytes are random too — not derived from any real key, because
/// this app holds no keys at all. Every real TON wallet checks that checksum before letting
/// someone pay an address, so this string fails that check and can never receive real TON —
/// nobody can lose real funds by paying it, and there is no key anywhere that could spend
/// from it even if they tried. This app makes no network calls, period; this function
/// doesn't either.
func generatePhantomTonAddress() -> String {
    var bytes: [UInt8] = [0x51, 0x00]
    bytes.reserveCapacity(36)
    for _ in 0 ..< 34 {
        bytes.append(UInt8.random(in: 0 ... 255))
    }
    let base64 = Data(bytes).base64EncodedString()
    return base64
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
