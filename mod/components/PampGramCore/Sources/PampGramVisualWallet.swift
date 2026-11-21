import Foundation
import Postbox
import SwiftSignalKit

/// One local GRAM wallet row shown in Telegram's Money history when «Карточка GRAM» is on.
/// Amounts are nanograms (1 GRAM = 1_000_000_000). Positive = incoming / top-up; negative = send / withdraw.
public struct PampGramVisualWalletTx: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable, Equatable {
        case topUp
        case send
        case receive
        case withdraw
    }

    public let id: Int64
    public let kind: Kind
    public let amountNanos: Int64
    public let date: Int32
    /// Counterparty Telegram peer when the row is a send/receive to a contact.
    public let peerId: PeerId?
    /// Display name / address shown in the history row and on the chat card.
    public let peerTitle: String
    /// Fake wallet address or tx hash groups drawn on cards.
    public let address: String
    public let txHash: String
    /// Dollar value cached at creation (for the chat card / detail sheet).
    public let usdCents: Int64

    public init(
        id: Int64 = Int64.random(in: 1 ... (Int64.max / 4)),
        kind: Kind,
        amountNanos: Int64,
        date: Int32 = Int32(Date().timeIntervalSince1970),
        peerId: PeerId? = nil,
        peerTitle: String,
        address: String = "",
        txHash: String = "",
        usdCents: Int64 = 0
    ) {
        self.id = id
        self.kind = kind
        self.amountNanos = amountNanos
        self.date = date
        self.peerId = peerId
        self.peerTitle = peerTitle
        self.address = address
        self.txHash = txHash.isEmpty ? PampGramVisualWallet.makeHash() : txHash
        self.usdCents = usdCents
    }

    public var isIncoming: Bool {
        switch self.kind {
        case .topUp, .receive:
            return true
        case .send, .withdraw:
            return false
        }
    }
}

private struct PampGramVisualWalletTxList: Codable {
    var items: [PampGramVisualWalletTx]
}

public enum PampGramVisualWallet {
    public static let nanosPerGram: Int64 = 1_000_000_000

    public static func makeHash() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var groups: [String] = []
        for _ in 0 ..< 12 {
            let group = String((0 ..< 4).map { _ in alphabet.randomElement()! })
            groups.append(group)
        }
        return groups.joined(separator: " ")
    }

    public static func makeAddress() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        return "UQ" + String((0 ..< 46).map { _ in alphabet.randomElement()! })
    }

    public static func grams(fromNanos nanos: Int64) -> Double {
        return Double(nanos) / Double(nanosPerGram)
    }

    public static func nanos(fromGrams grams: Double) -> Int64 {
        if !grams.isFinite || grams <= 0.0 {
            return 0
        }
        let value = (grams * Double(nanosPerGram)).rounded()
        if value >= Double(Int64.max) {
            return Int64.max
        }
        return Int64(value)
    }

    /// Formats nanograms the way Money UI shows them: `0,1`, `1`, `5,5` (ru decimal comma).
    public static func formatGrams(_ nanos: Int64, signed: Bool = false) -> String {
        let absolute = abs(nanos)
        let whole = absolute / nanosPerGram
        let fraction = absolute % nanosPerGram
        var text: String
        if fraction == 0 {
            text = "\(whole)"
        } else {
            var frac = String(format: "%09d", fraction)
            while frac.last == "0" {
                frac.removeLast()
            }
            text = "\(whole),\(frac)"
        }
        if signed {
            if nanos > 0 {
                return "+\(text)"
            }
            if nanos < 0 {
                return "-\(text)"
            }
        }
        return text
    }

    public static func formatUsd(cents: Int64) -> String {
        let value = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let body = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "$\(body)"
    }

    /// Rough GRAM→USD using the same ballpark as the screenshots (~$0.11 per GRAM).
    public static func usdCents(forNanos nanos: Int64, rateCentsPerGram: Int64 = 11) -> Int64 {
        let grams = abs(nanos) / nanosPerGram
        let rem = abs(nanos) % nanosPerGram
        let cents = grams * rateCentsPerGram + (rem * rateCentsPerGram) / nanosPerGram
        return nanos >= 0 ? cents : -cents
    }

    public static func all(transaction: Transaction) -> [PampGramVisualWalletTx] {
        let items = transaction.getPreferencesEntry(key: PampGramPreferencesKeys.visualWalletTx)?.get(PampGramVisualWalletTxList.self)?.items ?? []
        return items.sorted(by: { $0.date > $1.date })
    }

    public static func signal(postbox: Postbox) -> Signal<[PampGramVisualWalletTx], NoError> {
        return PampGramSharedSignals.shared(postbox: postbox, name: "visualWalletTx", make: {
            return postbox.preferencesView(keys: [PampGramPreferencesKeys.visualWalletTx])
            |> map { view -> [PampGramVisualWalletTx] in
                let items = view.values[PampGramPreferencesKeys.visualWalletTx]?.get(PampGramVisualWalletTxList.self)?.items ?? []
                return items.sorted(by: { $0.date > $1.date })
            }
        })
    }

    public static func add(transaction: Transaction, tx: PampGramVisualWalletTx) {
        transaction.updatePreferencesEntry(key: PampGramPreferencesKeys.visualWalletTx, { entry in
            var list = entry?.get(PampGramVisualWalletTxList.self) ?? PampGramVisualWalletTxList(items: [])
            list.items.append(tx)
            if list.items.count > 500 {
                list.items.removeFirst(list.items.count - 500)
            }
            return PreferencesEntry(list)
        })
    }

    /// Credits/debits the visual GRAM card balance and appends a history row in one Postbox write.
    @discardableResult
    public static func apply(
        transaction: Transaction,
        kind: PampGramVisualWalletTx.Kind,
        amountNanos: Int64,
        peerId: PeerId? = nil,
        peerTitle: String,
        address: String = ""
    ) -> PampGramVisualWalletTx? {
        guard amountNanos != 0 else {
            return nil
        }
        var state = PampGramProfileVisualStore.state(transaction: transaction)
        var extras = state.visualExtras
        guard extras.cardEnabled else {
            return nil
        }
        let signed: Int64
        switch kind {
        case .topUp, .receive:
            signed = abs(amountNanos)
        case .send, .withdraw:
            signed = -abs(amountNanos)
        }
        let current = extras.resolvedBalanceNanos()
        let next = current.addingReportingOverflow(signed)
        if next.overflow {
            return nil
        }
        if next.partialValue < 0 {
            return nil
        }
        extras.setBalanceNanos(next.partialValue)
        state.visualExtras = extras
        PampGramProfileVisualStore.update(transaction: transaction) { _ in state }
        let tx = PampGramVisualWalletTx(
            kind: kind,
            amountNanos: signed,
            peerId: peerId,
            peerTitle: peerTitle,
            address: address.isEmpty ? (extras.cardAddress.isEmpty ? makeAddress() : extras.cardAddress) : address,
            usdCents: usdCents(forNanos: signed)
        )
        add(transaction: transaction, tx: tx)
        return tx
    }
}

public extension PampGramVisualExtras {
    /// Nanograms shown on the real Money card. Prefers `cardBalanceNanos` once written; otherwise
    /// migrates the legacy whole-GRAM `cardBalance`.
    func resolvedBalanceNanos() -> Int64 {
        if self.cardDidSetNanos {
            return self.cardBalanceNanos
        }
        let result = self.cardBalance.multipliedReportingOverflow(by: PampGramVisualWallet.nanosPerGram)
        return result.overflow ? Int64.max : result.partialValue
    }

    mutating func setBalanceNanos(_ nanos: Int64) {
        self.cardBalanceNanos = max(0, nanos)
        self.cardDidSetNanos = true
        self.cardBalance = max(0, nanos / PampGramVisualWallet.nanosPerGram)
    }
}
