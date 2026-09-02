import Foundation
import Testing
@testable import Clip4XCore

@Test func claudeProviderUsesPrintModeWithJSONSchema() {
    let schemaURL = URL(fileURLWithPath: "/tmp/schema.json")
    let outputURL = URL(fileURLWithPath: "/tmp/output.json")

    let command = MomentRankerProvider.claude(path: "/usr/local/bin/claude")
        .command(schemaURL: schemaURL, outputURL: outputURL, prompt: "Pick clips")

    #expect(command.executablePath == "/usr/local/bin/claude")
    #expect(command.arguments.contains("--print"))
    #expect(command.arguments.contains("--output-format"))
    #expect(command.arguments.contains("json"))
    #expect(command.arguments.contains("--json-schema"))
    #expect(command.arguments.contains("--no-session-persistence"))
    #expect(command.arguments.last == "Pick clips")
    #expect(command.readsOutputFile == false)
}

@Test func defaultToolSearchPathIncludesUserLocalBin() {
    let homeLocalBin = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin")
        .path

    #expect(ToolLocator.defaultSearchPath.split(separator: ":").map(String.init).contains(homeLocalBin))
}

@Test func rankerPreferenceAutoPrefersCodexThenClaude() async {
    let preference = MomentRankerPreference.auto
    let provider = await preference.resolve { name in
        [("codex", "/bin/codex"), ("claude", "/bin/claude")].first { $0.0 == name }?.1
    }

    #expect(provider?.name == "Codex")
}

@Test func rankerPreferenceClaudeSelectsClaudeEvenWhenCodexExists() async {
    let preference = MomentRankerPreference.claude
    let provider = await preference.resolve { name in
        [("codex", "/bin/codex"), ("claude", "/bin/claude")].first { $0.0 == name }?.1
    }

    #expect(provider?.name == "Claude")
}

@Test func codexProviderWritesLastMessageToOutputFile() {
    let schemaURL = URL(fileURLWithPath: "/tmp/schema.json")
    let outputURL = URL(fileURLWithPath: "/tmp/output.json")

    let command = MomentRankerProvider.codex(path: "/opt/homebrew/bin/codex")
        .command(schemaURL: schemaURL, outputURL: outputURL, prompt: "Pick clips")

    #expect(command.executablePath == "/opt/homebrew/bin/codex")
    #expect(command.arguments.starts(with: ["exec", "--skip-git-repo-check"]))
    #expect(command.arguments.contains("--output-schema"))
    #expect(command.arguments.contains(schemaURL.path))
    #expect(command.arguments.contains("--output-last-message"))
    #expect(command.arguments.contains(outputURL.path))
    #expect(command.arguments.last == "Pick clips")
    #expect(command.readsOutputFile == true)
}

@Test func claudeWrappedJSONResultDecodesToClips() throws {
    let stdout = """
    {"type":"result","subtype":"success","result":"{\\"clips\\":[{\\"title\\":\\"Clean hook\\",\\"theme\\":\\"editing\\",\\"reason\\":\\"strong payoff\\",\\"start\\":10,\\"end\\":40,\\"score\\":88}]}","total_cost_usd":0.01}
    """

    let clips = try LocalAIMomentRanker.decodeCandidates(
        from: Data(stdout.utf8),
        providerName: "Claude",
        segments: [
            TranscriptSegment(start: 8, end: 20, text: "This is the setup."),
            TranscriptSegment(start: 20, end: 42, text: "This is the payoff.")
        ],
        sourceDuration: 60
    )

    #expect(clips.count == 1)
    #expect(clips[0].title == "Clean hook")
    #expect(clips[0].reason == "Claude 88/100: strong payoff")
    #expect(clips[0].isSelected)
}

@Test func claudeStructuredOutputDecodesToClips() throws {
    let stdout = #"{"type":"result","subtype":"success","structured_output":{"clips":[{"title":"Structured hook","theme":"workflow","reason":"clear result","start":4,"end":18,"score":91}]}}"#
    let clips = try LocalAIMomentRanker.decodeCandidates(
        from: Data(stdout.utf8),
        providerName: "Claude",
        segments: [TranscriptSegment(start: 4, end: 18, text: "Here is the complete workflow and result.")],
        sourceDuration: 20
    )
    #expect(clips.map(\.title) == ["Structured hook"])
}

@Test func pipelineCarriesSelectedRankerAndReportsItsName() {
    let pipeline = ClipPipeline(
        mediaTools: MediaTools(ffmpegPath: "/bin/ffmpeg", ffprobePath: "/bin/ffprobe"),
        whisperPath: "/bin/whisper",
        rankerProvider: .claude(path: "/bin/claude")
    )
    let result = AnalysisResult(
        duration: 10,
        sourceSize: VideoSize(width: 1920, height: 1080),
        segments: [],
        clips: [],
        rankerName: pipeline.rankerProvider?.name
    )

    #expect(pipeline.rankerProvider?.name == "Claude")
    #expect(result.rankerName == "Claude")
    #expect(!result.usedCodex)
}

@Test func explicitMissingRankerFailsDuringPipelineCreation() async {
    await #expect(throws: Clip4XError.self) {
        _ = try await ClipPipeline.make(
            requireWhisper: false,
            rankerPreference: .claude
        ) { name in
            ["ffmpeg": "/bin/ffmpeg", "ffprobe": "/bin/ffprobe"][name]
        }
    }
}

@Test func explicitRankerFailureDoesNotSilentlyFallback() async throws {
    let pipeline = ClipPipeline(
        mediaTools: MediaTools(ffmpegPath: "/bin/ffmpeg", ffprobePath: "/bin/ffprobe"),
        whisperPath: "/bin/whisper",
        rankerProvider: .claude(path: "/usr/bin/false"),
        rankerFallbackAllowed: false
    )
    let segments = [
        TranscriptSegment(start: 0, end: 12, text: "Here is the specific result and why it matters to you."),
        TranscriptSegment(start: 12, end: 28, text: "The practical payoff is a faster and clearer workflow.")
    ]
    let work = FileManager.default.temporaryDirectory
        .appendingPathComponent("clip4x-explicit-ranker-test-\(UUID().uuidString)")

    await #expect(throws: Clip4XError.self) {
        _ = try await pipeline.rankCandidates(
            segments: segments,
            sourceDuration: 28,
            workDirectory: work,
            maxClips: 4
        )
    }
}
