import Foundation

/// Extracts an 11-character YouTube video ID from a URL or a raw ID.
public enum YouTubeVideoID {
    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))

    public static func parse(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let id = validated(trimmed) { return id }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme) else { return nil }

        let host = url.host?.lowercased() ?? ""
        if host.contains("youtu.be") {
            return validated(url.path.split(separator: "/").first.map(String.init))
        }

        let parts = url.path.split(separator: "/").map(String.init)
        for marker in ["shorts", "live", "embed", "v"] {
            if let index = parts.firstIndex(of: marker), parts.indices.contains(index + 1) {
                return validated(parts[index + 1])
            }
        }

        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let value = items.first(where: { $0.name == "v" })?.value {
            return validated(value)
        }

        return nil
    }

    private static func validated(_ id: String?) -> String? {
        guard let id, id.count == 11, id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return id
    }
}
