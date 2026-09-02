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

        let resolved = try await WorkflowSourceResolver(validateMedia: false).resolve(.file(input), into: project)

        #expect(resolved.lastPathComponent == "source.mov")
        #expect(try Data(contentsOf: resolved) == Data("video".utf8))
    }

    @Test func rejectsUnsupportedWebURLs() {
        #expect(WorkflowInput.parse("https://example.com/video") == nil)
    }

    @Test func youtubeDownloadReturnsFreshExactOutputInsteadOfStaleSource() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip4x-ytdlp-test-\(UUID().uuidString)")
        let project = try WorkflowProject.create(root: temporary.appendingPathComponent("project"))
        let stale = project.sourceDirectory.appendingPathComponent("source.mp4")
        try Data("stale".utf8).write(to: stale)
        let script = temporary.appendingPathComponent("fake-yt-dlp.sh")
        let source = """
        #!/bin/sh
        template=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-o" ]; then shift; template="$1"; fi
          shift
        done
        output=$(printf '%s' "$template" | sed 's/%(ext)s/mp4/')
        printf 'fresh' > "$output"
        printf '%s\n' "$output"
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let resolved = try await WorkflowSourceResolver(
            ytdlpPath: script.path,
            validateMedia: false
        ).resolve(.youtube(URL(string: "https://youtu.be/abcdefghijk")!), into: project)

        #expect(resolved.lastPathComponent == "source-v2.mp4")
        #expect(try String(contentsOf: resolved, encoding: .utf8) == "fresh")
        #expect(try String(contentsOf: stale, encoding: .utf8) == "stale")
    }
}
