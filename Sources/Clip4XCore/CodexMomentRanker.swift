import Foundation

public struct MomentRankerCommand: Sendable {
    public var executablePath: String
    public var arguments: [String]
    public var readsOutputFile: Bool
}

public enum MomentRankerProvider: Sendable {
    case codex(path: String)
    case claude(path: String)

    public var name: String {
        switch self {
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        }
    }

    public func command(schemaURL: URL, outputURL: URL, prompt: String) -> MomentRankerCommand {
        switch self {
        case .codex(let path):
            return MomentRankerCommand(
                executablePath: path,
                arguments: [
                    "exec",
                    "--skip-git-repo-check",
                    "--sandbox", "read-only",
                    "--color", "never",
                    "--output-schema", schemaURL.path,
                    "--output-last-message", outputURL.path,
                    prompt
                ],
                readsOutputFile: true
            )
        case .claude(let path):
            let schemaArgument = (try? String(contentsOf: schemaURL, encoding: .utf8)) ?? schemaURL.path
            return MomentRankerCommand(
                executablePath: path,
                arguments: [
                    "--print",
                    "--output-format", "json",
                    "--json-schema", schemaArgument,
                    "--permission-mode", "dontAsk",
                    "--no-session-persistence",
                    prompt
                ],
                readsOutputFile: false
            )
        }
    }
}

public enum MomentRankerPreference: String, CaseIterable, Identifiable, Sendable {
    case auto
    case codex
    case claude

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto:
            "Auto"
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        }
    }

    public var toolName: String? {
        switch self {
        case .auto:
            nil
        case .codex:
            "codex"
        case .claude:
            "claude"
        }
    }

    public func resolve(findTool: @Sendable (String) async -> String?) async -> MomentRankerProvider? {
        switch self {
        case .auto:
            if let codex = await findTool("codex") {
                return .codex(path: codex)
            }
            if let claude = await findTool("claude") {
                return .claude(path: claude)
            }
            return nil
        case .codex:
            guard let codex = await findTool("codex") else { return nil }
            return .codex(path: codex)
        case .claude:
            guard let claude = await findTool("claude") else { return nil }
            return .claude(path: claude)
        }
    }
}

public struct LocalAIMomentRanker: Sendable {
    public var provider: MomentRankerProvider

    public init(provider: MomentRankerProvider) {
        self.provider = provider
    }

    public func rank(
        segments: [TranscriptSegment],
        sourceDuration: Double,
        workDirectory: URL
    ) async throws -> [ClipCandidate] {
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let schemaURL = workDirectory.appendingPathComponent("ai-moments.schema.json")
        let outputURL = workDirectory.appendingPathComponent("ai-moments.json")
        try Self.schema.write(to: schemaURL, atomically: true, encoding: .utf8)

        let prompt = Self.makePrompt(segments: segments, sourceDuration: sourceDuration)
        let command = provider.command(schemaURL: schemaURL, outputURL: outputURL, prompt: prompt)
        let result = try await ProcessRunner.run(
            command.executablePath,
            command.arguments,
            currentDirectory: workDirectory,
            environment: [
                "PATH": ToolLocator.defaultSearchPath
            ]
        )

        let data = command.readsOutputFile ? try Data(contentsOf: outputURL) : Data(result.stdout.utf8)
        return try Self.decodeCandidates(
            from: data,
            providerName: provider.name,
            segments: segments,
            sourceDuration: sourceDuration
        )
    }

    public static func decodeCandidates(
        from data: Data,
        providerName: String,
        segments: [TranscriptSegment],
        sourceDuration: Double
    ) throws -> [ClipCandidate] {
        let response = try decodeResponse(from: data)
        return makeCandidates(
            from: response.clips,
            providerName: providerName,
            segments: segments,
            sourceDuration: sourceDuration
        )
    }

    private static func decodeResponse(from data: Data) throws -> AIMomentResponse {
        let decoder = JSONDecoder()
        if let response = try? decoder.decode(AIMomentResponse.self, from: data) {
            return response
        }

        let claudeResponse = try decoder.decode(ClaudePrintResponse.self, from: data)
        if let structuredOutput = claudeResponse.structuredOutput {
            return structuredOutput
        }
        guard let result = claudeResponse.result else {
            throw Clip4XError.exportFailed("Claude returned no structured clip output.")
        }
        return try decoder.decode(AIMomentResponse.self, from: Data(result.utf8))
    }

    private static func makePrompt(segments: [TranscriptSegment], sourceDuration: Double) -> String {
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

    private static func makeCandidates(
        from clips: [AIMoment],
        providerName: String,
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
                reason: "\(providerName) \(clip.score)/100: \(clip.reason.trimmingCharacters(in: .whitespacesAndNewlines))",
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

    private static func overlapRatio(_ lhs: ClipCandidate, _ rhs: ClipCandidate) -> Double {
        let overlap = max(0, min(lhs.end, rhs.end) - max(lhs.start, rhs.start))
        return overlap / max(1, min(lhs.duration, rhs.duration))
    }

    private static func time(_ seconds: Double) -> String {
        String(format: "%.2f", seconds)
    }

    private static var schema: String {
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
        try await LocalAIMomentRanker(provider: .codex(path: codexPath)).rank(
            segments: segments,
            sourceDuration: sourceDuration,
            workDirectory: workDirectory
        )
    }
}

private struct AIMomentResponse: Decodable {
    var clips: [AIMoment]
}

private struct AIMoment: Decodable {
    var title: String
    var theme: String
    var reason: String
    var start: Double
    var end: Double
    var score: Int
}

private struct ClaudePrintResponse: Decodable {
    var result: String?
    var structuredOutput: AIMomentResponse?

    enum CodingKeys: String, CodingKey {
        case result
        case structuredOutput = "structured_output"
    }
}
