import Foundation
import Testing
@testable import Clip4XCore

@Suite struct WorkflowRunnerTests {
    @Test func qcAcceptsReferenceOutput() {
        let inspection = MediaInspection(
            width: 1080,
            height: 1920,
            duration: 32.1,
            videoCodec: "h264",
            audioCodec: "aac"
        )
        let result = WorkflowQC.validate(inspection, expectedDuration: 32)
        #expect(result.passed)
        #expect(result.issues.isEmpty)
    }

    @Test func qcRejectsLandscapeMissingAudioAndWrongCodec() {
        let inspection = MediaInspection(
            width: 1920,
            height: 1080,
            duration: 32,
            videoCodec: "hevc",
            audioCodec: nil
        )
        let result = WorkflowQC.validate(inspection, expectedDuration: 32)
        #expect(!result.passed)
        #expect(result.issues.contains(where: { $0.contains("1080x1920") }))
        #expect(result.issues.contains(where: { $0.contains("H.264") }))
        #expect(result.issues.contains(where: { $0.contains("AAC") }))
    }

    @Test func projectNameIsSanitizedFromInput() {
        #expect(WorkflowRunner.defaultProjectName(for: "/tmp/My Great Talk!.mov") == "My Great Talk-")
        #expect(WorkflowRunner.defaultProjectName(for: "https://youtu.be/abcdefghijk") == "youtube-abcdefghijk")
    }

    @Test func syntheticWorkflowProducesCompleteArtifacts() async throws {
        guard let ffmpeg = await ToolLocator.find("ffmpeg"),
              let ffprobe = await ToolLocator.find("ffprobe") else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip4x-workflow-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("input.mp4")
        _ = try await ProcessRunner.run(ffmpeg, [
            "-y", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
            "-t", "9", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", source.path
        ])
        let fixture = root.appendingPathComponent("transcript.json")
        try #"{"segments":[{"start":0,"end":8.5,"text":"Here is the better workflow because you can create a clean clip instead of wasting time.","words":[]}]}"#
            .write(to: fixture, atomically: true, encoding: .utf8)
        let whisper = root.appendingPathComponent("whisper")
        let script = """
        #!/bin/sh
        output_dir=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output_dir" ]; then shift; output_dir="$1"; fi
          shift
        done
        cp '\(fixture.path)' "$output_dir/source.json"
        """
        try script.write(to: whisper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: whisper.path)

        let project = try WorkflowProject.create(root: root.appendingPathComponent("project"))
        let pipeline = ClipPipeline(
            mediaTools: MediaTools(ffmpegPath: ffmpeg, ffprobePath: ffprobe),
            whisperPath: whisper.path
        )
        let runner = WorkflowRunner(
            sourceResolver: WorkflowSourceResolver(ffprobePath: ffprobe),
            pipeline: pipeline
        )
        let result = try await runner.run(
            input: source.path,
            project: project,
            options: WorkflowOptions(layout: .fit, maxClips: 1, captions: false)
        )

        #expect(result.renders.count == 1)
        #expect(result.renders[0].qc.passed)
        for artifact in [project.transcriptURL, project.candidatesURL, project.layoutsURL, project.metadataURL, project.qcURL] {
            #expect(FileManager.default.fileExists(atPath: artifact.path))
        }
        let previews = try FileManager.default.contentsOfDirectory(atPath: project.previewsDirectory.path)
        #expect(previews.filter { $0.hasSuffix(".png") }.count == 3)
    }
}
