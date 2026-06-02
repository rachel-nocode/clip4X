import Foundation

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
        destinationURL: URL
    ) async throws {
        let size = ratio.outputSize
        let baseFilter = [
            "[0:v]split=2[bg][fg]",
            "[bg]scale=\(size.width):\(size.height):force_original_aspect_ratio=increase,crop=\(size.width):\(size.height),gblur=sigma=32,eq=brightness=-0.06:saturation=1.12[bgv]",
            "[fg]scale=\(size.width):\(size.height):force_original_aspect_ratio=decrease[fgv]",
            "[bgv][fgv]overlay=(W-w)/2:(H-h)/2,setsar=1[v0]"
        ]

        var filterParts = baseFilter
        var inputLabel = "v0"
        for (index, overlay) in overlays.enumerated() {
            let inputIndex = index + 1
            let outputLabel = "v\(inputIndex)"
            filterParts.append("[\(inputIndex):v]format=rgba[ov\(inputIndex)]")
            filterParts.append("[\(inputLabel)][ov\(inputIndex)]overlay=0:0:enable='between(t,\(String(format: "%.3f", overlay.start)),\(String(format: "%.3f", overlay.end)))'[\(outputLabel)]")
            inputLabel = outputLabel
        }
        filterParts.append("[\(inputLabel)]format=yuv420p[vout]")

        var arguments = [
            "-y",
            "-ss", String(format: "%.3f", clip.start),
            "-i", videoURL.path,
        ]
        for overlay in overlays {
            arguments.append(contentsOf: ["-loop", "1", "-i", overlay.url.path])
        }
        arguments.append(contentsOf: [
            "-t", String(format: "%.3f", clip.duration),
            "-filter_complex", filterParts.joined(separator: ";"),
            "-map", "[vout]",
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

        _ = try await ProcessRunner.run(ffmpegPath, arguments)
    }
}
