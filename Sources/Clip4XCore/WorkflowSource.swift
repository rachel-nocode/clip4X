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
    public var ffprobePath: String?
    public var validateMedia: Bool

    public init(
        ytdlpPath: String? = nil,
        ffprobePath: String? = nil,
        validateMedia: Bool = true
    ) {
        self.ytdlpPath = ytdlpPath
        self.ffprobePath = ffprobePath
        self.validateMedia = validateMedia
    }

    public func resolve(_ input: WorkflowInput, into project: WorkflowProject) async throws -> URL {
        let resolved: URL
        switch input {
        case .file(let source):
            resolved = try copyLocal(source, into: project)
        case .youtube(let url):
            resolved = try await downloadYouTube(url, into: project)
        }
        if validateMedia {
            try await validate(resolved)
        }
        return resolved
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
        let stem = try uniqueSourceStem(project: project)
        let template = project.sourceDirectory.appendingPathComponent("\(stem).%(ext)s").path
        let result = try await ProcessRunner.run(tool, [
            "--no-playlist",
            "--write-info-json",
            "-f", "bv*+ba/b",
            "--merge-output-format", "mp4",
            "--print", "after_move:filepath",
            "-o", template,
            url.absoluteString
        ])
        guard let output = result.stdout.split(whereSeparator: \.isNewline).last else {
            throw Clip4XError.invalidMedia("yt-dlp did not create a readable video.")
        }
        let video = URL(fileURLWithPath: String(output)).standardizedFileURL
        let sourceDirectory = project.sourceDirectory.standardizedFileURL.path + "/"
        guard video.path.hasPrefix(sourceDirectory),
              ["mp4", "mov", "mkv", "webm"].contains(video.pathExtension.lowercased()),
              FileManager.default.isReadableFile(atPath: video.path) else {
            throw Clip4XError.invalidMedia("yt-dlp returned an invalid output path.")
        }
        return video
    }

    private func validate(_ video: URL) async throws {
        guard FileManager.default.isReadableFile(atPath: video.path) else {
            throw Clip4XError.invalidMedia("Cannot read \(video.path).")
        }
        let tool = if let ffprobePath {
            ffprobePath
        } else if let located = await ToolLocator.find("ffprobe") {
            located
        } else {
            throw Clip4XError.missingTool("ffprobe")
        }
        let inspection = try await MediaTools(ffmpegPath: "ffmpeg", ffprobePath: tool)
            .inspectMedia(videoURL: video)
        guard inspection.audioCodec != nil else {
            throw Clip4XError.invalidMedia("Source video has no audio stream.")
        }
    }

    private func uniqueSourceStem(project: WorkflowProject) throws -> String {
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: project.sourceDirectory.path))
        var version = 1
        while true {
            let stem = version == 1 ? "source" : "source-v\(version)"
            if !names.contains(where: { $0 == stem || $0.hasPrefix("\(stem).") }) {
                return stem
            }
            version += 1
        }
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
