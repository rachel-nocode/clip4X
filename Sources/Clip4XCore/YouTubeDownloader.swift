import Foundation

/// Downloads an owned YouTube video to a local MP4 via `yt-dlp`.
public struct YouTubeDownloader: Sendable {
    public init() {}

    public static func cacheDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio.witch.clip4x")
            .appendingPathComponent("youtube")
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func download(
        videoID: String,
        ytDlpPath: String,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let directory = try Self.cacheDirectory(fileManager: fileManager)
        let destination = directory.appendingPathComponent("\(videoID).mp4")
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        let outputTemplate = directory.appendingPathComponent("\(videoID).%(ext)s").path
        do {
            _ = try await ProcessRunner.run(ytDlpPath, [
                "-f", "bv*+ba/b",
                "--merge-output-format", "mp4",
                "-o", outputTemplate,
                "--no-playlist",
                "--no-mtime",
                "https://www.youtube.com/watch?v=\(videoID)"
            ])
        } catch let Clip4XError.commandFailed(_, _, stderr) {
            throw Self.mapDownloadFailure(stderr)
        }

        guard fileManager.fileExists(atPath: destination.path) else {
            throw YouTubeImportError.downloadFailed("yt-dlp did not produce an MP4.")
        }
        return destination
    }

    static func mapDownloadFailure(_ stderr: String) -> YouTubeImportError {
        let lower = stderr.lowercased()
        if lower.contains("private video")
            || lower.contains("sign in to confirm")
            || lower.contains("this video is private") {
            return .privateDownloadFailed
        }
        return .downloadFailed(stderr)
    }
}
