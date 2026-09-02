import Foundation
import Testing
@testable import Clip4XCore

@Suite struct WorkflowSourceTests {
    @Test func classifiesYouTubeAndLocalInputs() {
        #expect(
            WorkflowInput.parse("https://youtu.be/abcdefghijk")
                == .youtube(URL(string: "https://youtu.be/abcdefghijk")!)
        )
        #expect(
            WorkflowInput.parse("/tmp/talk.mov")
                == .file(URL(fileURLWithPath: "/tmp/talk.mov"))
        )
    }

    @Test func localSourceIsCopiedIntoProject() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip4x-source-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let input = temporary.appendingPathComponent("talk.mov")
        try Data("video".utf8).write(to: input)
        let project = try WorkflowProject.create(root: temporary.appendingPathComponent("project"))

        let resolved = try await WorkflowSourceResolver().resolve(.file(input), into: project)

        #expect(resolved.lastPathComponent == "source.mov")
        #expect(try Data(contentsOf: resolved) == Data("video".utf8))
    }

    @Test func rejectsUnsupportedWebURLs() {
        #expect(WorkflowInput.parse("https://example.com/video") == nil)
    }
}
