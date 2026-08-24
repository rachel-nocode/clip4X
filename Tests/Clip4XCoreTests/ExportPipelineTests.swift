import Foundation
import Testing
@testable import Clip4XCore

@Test func exportPipelineCreatesCaptionedVerticalClip() async throws {
    guard let ffmpeg = await ToolLocator.find("ffmpeg"),
          let ffprobe = await ToolLocator.find("ffprobe") else {
        return
    }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("clip4x-export-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let sourceURL = root.appendingPathComponent("source.mp4")
    let overlaysURL = root.appendingPathComponent("overlays")
    let outputURL = root.appendingPathComponent("output.mp4")

    _ = try await ProcessRunner.run(ffmpeg, [
        "-y",
        "-f", "lavfi",
        "-i", "testsrc2=size=1280x720:rate=30",
        "-f", "lavfi",
        "-i", "sine=frequency=440:sample_rate=44100",
        "-t", "2.5",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        sourceURL.path
    ])

    let clip = ClipCandidate(
        title: "Clean clip export",
        theme: "export",
        reason: "smoke test",
        start: 0,
        end: 2.2,
        score: 90,
        transcript: [
            TranscriptSegment(start: 0, end: 2.2, text: "This caption should render on the exported vertical clip.")
        ]
    )

    let mediaTools = MediaTools(ffmpegPath: ffmpeg, ffprobePath: ffprobe)
    let overlays = try CaptionOverlayRenderer().writeOverlays(
        clip: clip,
        ratio: .vertical,
        destinationDirectory: overlaysURL
    )
    try await mediaTools.exportComposedClip(
        videoURL: sourceURL,
        clip: clip,
        ratio: .vertical,
        overlays: overlays,
        destinationURL: outputURL
    )

    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    let outputSize = try await mediaTools.probeVideoSize(videoURL: outputURL)
    #expect(outputSize == VideoSize(width: 1080, height: 1920))
}

@Test func exportPipelineStacksPinnedFaceAndDemo() async throws {
    guard let ffmpeg = await ToolLocator.find("ffmpeg"),
          let ffprobe = await ToolLocator.find("ffprobe") else {
        return
    }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("clip4x-stack-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let sourceURL = root.appendingPathComponent("source.mp4")
    let outputURL = root.appendingPathComponent("stack.mp4")

    _ = try await ProcessRunner.run(ffmpeg, [
        "-y",
        "-f", "lavfi",
        "-i", "testsrc2=size=1920x1080:rate=24",
        "-f", "lavfi",
        "-i", "sine=frequency=330:sample_rate=44100",
        "-t", "1.2",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        sourceURL.path
    ])

    let clip = ClipCandidate(
        title: "Stack export",
        theme: "stack",
        reason: "smoke test",
        start: 0,
        end: 1.0,
        score: 80,
        transcript: []
    )
    let mediaTools = MediaTools(ffmpegPath: ffmpeg, ffprobePath: ffprobe)
    let scene = ScenePlan(
        face: NormalizedRect(x: 0.28, y: 0.42, width: 0.44, height: 0.52),
        demo: NormalizedRect(x: 0.18, y: 0.04, width: 0.64, height: 0.34),
        demoDetected: true,
        sourceSize: VideoSize(width: 1920, height: 1080)
    )
    try await mediaTools.exportComposedClip(
        videoURL: sourceURL,
        clip: clip,
        ratio: .vertical,
        overlays: [],
        destinationURL: outputURL,
        layout: scene.resolve(layout: .stack, ratio: .vertical, style: .talkingHead)
    )

    #expect(FileManager.default.fileExists(atPath: outputURL.path))
    let outputSize = try await mediaTools.probeVideoSize(videoURL: outputURL)
    #expect(outputSize == VideoSize(width: 1080, height: 1920))
}
