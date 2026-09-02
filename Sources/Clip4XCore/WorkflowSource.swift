import Foundation

public enum WorkflowInput: Equatable, Sendable {
    case file(URL)
    case youtube(URL)

    public static func parse(_ raw: String) -> WorkflowInput? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            let host = url.host?.lowercased() ?? ""
            guard host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") else {
                return nil
            }
            return .youtube(url)
        }
        let path = (trimmed as NSString).expandingTildeInPath
        return .file(URL(fileURLWithPath: path))
    }
}

public struct WorkflowSourceResolver: Sendable {
    public var ytdlpPath: String?

    public init(ytdlpPath: String? = nil) {
        self.ytdlpPath = ytdlpPath
    }

    public func resolve(_ input: WorkflowInput, into project: WorkflowProject) async throws -> URL {
        switch input {
        case .file(let source):
            return try copyLocal(source, into: project)
        case .youtube(let url):
            return try await downloadYouTube(url, into: project)
        }
    }

    private func copyLocal(_ source: URL, into project: WorkflowProject) throws -> URL {
        guard FileManager.default.isReadableFile(atPath: source.path) else {
            throw Clip4XError.invalidMedia("Cannot read \(source.path).")
        }
        let ext = source.pathExtension.isEmpty ? "mp4" : source.pathExtension
        let destination = uniqueSourceURL(project: project, extension: ext)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func downloadYouTube(_ url: URL, into project: WorkflowProject) async throws -> URL {
        let tool = if let ytdlpPath {
            ytdlpPath
        } else if let located = await ToolLocator.find("yt-dlp") {
            located
        } else {
            throw Clip4XError.missingTool("yt-dlp")
        }
        let template = project.sourceDirectory.appendingPathComponent("source.%(ext)s").path
        _ = try await ProcessRunner.run(tool, [
            "--no-playlist",
            "--write-info-json",
            "-f", "bv*+ba/b",
            "--merge-output-format", "mp4",
            "-o", template,
            url.absoluteString
        ])
        let files = try FileManager.default.contentsOfDirectory(
            at: project.sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        guard let video = files.first(where: {
            ["mp4", "mov", "mkv", "webm"].contains($0.pathExtension.lowercased())
        }) else {
            throw Clip4XError.invalidMedia("yt-dlp did not create a readable video.")
        }
        return video
    }

    private func uniqueSourceURL(project: WorkflowProject, extension ext: String) -> URL {
        var version = 1
        while true {
            let suffix = version == 1 ? "" : "-v\(version)"
            let candidate = project.sourceDirectory
                .appendingPathComponent("source\(suffix)")
                .appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            version += 1
        }
    }
}
