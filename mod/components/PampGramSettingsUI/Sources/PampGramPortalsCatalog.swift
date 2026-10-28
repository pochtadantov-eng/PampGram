import Foundation
import UIKit

/// Static catalog of fake Portals Market items. Mirrors the real
/// portals-market Telegram mini-app's structure: 11 collections, 30
/// items with Model/Symbol/Backdrop attributes and rarity percentages,
/// GRAM prices in nano-GRAM. All numbers are frozen — every PampGram
/// build sees the same market.
///
/// Prices live in nano-GRAM (1 GRAM = 1_000_000_000 units) so they map
/// one-to-one onto `fakeTonBalanceNanos`. The Portals Market just
/// relabels the TON balance as GRAM for the duration of the screen.
public enum PampGramPortalsCatalog {
    public struct Collection: Equatable {
        public let name: String
        public let emoji: String
        public let gradientTop: UIColor
        public let gradientBottom: UIColor
        public let supply: Int
        public let floorNanoGram: Int64
        public let volume24hNanoGram: Int64
        public let isNew: Bool
    }

    public struct Item: Equatable, Identifiable {
        public let id: String
        public let collection: String
        public let number: Int
        public let model: String
        public let modelPct10: Int        // tenths of a percent (12 = 1.2%)
        public let symbol: String
        public let symbolPct10: Int
        public let backdrop: String
        public let backdropPct10: Int
        public let priceNanoGram: Int64
        public let emoji: String
        public let gradientTop: UIColor
        public let gradientBottom: UIColor
        public let craftable: Bool
        public let isNew: Bool

        /// Stars rewarded on a full-price purchase. 100 ✦ per 1 GRAM — matches the
        /// on-screen "Вознаграждение 46 950 ✦" at a 469.5 GRAM floor.
        public var rewardStars: Int64 {
            return self.priceNanoGram / 10_000_000
        }
    }

    public static let collections: [Collection] = [
        Collection(name: "Resistance Dog", emoji: "🥷",
                   gradientTop: UIColor(rgb: 0x1F5B6B), gradientBottom: UIColor(rgb: 0x0C2A33),
                   supply: 15_800, floorNanoGram: 469_500_000_000,
                   volume24hNanoGram: 176_500_000_000_000, isNew: true),
        Collection(name: "Heroic Helmet", emoji: "🪖",
                   gradientTop: UIColor(rgb: 0x2C3E52), gradientBottom: UIColor(rgb: 0x101822),
                   supply: 8_000, floorNanoGram: 187_800_000_000,
                   volume24hNanoGram: 2_200_000_000_000, isNew: false),
        Collection(name: "Swiss Watch", emoji: "⌚",
                   gradientTop: UIColor(rgb: 0x3A2E22), gradientBottom: UIColor(rgb: 0x17120D),
                   supply: 50_000, floorNanoGram: 59_500_000_000,
                   volume24hNanoGram: 5_900_000_000_000, isNew: false),
        Collection(name: "Snoop Cigar", emoji: "🚬",
                   gradientTop: UIColor(rgb: 0x3E2550), gradientBottom: UIColor(rgb: 0x180F20),
                   supply: 23_000, floorNanoGram: 39_990_000_000,
                   volume24hNanoGram: 1_400_000_000_000, isNew: false),
        Collection(name: "Rare Bird", emoji: "🦜",
                   gradientTop: UIColor(rgb: 0x225944), gradientBottom: UIColor(rgb: 0x0D2219),
                   supply: 15_000, floorNanoGram: 29_900_000_000,
                   volume24hNanoGram: 2_100_000_000_000, isNew: false),
        Collection(name: "Lucky Locket", emoji: "🏵️",
                   gradientTop: UIColor(rgb: 0x4A2A3A), gradientBottom: UIColor(rgb: 0x1C0F17),
                   supply: 66_000, floorNanoGram: 17_500_000_000,
                   volume24hNanoGram: 6_300_000_000_000, isNew: true),
        Collection(name: "Stellar Rocket", emoji: "🚀",
                   gradientTop: UIColor(rgb: 0x2E3C66), gradientBottom: UIColor(rgb: 0x0F1328),
                   supply: 39_000, floorNanoGram: 15_230_000_000,
                   volume24hNanoGram: 1_800_000_000_000, isNew: false),
        Collection(name: "Sakura Flower", emoji: "🌸",
                   gradientTop: UIColor(rgb: 0x4F2A3B), gradientBottom: UIColor(rgb: 0x1D0E17),
                   supply: 100_000, floorNanoGram: 11_200_000_000,
                   volume24hNanoGram: 1_600_000_000_000, isNew: false),
        Collection(name: "Jingle Bells", emoji: "🔔",
                   gradientTop: UIColor(rgb: 0x4D1E1E), gradientBottom: UIColor(rgb: 0x1B0A0A),
                   supply: 200_000, floorNanoGram: 11_000_000_000,
                   volume24hNanoGram: 959_020_000_000, isNew: false),
        Collection(name: "Pool Float", emoji: "🦆",
                   gradientTop: UIColor(rgb: 0x3B4C1F), gradientBottom: UIColor(rgb: 0x161C0C),
                   supply: 201_000, floorNanoGram: 4_000_000_000,
                   volume24hNanoGram: 420_000_000_000, isNew: false),
        Collection(name: "Ice Cream", emoji: "🍦",
                   gradientTop: UIColor(rgb: 0x4C2537), gradientBottom: UIColor(rgb: 0x1C0D15),
                   supply: 275_000, floorNanoGram: 3_990_000_000,
                   volume24hNanoGram: 320_000_000_000, isNew: false)
    ]

    public static func collection(named name: String) -> Collection? {
        return self.collections.first(where: { $0.name == name })
    }

    public static let items: [Item] = [
        // Resistance Dog
        mk("rd-3353",  "Resistance Dog", 3353,  "Breaker",  12, "Crusader",  5, "Moonstone",      14, 469_500_000_000, craftable: true,  isNew: true),
        mk("rd-12521", "Resistance Dog", 12521, "Rebel",    18, "Revolver",  9, "Dark Pistachio", 11, 469_990_000_000, craftable: true,  isNew: false),
        mk("rd-9965",  "Resistance Dog", 9965,  "Nomad",    22, "Hood",     13, "Ash Grey",       20, 474_900_000_000, craftable: true,  isNew: false),
        mk("rd-18085", "Resistance Dog", 18085, "Spartan",  17, "Shield",    8, "Blood Red",      15, 474_900_000_000, craftable: true,  isNew: false),
        mk("rd-9886",  "Resistance Dog", 9886,  "Vagabond", 24, "Fist",     16, "Deep Teal",      19, 474_900_000_000, craftable: true,  isNew: false),
        mk("rd-220",   "Resistance Dog", 220,   "King",      2, "Crown",     1, "Royal Blue",      3, 1_980_000_000_000, craftable: true, isNew: false),
        // Heroic Helmet
        mk("hh-4420",  "Heroic Helmet", 4420,  "Centurion",  14, "Laurel",   10, "Battlefield Dawn", 18, 187_800_000_000, craftable: false, isNew: false),
        mk("hh-77",    "Heroic Helmet", 77,    "Praetorian",  4, "Lion",      3, "Thunder",           5, 640_000_000_000, craftable: false, isNew: false),
        mk("hh-10211", "Heroic Helmet", 10211, "Berserker",  19, "Sword",    15, "Snow Peak",        22, 198_400_000_000, craftable: false, isNew: false),
        // Swiss Watch
        mk("sw-512",   "Swiss Watch", 512,   "Chronograph",  8, "Gear",      6, "Steel",       11, 59_500_000_000, craftable: false, isNew: false),
        mk("sw-888",   "Swiss Watch", 888,   "Daytona",      3, "Diamond",   2, "Gold Strap",   4, 320_000_000_000, craftable: false, isNew: false),
        mk("sw-20244", "Swiss Watch", 20244, "Classic",     20, "Sapphire", 17, "Leather",     24, 62_300_000_000, craftable: false, isNew: false),
        // Snoop Cigar
        mk("sc-23133", "Snoop Cigar", 23133, "OG",         15, "Smoke", 13, "Lounge",         20, 39_990_000_000, craftable: false, isNew: false),
        mk("sc-187",   "Snoop Cigar", 187,   "West Side",   6, "Flame",  4, "Sunset Strip",    8, 180_000_000_000, craftable: false, isNew: false),
        mk("sc-4040",  "Snoop Cigar", 4040,  "Studio",     18, "Mic",   14, "Stage",          21, 41_200_000_000, craftable: false, isNew: false),
        // Rare Bird
        mk("rb-321",   "Rare Bird", 321,  "Scarlet Macaw",  9, "Feather", 7, "Rainforest", 12, 29_900_000_000, craftable: false, isNew: false),
        mk("rb-8800",  "Rare Bird", 8800, "Peacock",       17, "Nest",   15, "Twilight",   21, 33_500_000_000, craftable: false, isNew: false),
        mk("rb-55",    "Rare Bird", 55,   "Paradise",       3, "Berry",   2, "Dawn",        5, 128_700_000_000, craftable: false, isNew: false),
        // Lucky Locket
        mk("ll-99",    "Lucky Locket", 99,   "Rose Gold",      5, "Clover",    4, "Rose Blush", 7,  17_500_000_000, craftable: false, isNew: true),
        mk("ll-5513",  "Lucky Locket", 5513, "Secret Garden", 19, "Horseshoe",16, "Mint",      22,  18_900_000_000, craftable: false, isNew: true),
        mk("ll-2024",  "Lucky Locket", 2024, "Antique",       14, "Pearl",    11, "Lavender",  18,  19_400_000_000, craftable: false, isNew: true),
        // Stellar Rocket
        mk("sr-39893", "Stellar Rocket", 39893, "Classic",       22, "Thruster", 19, "Launch Pad", 24, 15_230_000_000, craftable: true, isNew: false),
        mk("sr-137",   "Stellar Rocket", 137,   "Interstellar",   6, "Antenna",   4, "Deep Space",  8, 48_900_000_000, craftable: true, isNew: false),
        // Sakura Flower
        mk("sf-4096",  "Sakura Flower", 4096, "Blossom",   15, "Petal",    12, "Pink Mist",   20, 11_200_000_000, craftable: false, isNew: false),
        mk("sf-808",   "Sakura Flower", 808,  "Full Bloom", 8, "Butterfly", 6, "Spring Sky",  10, 14_800_000_000, craftable: false, isNew: false),
        // Jingle Bells
        mk("jb-999",   "Jingle Bells", 999,  "Golden",   8, "Snowflake",  6, "Snowy Night", 10, 11_000_000_000, craftable: false, isNew: false),
        mk("jb-10",    "Jingle Bells", 10,   "Festive",  3, "Ribbon",     2, "Hearth",       4, 45_500_000_000, craftable: false, isNew: false),
        mk("jb-5423",  "Jingle Bells", 5423, "Silver",  22, "Holly",     19, "Pine Forest", 25, 11_300_000_000, craftable: false, isNew: false),
        // Pool Float
        mk("pf-201657", "Pool Float", 201657, "Duck",      21, "Bubble", 19, "Poolside",  24, 4_000_000_000, craftable: false, isNew: false),
        mk("pf-150845", "Pool Float", 150845, "Flamingo",  17, "Palm",   14, "Beach Day", 20, 4_000_000_000, craftable: false, isNew: false),
        // Ice Cream
        mk("ic-275978", "Ice Cream", 275978, "Vanilla",    23, "Sprinkle", 20, "Pastel Pink", 25, 3_990_000_000, craftable: false, isNew: false),
        mk("ic-30011",  "Ice Cream", 30011,  "Mint Chip",  15, "Cherry",   12, "Summer Sky",  19, 5_200_000_000, craftable: false, isNew: false)
    ]

    private static func mk(_ id: String, _ collection: String, _ number: Int,
                           _ model: String, _ modelPct10: Int,
                           _ symbol: String, _ symbolPct10: Int,
                           _ backdrop: String, _ backdropPct10: Int,
                           _ priceNanoGram: Int64,
                           craftable: Bool, isNew: Bool) -> Item {
        let c = collections.first(where: { $0.name == collection })!
        return Item(id: id, collection: collection, number: number,
                    model: model, modelPct10: modelPct10,
                    symbol: symbol, symbolPct10: symbolPct10,
                    backdrop: backdrop, backdropPct10: backdropPct10,
                    priceNanoGram: priceNanoGram, emoji: c.emoji,
                    gradientTop: c.gradientTop, gradientBottom: c.gradientBottom,
                    craftable: craftable, isNew: isNew)
    }

    public static func items(in collection: String?) -> [Item] {
        guard let collection else { return self.items }
        return self.items.filter { $0.collection == collection }
    }

    public static func item(id: String) -> Item? {
        return self.items.first(where: { $0.id == id })
    }

    // ----- Formatters -------------------------------------------------------

    /// 469_500_000_000 → "469.5". Drops trailing zeros, keeps up to 2 decimals.
    public static func formatGram(_ nanoGram: Int64) -> String {
        let value = Double(nanoGram) / 1_000_000_000.0
        if abs(value - value.rounded()) < 0.005 {
            return String(format: "%.0f", value)
        }
        if abs(value * 10 - (value * 10).rounded()) < 0.005 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    /// 15800 → "15.8K", 200000 → "200K", 1_000_000 → "1M".
    public static func formatCompact(_ value: Int) -> String {
        if value >= 1_000_000 {
            let m = Double(value) / 1_000_000.0
            if abs(m - m.rounded()) < 0.05 {
                return String(format: "%.0fM", m)
            }
            return String(format: "%.1fM", m)
        }
        if value >= 1000 {
            let k = Double(value) / 1000.0
            if abs(k - k.rounded()) < 0.05 {
                return String(format: "%.0fK", k)
            }
            return String(format: "%.1fK", k)
        }
        return "\(value)"
    }

    /// 46950 → "46 950" (NBSP-grouped, matches the Russian format in the UI).
    public static func formatStars(_ stars: Int64) -> String {
        let s = String(abs(stars))
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0 && (s.count - i) % 3 == 0 {
                out.append(" ")
            }
            out.append(ch)
        }
        return (stars < 0 ? "-" : "") + out
    }
}

// Local convenience init matching the one from TelegramPresentationData's UIColor+Palette, so
// the catalog file does not need to depend on that submodule for compile-only color literals.
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
