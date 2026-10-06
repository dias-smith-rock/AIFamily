import Foundation

enum TrackedDevicePairingCode {
    static func parse(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if let fromURL = codeFromTrackURL(trimmed) {
            return fromURL
        }

        let compact = trimmed.uppercased().filter(\.isAlphanumeric)
        if compact.count == 6 {
            return compact
        }
        if compact.contains("TRACKCODE"), compact.count >= 6 {
            return String(compact.suffix(6))
        }

        let pattern = "\\b[A-Z0-9]{6}\\b"
        guard let range = compact.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(compact[range])
    }

    private static func codeFromTrackURL(_ raw: String) -> String? {
        guard let url = URL(string: raw),
              url.scheme?.caseInsensitiveCompare("wefamily") == .orderedSame,
              (url.host?.caseInsensitiveCompare("track") == .orderedSame
                || url.path.lowercased().contains("track"))
        else {
            return nil
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let value = items?.first(where: { $0.name.caseInsensitiveCompare("code") == .orderedSame })?.value
        let normalized = value?.uppercased().filter(\.isAlphanumeric) ?? ""
        guard normalized.count == 6 else { return nil }
        return normalized
    }
}

private extension Character {
    var isAlphanumeric: Bool {
        isLetter || isNumber
    }
}
