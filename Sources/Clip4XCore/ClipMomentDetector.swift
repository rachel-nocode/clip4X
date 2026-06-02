import Foundation

public struct ClipMomentDetector: Sendable {
    public var minDuration: Double
    public var maxDuration: Double
    public var maxClips: Int

    public init(minDuration: Double = 18, maxDuration: Double = 62, maxClips: Int = 8) {
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.maxClips = maxClips
    }

    public func detect(in segments: [TranscriptSegment], sourceDuration: Double) -> [ClipCandidate] {
        let ordered = segments.sorted { $0.start < $1.start }
        guard !ordered.isEmpty else { return [] }

        var candidates: [ClipCandidate] = []
        for startIndex in ordered.indices {
            let start = max(0, ordered[startIndex].start - 0.5)
            var endIndex = startIndex

            while endIndex < ordered.endIndex - 1,
                  ordered[endIndex].end - start < minDuration {
                endIndex += 1
            }

            while endIndex < ordered.endIndex - 1,
                  ordered[endIndex].end - start < maxDuration,
                  shouldExtendAfter(ordered[endIndex].text) {
                endIndex += 1
            }

            let window = Array(ordered[startIndex...endIndex])
            guard let last = window.last else { continue }
            let end = min(sourceDuration, last.end + 0.5)
            let duration = end - start
            guard duration >= 8, duration <= maxDuration + 4 else { continue }

            let text = window.map(\.text).joined(separator: " ")
            let score = scoreWindow(text: text, duration: duration, startsStrong: startsStrong(text))
            let keywords = topKeywords(in: text, limit: 3)
            let theme = keywords.isEmpty ? "general" : keywords.joined(separator: ", ")
            let title = hookTitle(from: text, fallback: theme)
            let reason = reasonFor(text: text, duration: duration, score: score)

            candidates.append(ClipCandidate(
                title: title,
                theme: theme,
                reason: reason,
                start: start,
                end: end,
                score: score,
                transcript: window,
                isSelected: candidates.count < 4
            ))
        }

        let ranked = candidates.sorted {
            if $0.score == $1.score { return $0.duration > $1.duration }
            return $0.score > $1.score
        }

        var picked: [ClipCandidate] = []
        for candidate in ranked {
            guard picked.allSatisfy({ overlapRatio($0, candidate) < 0.45 }) else { continue }
            picked.append(candidate)
            if picked.count == maxClips { break }
        }

        if picked.isEmpty, let first = ordered.first, let last = ordered.last {
            let window = ordered
            let text = window.map(\.text).joined(separator: " ")
            return [ClipCandidate(
                title: hookTitle(from: text, fallback: "clip"),
                theme: topKeywords(in: text, limit: 3).joined(separator: ", "),
                reason: "Best available continuous section.",
                start: first.start,
                end: min(sourceDuration, last.end),
                score: 50,
                transcript: window,
                isSelected: true
            )]
        }

        return picked.sorted { $0.start < $1.start }
    }

    private func scoreWindow(text: String, duration: Double, startsStrong: Bool) -> Int {
        let lower = normalized(text)
        var score = 40

        let hookTerms = [
            "you can", "here's", "here is", "the problem", "i found", "what if",
            "instead", "actually", "because", "better", "free", "so you don't have to",
            "mistake", "faster", "clean", "this is why", "the catch", "watch this"
        ]
        score += hookTerms.reduce(0) { $0 + (lower.contains($1) ? 5 : 0) }

        let contrastTerms = ["but", "instead", "however", "except", "the catch", "the problem"]
        score += contrastTerms.reduce(0) { $0 + (lower.contains(" \($1) ") ? 4 : 0) }

        if lower.contains("you") { score += 6 }
        if lower.contains("because") { score += 5 }
        if startsStrong { score += 10 }

        let idealDuration = 38.0
        let distance = abs(duration - idealDuration)
        score += max(0, 18 - Int(distance / 2))

        let fillerCount = [" um ", " uh ", " like ", " kind of ", " sort of "]
            .reduce(0) { $0 + lower.components(separatedBy: $1).count - 1 }
        score -= fillerCount * 2

        return max(1, min(100, score))
    }

    private func startsStrong(_ text: String) -> Bool {
        let lower = normalized(text)
        return [
            "if you", "here's", "here is", "this is", "i found",
            "the fastest", "the easiest", "stop", "you can"
        ].contains { lower.hasPrefix($0) }
    }

    private func shouldExtendAfter(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return true }
        return ![".", "!", "?"].contains(last)
    }

    private func topKeywords(in text: String, limit: Int) -> [String] {
        let stopwords: Set<String> = [
            "the", "and", "that", "this", "with", "you", "your", "for", "are", "was",
            "but", "not", "have", "just", "like", "from", "they", "then", "than",
            "can", "get", "one", "all", "out", "really", "actually", "because",
            "about", "into", "when", "what", "there", "here", "going", "make"
        ]
        let words = normalized(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 3 && !stopwords.contains($0) }

        let counts = Dictionary(grouping: words, by: { $0 }).mapValues(\.count)
        return counts.sorted {
            if $0.value == $1.value { return $0.key < $1.key }
            return $0.value > $1.value
        }
        .prefix(limit)
        .map(\.key)
    }

    private func hookTitle(from text: String, fallback: String) -> String {
        let firstSentence = text
            .split(whereSeparator: { ".!?".contains($0) })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let source = firstSentence?.isEmpty == false ? firstSentence! : fallback
        let words = source.split(separator: " ").prefix(9).map(String.init)
        let title = words.joined(separator: " ")
        return title.isEmpty ? "clip" : title
    }

    private func reasonFor(text: String, duration: Double, score: Int) -> String {
        var reasons: [String] = []
        let lower = normalized(text)
        if lower.contains("you") { reasons.append("viewer-facing") }
        if lower.contains("but") || lower.contains("instead") { reasons.append("contrast") }
        if lower.contains("because") { reasons.append("clear payoff") }
        if duration >= 25 && duration <= 50 { reasons.append("tight length") }
        if reasons.isEmpty { reasons.append("cohesive section") }
        return "\(score)/100: " + reasons.prefix(3).joined(separator: ", ")
    }

    private func overlapRatio(_ lhs: ClipCandidate, _ rhs: ClipCandidate) -> Double {
        let overlap = max(0, min(lhs.end, rhs.end) - max(lhs.start, rhs.start))
        let shorter = max(1, min(lhs.duration, rhs.duration))
        return overlap / shorter
    }

    private func normalized(_ text: String) -> String {
        " " + text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + " "
    }
}
