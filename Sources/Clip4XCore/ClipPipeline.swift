import Foundation

public struct AnalysisResult: Sendable {
    public var duration: Double
    public var sourceSize: VideoSize
    public var segments: [TranscriptSegment]
    public var clips: [ClipCandidate]
    public var rankerName: String?

    public var usedCodex: Bool { rankerName == "Codex" }

    public init(
        duration: Double,
        sourceSize: VideoSize,
        segments: [TranscriptSegment],
        clips: [ClipCandidate],
        rankerName: String?
    ) {
        self.duration = duration
        self.sourceSize = sourceSize
        self.segments = segments
        self.clips = clips
        self.rankerName = rankerName
    }
}

public struct ClipPipeline: Sendable {
    public var mediaTools: MediaTools
    public var whisperPath: String
    public var whisperModel: String
    public var rankerProvider: MomentRankerProvider?
    public var analyzer: FaceAndCropAnalyzer

    public init(
        mediaTools: MediaTools,
        whisperPath: String,
        whisperModel: String = "base",
        rankerProvider: MomentRankerProvider? = nil,
        analyzer: FaceAndCropAnalyzer = FaceAndCropAnalyzer()
    ) {
        self.mediaTools = mediaTools
        self.whisperPath = whisperPath
        self.whisperModel = whisperModel
        self.rankerProvider = rankerProvider
        self.analyzer = analyzer
    }

    public static func make(
        requireWhisper: Bool = true,
        rankerPreference: MomentRankerPreference = .auto
    ) async throws -> ClipPipeline {
        guard let ffmpeg = await ToolLocator.find("ffmpeg") else { throw Clip4XError.missingTool("ffmpeg") }
        guard let ffprobe = await ToolLocator.find("ffprobe") else { throw Clip4XError.missingTool("ffprobe") }
        let whisper = await ToolLocator.find("whisper")
        if requireWhisper, whisper == nil {
            throw Clip4XError.missingTool("whisper")
        }
        return ClipPipeline(
            mediaTools: MediaTools(ffmpegPath: ffmpeg, ffprobePath: ffprobe),
            whisperPath: whisper ?? "",
            whisperModel: "base",
            rankerProvider: await rankerPreference.resolve { await ToolLocator.find($0) }
        )
    }

    public func analyze(
        videoURL: URL,
        workDirectory: URL,
        maxClips: Int = 8,
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> AnalysisResult {
        onStatus?("Reading video")
        let duration = try await mediaTools.probeDuration(videoURL: videoURL)
        let sourceSize = try await mediaTools.probeVideoSize(videoURL: videoURL)

        let audioURL = workDirectory.appendingPathComponent("source.wav")
        let transcriptDirectory = workDirectory.appendingPathComponent("transcript")
        onStatus?("Extracting audio")
        try await mediaTools.extractAudio(videoURL: videoURL, destinationURL: audioURL)

        onStatus?("Transcribing with Whisper")
        let transcriber = WhisperTranscriber(whisperPath: whisperPath, model: whisperModel)
        let segments = try await transcriber.transcribe(audioURL: audioURL, outputDirectory: transcriptDirectory)

        onStatus?("Finding clip moments")
        let detector = ClipMomentDetector(maxClips: maxClips)
        let fallbackClips = detector.detect(in: segments, sourceDuration: duration)

        var rankerName: String?
        let clips: [ClipCandidate]
        if let rankerProvider {
            do {
                onStatus?("Ranking moments with \(rankerProvider.name) CLI")
                let ranker = LocalAIMomentRanker(provider: rankerProvider)
                let ranked = try await ranker.rank(
                    segments: segments,
                    sourceDuration: duration,
                    workDirectory: workDirectory.appendingPathComponent(rankerProvider.name.lowercased())
                )
                clips = ranked.isEmpty ? fallbackClips : Array(ranked.prefix(maxClips))
                rankerName = ranked.isEmpty ? nil : rankerProvider.name
            } catch {
                clips = fallbackClips
            }
        } else {
            clips = fallbackClips
        }

        return AnalysisResult(
            duration: duration,
            sourceSize: sourceSize,
            segments: segments,
            clips: clips,
            rankerName: rankerName
        )
    }

    public func scenePlan(
        videoURL: URL,
        clip: ClipCandidate,
        sourceSize: VideoSize,
        options: ExportOptions
    ) -> ScenePlan {
        analyzer
            .analyzeScene(videoURL: videoURL, clip: clip, sourceSize: sourceSize)
            .applying(options)
    }

    public func exportClip(
        videoURL: URL,
        clip: ClipCandidate,
        sourceSize: VideoSize,
        options: ExportOptions,
        destinationURL: URL,
        workDirectory: URL
    ) async throws {
        let scene = scenePlan(videoURL: videoURL, clip: clip, sourceSize: sourceSize, options: options)
        let resolved = scene.resolve(layout: options.layout, ratio: options.ratio, style: options.style)
        let overlays: [TimedOverlay]
        if options.captions {
            overlays = try CaptionOverlayRenderer().writeOverlays(
                clip: clip,
                ratio: options.ratio,
                destinationDirectory: workDirectory.appendingPathComponent("overlays-\(clip.id.uuidString)"),
                layout: resolved
            )
        } else {
            overlays = []
        }
        try await mediaTools.exportComposedClip(
            videoURL: videoURL,
            clip: clip,
            ratio: options.ratio,
            overlays: overlays,
            destinationURL: destinationURL,
            layout: resolved
        )
    }

    public func exportFrame(
        videoURL: URL,
        at seconds: Double,
        sourceSize: VideoSize,
        options: ExportOptions,
        destinationURL: URL
    ) async throws -> ScenePlan {
        let duration = max(0.4, try await mediaTools.probeDuration(videoURL: videoURL))
        let start = min(max(0, seconds), max(0, duration - 0.05))
        let clip = ClipCandidate(
            title: "frame",
            theme: "frame",
            reason: "preview",
            start: start,
            end: min(duration, start + 0.8),
            score: 1,
            transcript: []
        )
        let scene = scenePlan(videoURL: videoURL, clip: clip, sourceSize: sourceSize, options: options)
        let resolved = scene.resolve(layout: options.layout, ratio: options.ratio, style: options.style)
        try await mediaTools.exportPreviewFrame(
            videoURL: videoURL,
            at: start,
            ratio: options.ratio,
            destinationURL: destinationURL,
            layout: resolved
        )
        return scene
    }
}

public enum ClipFileName {
    public static func safe(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(scalars).replacingOccurrences(of: "  ", with: " ")
        return String(cleaned.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func timecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d%02d", total / 60, total % 60)
    }

    public static func clipFile(title: String, start: Double) -> String {
        safe("\(timecode(start))-\(title)")
    }

    public static func layoutFolder(ratio: ExportRatio, layout: ExportLayout) -> String {
        "\(ratio.label)-\(layout.rawValue)"
    }

    public static func matchesLayoutFolder(_ url: URL, ratio: ExportRatio, layout: ExportLayout) -> Bool {
        url.deletingLastPathComponent().lastPathComponent == layoutFolder(ratio: ratio, layout: layout)
    }
}
