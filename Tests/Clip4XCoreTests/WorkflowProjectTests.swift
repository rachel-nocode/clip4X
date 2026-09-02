import Foundation
import Testing
@testable import Clip4XCore

@Suite struct WorkflowProjectTests {
    @Test func createsExpectedFoldersAndVersionsRenders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip4x-project-test-\(UUID().uuidString)")
        let project = try WorkflowProject.create(root: root)

        #expect(project.sourceDirectory.lastPathComponent == "source")
        #expect(project.analysisDirectory.lastPathComponent == "analysis")
        #expect(project.previewsDirectory.lastPathComponent == "previews")
        #expect(project.rendersDirectory.lastPathComponent == "renders")
        #expect(FileManager.default.fileExists(atPath: project.analysisDirectory.path))

        let first = project.uniqueRenderURL(stem: "01-clean-hook")
        #expect(first.lastPathComponent == "01-clean-hook.mp4")
        try Data().write(to: first)
        #expect(project.uniqueRenderURL(stem: "01-clean-hook").lastPathComponent == "01-clean-hook-v2.mp4")
    }

    @Test func writesCandidateAndMetadataArtifacts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip4x-artifact-test-\(UUID().uuidString)")
        let project = try WorkflowProject.create(root: root)
        let clip = ClipCandidate(
            title: "Stop Repeating Context",
            theme: "AI",
            reason: "Specific payoff",
            start: 10,
            end: 42,
            score: 92,
            transcript: [TranscriptSegment(start: 10, end: 42, text: "Opening and closing words")]
        )

        try project.writeCandidates([clip])
        try project.writeMetadata([
            "01-stop-repeating-context.mp4": WorkflowClipMetadata(
                title: clip.title,
                description: clip.reason,
                tags: [clip.theme]
            )
        ])

        let candidates = try String(contentsOf: project.candidatesURL, encoding: .utf8)
        #expect(candidates.contains("Stop Repeating Context"))
        #expect(candidates.contains("10.000–42.000"))
        let metadata = try Data(contentsOf: project.metadataURL)
        let decoded = try JSONDecoder().decode([String: WorkflowClipMetadata].self, from: metadata)
        #expect(decoded["01-stop-repeating-context.mp4"]?.tags == ["AI"])
    }
}
