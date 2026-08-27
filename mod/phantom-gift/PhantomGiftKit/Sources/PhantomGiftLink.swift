import Foundation

/// Encodes/decodes the `phantomgift://` link that carries a `PhantomGiftPayload` inside
/// a normal chat message. This scheme is never resolved by real Telegram clients or
/// servers — the app-wide URL handler in `OpenUrl.swift` intercepts it before it would
/// otherwise fall through to "open externally", so on a stock Telegram it is inert.
public enum PhantomGiftLink {
    public static let scheme = "phantomgift"

    public static func urlString(for payload: PhantomGiftPayload) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else {
            return nil
        }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(scheme)://send?d=\(encoded)"
    }

    public static func payload(from url: URL) -> PhantomGiftPayload? {
        guard url.scheme?.lowercased() == scheme else {
            return nil
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard let encoded = components.queryItems?.first(where: { $0.name == "d" })?.value else {
            return nil
        }
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64) else {
            return nil
        }
        return try? JSONDecoder().decode(PhantomGiftPayload.self, from: data)
    }
}
