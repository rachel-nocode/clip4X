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
}
