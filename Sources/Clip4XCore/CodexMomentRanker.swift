import Foundation

public struct CodexMomentRanker: Sendable {
    public var codexPath: String

    public init(codexPath: String) {
        self.codexPath = codexPath
    }

    public func rank(
        segments: [TranscriptSegment],
        sourceDuration: Double,
        workDirectory: URL
    ) async throws -> [ClipCandidate] {
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let schemaURL = workDirectory.appendingPathComponent("codex-moments.schema.json")
        let outputURL = workDirectory.appendingPathComponent("codex-moments.json")
        try schema.write(to: schemaURL, atomically: true, encoding: .utf8)

        let prompt = makePrompt(segments: segments, sourceDuration: sourceDuration)
        _ = try await ProcessRunner.run(
            codexPath,
            [
                "exec",
                "--skip-git-repo-check",
                "--sandbox", "read-only",
                "--color", "never",
                "--output-schema", schemaURL.path,
                "--output-last-message", outputURL.path,
                prompt
            ],
            currentDirectory: workDirectory,
            environment: [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            ]
        )

        let data = try Data(contentsOf: outputURL)
        let response = try JSONDecoder().decode(CodexMomentResponse.self, from: data)
        return makeCandidates(from: response.clips, segments: segments, sourceDuration: sourceDuration)
    }

    private func makePrompt(segments: [TranscriptSegment], sourceDuration: Double) -> String {
        let transcript = segments.enumerated().map { index, segment in
            "[\(index)] \(time(segment.start))-\(time(segment.end)): \(segment.text)"
        }.joined(separator: "\n")

        return """
        You are selecting the best short-form viral moments from Rachel's creator video transcript.

        Find moments that are cohesive, self-contained, and about one clear idea. Favor:
        - strong first sentence or obvious hook
        - viewer-facing takeaway
        - contrast, mistake, surprise, demo payoff, or clear opinion
        - clips that can stand alone on TikTok, Instagram, X, and Threads

        Avoid generic setup, rambling, half-thoughts, and moments that need missing visual context.

        Return only JSON matching the provided schema. Pick 3 to 8 clips. Each clip should usually be 20-65 seconds.
        Use exact seconds from the transcript. Titles should be short hook titles, not sentence summaries.

        Source duration: \(String(format: "%.1f", sourceDuration)) seconds

        Transcript:
        \(transcript)
        """
    }

    private func makeCandidates(
        from clips: [CodexMoment],
        segments: [TranscriptSegment],
        sourceDuration: Double
    ) -> [ClipCandidate] {
        let cleaned = clips.compactMap { clip -> ClipCandidate? in
            let start = max(0, min(sourceDuration, clip.start))
            let end = max(start, min(sourceDuration, clip.end))
            guard end - start >= 8 else { return nil }

            let window = segments.filter { segment in
                max(segment.start, start) < min(segment.end, end)
            }
            guard !window.isEmpty else { return nil }

            return ClipCandidate(
                title: clip.title.trimmingCharacters(in: .whitespacesAndNewlines),
                theme: clip.theme.trimmingCharacters(in: .whitespacesAndNewlines),
                reason: "Codex \(clip.score)/100: \(clip.reason.trimmingCharacters(in: .whitespacesAndNewlines))",
                start: start,
                end: end,
                score: max(1, min(100, clip.score)),
                transcript: window,
                isSelected: false
            )
        }
        .sorted { $0.score > $1.score }

        var picked: [ClipCandidate] = []
        for var candidate in cleaned {
            guard picked.allSatisfy({ overlapRatio($0, candidate) < 0.5 }) else { continue }
            candidate.isSelected = picked.count < 4
            picked.append(candidate)
            if picked.count == 8 { break }
        }

        return picked.sorted { $0.start < $1.start }
    }

    private func overlapRatio(_ lhs: ClipCandidate, _ rhs: ClipCandidate) -> Double {
        let overlap = max(0, min(lhs.end, rhs.end) - max(lhs.start, rhs.start))
        return overlap / max(1, min(lhs.duration, rhs.duration))
    }

    private func time(_ seconds: Double) -> String {
        String(format: "%.2f", seconds)
    }

    private var schema: String {
        """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["clips"],
          "properties": {
            "clips": {
              "type": "array",
              "minItems": 1,
              "maxItems": 8,
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["title", "theme", "reason", "start", "end", "score"],
                "properties": {
                  "title": { "type": "string" },
                  "theme": { "type": "string" },
                  "reason": { "type": "string" },
                  "start": { "type": "number" },
                  "end": { "type": "number" },
                  "score": { "type": "integer", "minimum": 1, "maximum": 100 }
                }
              }
            }
          }
        }
        """
    }
}

private struct CodexMomentResponse: Decodable {
    var clips: [CodexMoment]
}

private struct CodexMoment: Decodable {
    var title: String
    var theme: String
    var reason: String
    var start: Double
    var end: Double
    var score: Int
}
