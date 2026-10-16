import Foundation
import TelegramCore

/// Telegram's gift titles come from the server in English, so the search also understands a few
/// Russian words people actually type for the well-known ones.
let pampGramGiftSearchAliases: [(words: [String], fragment: String)] = [
    (["ролекс", "часы", "часики"], "watch"),
    (["пепе", "пепа", "лягушка"], "pepe"),
    (["кольцо", "перстень", "печатка"], "ring"),
    (["кепка", "шапка"], "cap"),
    (["сердце", "медальон"], "locket"),
    (["торт", "тортик"], "cake"),
    (["мишка", "медведь"], "bear"),
    (["ракета"], "rocket"),
    (["роза", "цветок", "цветы"], "rose"),
    (["персик"], "peach"),
    (["шар", "шарик"], "balloon"),
    (["кубок"], "cup")
]

func pampGramGiftMatches(_ gift: StarGift.Gift, query: String) -> Bool {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if query.isEmpty {
        return true
    }
    let title = (gift.title ?? "").lowercased()
    if title.contains(query) {
        return true
    }
    for alias in pampGramGiftSearchAliases {
        if alias.words.contains(where: { $0.hasPrefix(query) || query.hasPrefix($0) }) && title.contains(alias.fragment) {
            return true
        }
    }
    return false
}
