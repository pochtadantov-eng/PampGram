import Foundation

/// The rates behind every number of the fake CryptoBot: the wallet's prices and day changes, the
/// exchange's ticker and order book, the swap's rate. They are real: Binance's public market-data
/// API is polled every few seconds while a page is open (no key, no account, nothing is sent
/// except the symbol). Where the network or a symbol is not there, the last value keeps drifting by
/// small random steps, so the page never freezes.

struct PampGramFakeCryptoBotQuote {
    /// In dollars (the USDT pairs are taken as dollars).
    var price: Double
    /// The change over 24 hours, in dollars per coin, and in percent.
    var change: Double
    var changePercent: Double
    /// What was traded over 24 hours, in USDT. Scaled down: the real exchange is CryptoBot's own, thinner market.
    var volume: Double
}

struct PampGramFakeCryptoBotBookLevel {
    let price: Double
    let amount: Double
}

/// Both sides, best price first.
struct PampGramFakeCryptoBotBook {
    var bids: [PampGramFakeCryptoBotBookLevel]
    var asks: [PampGramFakeCryptoBotBookLevel]
}

func pampGramFakeCryptoBotIsStableCoin(_ code: String) -> Bool {
    return code == "USDT" || code == "USDC"
}

final class PampGramFakeCryptoBotMarket {
    static let shared = PampGramFakeCryptoBotMarket()

    /// Binance symbols, by the coin's code in the fake app (GRAM is Toncoin renamed).
    private static let symbols: [String: String] = [
        "GRAM": "TONUSDT", "SOL": "SOLUSDT", "TRX": "TRXUSDT", "BTC": "BTCUSDT", "ETH": "ETHUSDT",
        "DOGE": "DOGEUSDT", "LTC": "LTCUSDT", "BNB": "BNBUSDT", "USDC": "USDCUSDT", "XAUT": "XAUTUSDT"
    ]
    private static let hosts = ["https://data-api.binance.vision", "https://api.binance.com", "https://api1.binance.com"]
    private static let volumeScale = 0.0002
    private static let depthScale = 0.002

    private(set) var quotes: [String: PampGramFakeCryptoBotQuote] = [:]
    /// The price a coin started the session at, the centre its simulated drift stays near.
    private var anchors: [String: PampGramFakeCryptoBotQuote] = [:]
    private var lastLiveUpdate: [String: Date] = [:]
    private var observers: [Int: () -> Void] = [:]
    private var nextObserverId = 0
    private var timer: Foundation.Timer?
    private var hostIndex = 0
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6.0
        configuration.timeoutIntervalForResource = 8.0
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
        for currency in pampGramFakeCryptoBotCurrencies {
            let jitter = Double.random(in: -0.004 ... 0.004) * (pampGramFakeCryptoBotIsStableCoin(currency.code) ? 0.05 : 1.0)
            let price = currency.price * (1.0 + jitter)
            let quote = PampGramFakeCryptoBotQuote(price: price, change: price * currency.change / 100.0, changePercent: currency.change + jitter * 100.0, volume: PampGramFakeCryptoBotMarket.baselineVolume(currency.code))
            self.quotes[currency.code] = quote
            self.anchors[currency.code] = quote
        }
    }

    private static func baselineVolume(_ code: String) -> Double {
        switch code {
        case "USDC": return 32889.73
        case "BTC": return 481530.4
        case "ETH": return 215882.15
        case "GRAM": return 96214.7
        default: return 18400.0
        }
    }

    func quote(_ code: String) -> PampGramFakeCryptoBotQuote {
        if let quote = self.quotes[code] {
            return quote
        }
        return PampGramFakeCryptoBotQuote(price: 1.0, change: 0.0, changePercent: 0.0, volume: 0.0)
    }

    // MARK: Observers

    /// Starts the polling with the first observer and stops it with the last one.
    func addObserver(_ block: @escaping () -> Void) -> Int {
        let id = self.nextObserverId
        self.nextObserverId += 1
        self.observers[id] = block
        if self.timer == nil {
            let timer = Foundation.Timer(timeInterval: 4.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            self.refresh()
        }
        return id
    }

    func removeObserver(_ id: Int) {
        self.observers.removeValue(forKey: id)
        if self.observers.isEmpty {
            self.timer?.invalidate()
            self.timer = nil
        }
    }

    private func notify() {
        for block in Array(self.observers.values) {
            block()
        }
    }

    private func tick() {
        self.refresh()
        // Anything the network did not refresh for a while drifts a little by itself.
        let now = Date()
        for currency in pampGramFakeCryptoBotCurrencies {
            let code = currency.code
            if let updated = self.lastLiveUpdate[code], now.timeIntervalSince(updated) < 12.0 {
                continue
            }
            self.drift(code)
        }
        self.notify()
    }

    private func drift(_ code: String) {
        guard var quote = self.quotes[code], let anchor = self.anchors[code] else {
            return
        }
        let stable = pampGramFakeCryptoBotIsStableCoin(code)
        let step = Double.random(in: -(stable ? 0.00004 : 0.0007) ... (stable ? 0.00004 : 0.0007))
        var price = quote.price * (1.0 + step)
        let low = anchor.price * (stable ? 0.9995 : 0.985)
        let high = anchor.price * (stable ? 1.0005 : 1.015)
        if price < low || price > high {
            price = quote.price * (1.0 - step)
        }
        quote.price = price
        quote.changePercent = anchor.changePercent + (price / anchor.price - 1.0) * 100.0
        quote.change = anchor.change + (price - anchor.price)
        self.quotes[code] = quote
    }

    // MARK: Network

    private func url(_ path: String, query: String) -> URL? {
        let host = PampGramFakeCryptoBotMarket.hosts[self.hostIndex % PampGramFakeCryptoBotMarket.hosts.count]
        return URL(string: host + path + "?" + query)
    }

    /// One request per coin: a symbol the exchange does not list must not break the others.
    func refresh() {
        for (code, symbol) in PampGramFakeCryptoBotMarket.symbols {
            guard let url = self.url("/api/v3/ticker/24hr", query: "symbol=" + symbol) else {
                continue
            }
            self.session.dataTask(with: url) { [weak self] data, response, error in
                var parsed: PampGramFakeCryptoBotQuote?
                if error == nil, let data = data, let status = (response as? HTTPURLResponse)?.statusCode, status == 200,
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let last = Double(object["lastPrice"] as? String ?? ""),
                   last > 0.0 {
                    let change = Double(object["priceChange"] as? String ?? "") ?? 0.0
                    let percent = Double(object["priceChangePercent"] as? String ?? "") ?? 0.0
                    let volume = Double(object["quoteVolume"] as? String ?? "") ?? 0.0
                    parsed = PampGramFakeCryptoBotQuote(price: last, change: change, changePercent: percent, volume: volume * PampGramFakeCryptoBotMarket.volumeScale)
                }
                DispatchQueue.main.async {
                    guard let self = self else {
                        return
                    }
                    if let parsed = parsed {
                        self.quotes[code] = parsed
                        self.anchors[code] = parsed
                        self.lastLiveUpdate[code] = Date()
                        self.notify()
                    } else if error != nil {
                        // The next try goes to another host.
                        self.hostIndex += 1
                    }
                }
            }.resume()
        }
    }

    /// The order book of `code`/USDT. `nil` when the network has none; the caller then draws a made-up one.
    func fetchBook(code: String, completion: @escaping (PampGramFakeCryptoBotBook?) -> Void) {
        guard let symbol = PampGramFakeCryptoBotMarket.symbols[code], let url = self.url("/api/v3/depth", query: "symbol=" + symbol + "&limit=500") else {
            completion(nil)
            return
        }
        self.session.dataTask(with: url) { data, response, error in
            var book: PampGramFakeCryptoBotBook?
            if error == nil, let data = data, let status = (response as? HTTPURLResponse)?.statusCode, status == 200,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                func levels(_ key: String) -> [PampGramFakeCryptoBotBookLevel] {
                    var result: [PampGramFakeCryptoBotBookLevel] = []
                    for item in object[key] as? [[Any]] ?? [] {
                        if item.count >= 2, let price = Double(item[0] as? String ?? ""), let amount = Double(item[1] as? String ?? ""), price > 0.0, amount > 0.0 {
                            result.append(PampGramFakeCryptoBotBookLevel(price: price, amount: amount * PampGramFakeCryptoBotMarket.depthScale))
                        }
                    }
                    return result
                }
                let bids = levels("bids")
                let asks = levels("asks")
                if !bids.isEmpty && !asks.isEmpty {
                    book = PampGramFakeCryptoBotBook(bids: bids, asks: asks)
                }
            }
            DispatchQueue.main.async {
                completion(book)
            }
        }.resume()
    }

    /// A believable book around `price` for when the real one is not reachable.
    func syntheticBook(code: String, price: Double) -> PampGramFakeCryptoBotBook {
        let stable = pampGramFakeCryptoBotIsStableCoin(code)
        let spacing = price * (stable ? 0.00012 : 0.0002)
        var bids: [PampGramFakeCryptoBotBookLevel] = []
        var asks: [PampGramFakeCryptoBotBookLevel] = []
        for _ in 0 ..< 120 {
            let gap = spacing * (1.0 + Double.random(in: 0.0 ... 1.5))
            let bidPrice = (bids.last?.price ?? price) - gap
            let askPrice = (asks.last?.price ?? price) + gap
            let notional = pow(10.0, Double.random(in: 0.0 ... 4.2))
            let amount = notional / price
            bids.append(PampGramFakeCryptoBotBookLevel(price: max(bidPrice, spacing), amount: amount))
            asks.append(PampGramFakeCryptoBotBookLevel(price: askPrice, amount: pow(10.0, Double.random(in: 0.0 ... 4.2)) / price))
        }
        return PampGramFakeCryptoBotBook(bids: bids, asks: asks)
    }
}

// MARK: - Number formatting shared by the market screens

/// "1.01", "0.9959": at most `decimals` places, the trailing zeros cut.
func pampGramFakeCryptoBotTrimmed(_ value: Double, decimals: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = max(0, decimals)
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSNumber(value: value)) ?? "0"
}

/// "32 889.73": thousands apart by spaces, always `decimals` places.
func pampGramFakeCryptoBotGrouped(_ value: Double, decimals: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = decimals
    formatter.maximumFractionDigits = decimals
    formatter.groupingSeparator = " "
    formatter.usesGroupingSeparator = true
    return formatter.string(from: NSNumber(value: value)) ?? "0"
}

/// The order book's amounts: "882.38", "14.97K", "8.27K", "1.2M".
func pampGramFakeCryptoBotCompact(_ value: Double) -> String {
    if value >= 1_000_000.0 {
        return pampGramFakeCryptoBotTrimmed(value / 1_000_000.0, decimals: 2) + "M"
    }
    if value >= 1000.0 {
        return pampGramFakeCryptoBotTrimmed(value / 1000.0, decimals: 2) + "K"
    }
    return pampGramFakeCryptoBotGrouped(value, decimals: 2).replacingOccurrences(of: " ", with: "")
}
