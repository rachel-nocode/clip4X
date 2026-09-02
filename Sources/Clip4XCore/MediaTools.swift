import Foundation

public struct MediaInspection: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var duration: Double
    public var videoCodec: String?
    public var audioCodec: String?

    public init(width: Int, height: Int, duration: Double, videoCodec: String?, audioCodec: String?) {
        self.width = width
        self.height = height
        self.duration = duration
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
    }
}

public struct MediaTools: Sendable {
    public var ffmpegPath: String
    public var ffprobePath: String

    public init(ffmpegPath: String, ffprobePath: String) {
        self.ffmpegPath = ffmpegPath
        self.ffprobePath = ffprobePath
    }

    public func probeDuration(videoURL: URL) async throws -> Double {
        let result = try await ProcessRunner.run(ffprobePath, [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=nw=1:nk=1",
            videoURL.path
        ])
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let duration = Double(value), duration > 0 else {
            throw Clip4XError.invalidMedia("Could not read video duration.")
        }
        return duration
    }

    public func probeVideoSize(videoURL: URL) async throws -> VideoSize {
        let result = try await ProcessRunner.run(ffprobePath, [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=s=x:p=0",
            videoURL.path
        ])
        let parts = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "x")
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else {
            throw Clip4XError.invalidMedia("Could not read video dimensions.")
        }
        return VideoSize(width: width, height: height)
    }

    public func inspectMedia(videoURL: URL) async throws -> MediaInspection {
        let result = try await ProcessRunner.run(ffprobePath, [
            "-v", "error",
            "-show_entries", "stream=codec_name,codec_type,width,height:format=duration",
            "-of", "json",
            videoURL.path
        ])
        let decoded = try JSONDecoder().decode(ProbeOutput.self, from: Data(result.stdout.utf8))
        guard let video = decoded.streams.first(where: { $0.codecType == "video" }),
              let width = video.width, let height = video.height,
              let duration = Double(decoded.format.duration), duration > 0 else {
            throw Clip4XError.invalidMedia("Could not inspect media streams.")
        }
        let audio = decoded.streams.first(where: { $0.codecType == "audio" })
        return MediaInspection(
            width: width,
            height: height,
            duration: duration,
            videoCodec: video.codecName,
            audioCodec: audio?.codecName
        )
    }

    public func extractAudio(videoURL: URL, destinationURL: URL) async throws {
        _ = try await ProcessRunner.run(ffmpegPath, [
            "-y",
            "-i", videoURL.path,
            "-vn",
            "-acodec", "pcm_s16le",
            "-ar", "16000",
            "-ac", "1",
            destinationURL.path
        ])
    }

    public func exportComposedClip(
        videoURL: URL,
        clip: ClipCandidate,
        ratio: ExportRatio,
        overlays: [TimedOverlay],
        destinationURL: URL,
        layout: ResolvedLayout = .fit
    ) async throws {
        _ = try await runComposition(
            videoURL: videoURL,
            start: clip.start,
            duration: clip.duration,
            ratio: ratio,
            overlays: overlays,
            destinationURL: destinationURL,
            layout: layout,
            singleFrame: false
        )
    }

    public func exportPreviewFrame(
        videoURL: URL,
        at seconds: Double,
        ratio: ExportRatio,
        destinationURL: URL,
        layout: ResolvedLayout = .fit
    ) async throws {
        _ = try await runComposition(
            videoURL: videoURL,
            start: max(0, seconds),
            duration: 0.12,
            ratio: ratio,
            overlays: [],
            destinationURL: destinationURL,
            layout: layout,
            singleFrame: true
        )
    }

    public func extractFrame(videoURL: URL, at seconds: Double, destinationURL: URL) async throws {
        _ = try await ProcessRunner.run(ffmpegPath, [
            "-y",
            "-ss", String(format: "%.3f", max(0, seconds)),
            "-i", videoURL.path,
            "-frames:v", "1",
            "-update", "1",
            destinationURL.path
        ])
    }

    private func runComposition(
        videoURL: URL,
        start: Double,
        duration: Double,
        ratio: ExportRatio,
        overlays: [TimedOverlay],
        destinationURL: URL,
        layout: ResolvedLayout,
        singleFrame: Bool
    ) async throws {
        var filterParts = CompositionFilter.baseGraph(ratio: ratio, layout: layout)
        var inputLabel = "v0"
        for (index, overlay) in overlays.enumerated() {
            let inputIndex = index + 1
            let outputLabel = "v\(inputIndex)"
            filterParts.append("[\(inputIndex):v]format=rgba[ov\(inputIndex)]")
            filterParts.append("[\(inputLabel)][ov\(inputIndex)]overlay=0:0:enable='between(t,\(String(format: "%.3f", overlay.start)),\(String(format: "%.3f", overlay.end)))'[\(outputLabel)]")
            inputLabel = outputLabel
        }
        filterParts.append("[\(inputLabel)]format=\(singleFrame ? "rgba" : "yuv420p")[vout]")

        var arguments = [
            "-y",
            "-ss", String(format: "%.3f", start),
            "-i", videoURL.path,
        ]
        for overlay in overlays {
            arguments.append(contentsOf: ["-loop", "1", "-i", overlay.url.path])
        }
        arguments.append(contentsOf: [
            "-t", String(format: "%.3f", max(0.04, duration)),
            "-filter_complex", filterParts.joined(separator: ";"),
            "-map", "[vout]",
        ])

        if singleFrame {
            arguments.append(contentsOf: [
                "-frames:v", "1",
                "-update", "1",
                destinationURL.path
            ])
        } else {
            arguments.append(contentsOf: [
                "-map", "0:a?",
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "18",
                "-c:a", "aac",
                "-b:a", "192k",
                "-shortest",
                "-movflags", "+faststart",
                destinationURL.path
            ])
        }

        _ = try await ProcessRunner.run(ffmpegPath, arguments)
    }
}

private struct ProbeOutput: Decodable {
    var streams: [ProbeStream]
    var format: ProbeFormat
}

private struct ProbeStream: Decodable {
    var codecName: String?
    var codecType: String
    var width: Int?
    var height: Int?

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case codecType = "codec_type"
        case width, height
    }
}

private struct ProbeFormat: Decodable {
    var duration: String
}
