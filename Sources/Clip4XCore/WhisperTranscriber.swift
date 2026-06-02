import Foundation

public struct WhisperTranscriber: Sendable {
    public var whisperPath: String
    public var model: String

    public init(whisperPath: String, model: String = "base") {
        self.whisperPath = whisperPath
        self.model = model
    }

    public func transcribe(audioURL: URL, outputDirectory: URL) async throws -> [TranscriptSegment] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        _ = try await ProcessRunner.run(whisperPath, [
            audioURL.path,
            "--model", model,
            "--language", "en",
            "--output_format", "json",
            "--output_dir", outputDirectory.path,
            "--verbose", "False"
        ])

        let jsonURL = outputDirectory
            .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw Clip4XError.commandFailed(
                "whisper",
                0,
                "Whisper produced no transcript. This usually means it could not run ffmpeg to decode the audio. Ensure ffmpeg is installed via Homebrew."
            )
        }
        let data = try Data(contentsOf: jsonURL)
        let decoded = try JSONDecoder().decode(WhisperOutput.self, from: data)
        let segments = decoded.segments
            .map { TranscriptSegment(start: $0.start, end: $0.end, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty && $0.end > $0.start }

        guard !segments.isEmpty else {
            throw Clip4XError.noTranscript
        }

        return segments
    }
}

private struct WhisperOutput: Decodable {
    var segments: [WhisperSegment]
}

private struct WhisperSegment: Decodable {
    var start: Double
    var end: Double
    var text: String
}
