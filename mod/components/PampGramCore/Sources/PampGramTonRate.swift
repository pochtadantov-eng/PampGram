import Foundation

/// Live TON→USD exchange rate for the visual "+888" number's purchase-price fields (see
/// PampGramProfileNumberEditor.swift in PampGramSettingsUI). Both prices shown there are purely
/// cosmetic -- nothing here buys, sells, or moves anything real -- but the user wants the two
/// fields to track an actual market rate instead of being typed in independently: editing the
/// TON amount fills in USD (and vice versa) using CoinGecko's public API, at either today's rate
/// or the rate on the chosen purchase date.
public enum PampGramTonRateService {
    private static let coinId = "the-open-network"
    private static let session = URLSession(configuration: {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 8.0
        return config
    }())

    private static let cacheLock = NSLock()
    // Keyed by "current" for the live rate, or "dd-mm-yyyy" for a historical one. A cached
    // "current" entry is only reused for a few minutes (see `currentRateTTL`); historical
    // entries never change for a given date, so they're cached indefinitely for the process
    // lifetime.
    private static var rateCache: [String: (rate: Double, fetchedAt: Date)] = [:]
    private static let currentRateTTL: TimeInterval = 5 * 60

    /// USD price of 1 TON right now. `completion` always runs on the main queue; `nil` on any
    /// network/parsing failure -- callers should just leave the field the user didn't type in
    /// alone rather than show a wrong number.
    public static func currentRate(completion: @escaping (Double?) -> Void) {
        self.cacheLock.lock()
        if let cached = self.rateCache["current"], Date().timeIntervalSince(cached.fetchedAt) < self.currentRateTTL {
            self.cacheLock.unlock()
            DispatchQueue.main.async { completion(cached.rate) }
            return
        }
        self.cacheLock.unlock()

        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(self.coinId)&vs_currencies=usd") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        self.session.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]],
                  let rate = json[self.coinId]?["usd"], rate > 0 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.cacheLock.lock()
            self.rateCache["current"] = (rate, Date())
            self.cacheLock.unlock()
            DispatchQueue.main.async { completion(rate) }
        }.resume()
    }

    /// USD price of 1 TON on `date`'s calendar day (CoinGecko's own daily-close history, not an
    /// intraday price). Falls back to `nil` the same way `currentRate` does, including for a date
    /// before the coin had trading history.
    public static func historicalRate(date: Date, completion: @escaping (Double?) -> Void) {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateKey = formatter.string(from: date)

        self.cacheLock.lock()
        if let cached = self.rateCache[dateKey] {
            self.cacheLock.unlock()
            DispatchQueue.main.async { completion(cached.rate) }
            return
        }
        self.cacheLock.unlock()

        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/\(self.coinId)/history?date=\(dateKey)&localization=false") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        self.session.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let marketData = json["market_data"] as? [String: Any],
                  let currentPrice = marketData["current_price"] as? [String: Any],
                  let rate = currentPrice["usd"] as? Double, rate > 0 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.cacheLock.lock()
            self.rateCache[dateKey] = (rate, Date())
            self.cacheLock.unlock()
            DispatchQueue.main.async { completion(rate) }
        }.resume()
    }
}
