import Foundation

public struct WorkflowClipMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var description: String
    public var tags: [String]

    public init(title: String, description: String, tags: [String]) {
        self.title = title
        self.description = description
        self.tags = tags
    }
}

public struct WorkflowLayoutArtifact: Codable, Equatable, Sendable {
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var face: NormalizedRect?
    public var screen: NormalizedRect?

    public init(sourceWidth: Int, sourceHeight: Int, face: NormalizedRect?, screen: NormalizedRect?) {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.face = face
        self.screen = screen
    }
}

public struct WorkflowProject: Sendable {
    public let root: URL

    public var sourceDirectory: URL { root.appendingPathComponent("source", isDirectory: true) }
    public var analysisDirectory: URL { root.appendingPathComponent("analysis", isDirectory: true) }
    public var previewsDirectory: URL { root.appendingPathComponent("previews", isDirectory: true) }
    public var rendersDirectory: URL { root.appendingPathComponent("renders", isDirectory: true) }
    public var candidatesURL: URL { analysisDirectory.appendingPathComponent("candidates.md") }
    public var layoutsURL: URL { analysisDirectory.appendingPathComponent("layouts.json") }
    public var transcriptURL: URL { analysisDirectory.appendingPathComponent("transcript.json") }
    public var qcURL: URL { analysisDirectory.appendingPathComponent("qc.md") }
    public var metadataURL: URL { rendersDirectory.appendingPathComponent("metadata.json") }

    public static func create(root: URL, fileManager: FileManager = .default) throws -> WorkflowProject {
        let project = WorkflowProject(root: root.standardizedFileURL)
        for directory in [project.sourceDirectory, project.analysisDirectory, project.previewsDirectory, project.rendersDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return project
    }

    public func uniqueRenderURL(stem: String, fileManager: FileManager = .default) -> URL {
        let safeStem = ClipFileName.safe(stem)
        var version = 1
        while true {
            let suffix = version == 1 ? "" : "-v\(version)"
            let candidate = rendersDirectory
                .appendingPathComponent(safeStem + suffix)
                .appendingPathExtension("mp4")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            version += 1
        }
    }

    public func writeCandidates(_ clips: [ClipCandidate]) throws {
        let rows = clips.enumerated().map { index, clip in
            let words = clip.transcript.map(\.text).joined(separator: " ")
            return """
            ## \(index + 1). \(clip.title)

            - Time: \(String(format: "%.3f", clip.start))–\(String(format: "%.3f", clip.end))
            - Score: \(clip.score)/100
            - Theme: \(clip.theme)
            - Reason: \(clip.reason)
            - Opening/closing words: \(words)
            """
        }
        try ("# Clip Candidates\n\n" + rows.joined(separator: "\n\n") + "\n")
            .write(to: candidatesURL, atomically: true, encoding: .utf8)
    }

    public func writeLayouts(_ layouts: [String: WorkflowLayoutArtifact]) throws {
        try writeJSON(layouts, to: layoutsURL)
    }

    public func writeMetadata(_ metadata: [String: WorkflowClipMetadata]) throws {
        try writeJSON(metadata, to: metadataURL)
    }

    public func writeTranscript(_ segments: [TranscriptSegment]) throws {
        try writeJSON(segments, to: transcriptURL)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
