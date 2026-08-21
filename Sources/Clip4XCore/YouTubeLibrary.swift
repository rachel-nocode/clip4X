import Foundation

public struct YouTubeOwnedVideo: Sendable, Equatable {
    public var id: String
    public var title: String
    public var channelID: String

    public init(id: String, title: String, channelID: String) {
        self.id = id
        self.title = title
        self.channelID = channelID
    }
}

public enum YouTubeImportError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case reconnectRequired
    case notOwned
    case videoNotFound
    case noChannel
    case apiError(Int, String)
    case downloadFailed(String)
    case privateDownloadFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Paste a YouTube video URL or video ID."
        case .reconnectRequired:
            "Reconnect YouTube to import your own videos."
        case .notOwned:
            "That video is not on your connected YouTube channel."
        case .videoNotFound:
            "YouTube could not find that video."
        case .noChannel:
            "No YouTube channel on this account."
        case let .apiError(code, body):
            "YouTube API failed (HTTP \(code)): \(body)"
        case let .downloadFailed(detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Download failed."
                : "Download failed: \(trimmed.prefix(200))"
        case .privateDownloadFailed:
            "This video is private. Download it from YouTube Studio and drop the file."
        }
    }
}

/// Verifies a video belongs to the connected YouTube channel.
public struct YouTubeLibrary: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func verifyOwnership(videoID: String, accessToken: String) async throws -> YouTubeOwnedVideo {
        let channelID = try await fetchMyChannelID(accessToken: accessToken)
        let video = try await fetchVideo(videoID: videoID, accessToken: accessToken)
        return try Self.confirmOwnership(video: video, channelID: channelID)
    }

    public static func confirmOwnership(video: YouTubeOwnedVideo, channelID: String) throws -> YouTubeOwnedVideo {
        guard video.channelID == channelID else {
            throw YouTubeImportError.notOwned
        }
        return video
    }

    public static func parseChannelID(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(ChannelsResponse.self, from: data)
        guard let id = decoded.items?.first?.id, !id.isEmpty else {
            throw YouTubeImportError.noChannel
        }
        return id
    }

    public static func parseVideo(from data: Data) throws -> YouTubeOwnedVideo {
        let decoded = try JSONDecoder().decode(VideosResponse.self, from: data)
        guard let item = decoded.items?.first else {
            throw YouTubeImportError.videoNotFound
        }
        return YouTubeOwnedVideo(id: item.id, title: item.snippet.title, channelID: item.snippet.channelId)
    }

    private func fetchMyChannelID(accessToken: String) async throws -> String {
        var components = URLComponents(url: YouTubeConfig.channelsEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "part", value: "id"),
            URLQueryItem(name: "mine", value: "true")
        ]
        let data = try await get(components.url!, accessToken: accessToken)
        return try Self.parseChannelID(from: data)
    }

    private func fetchVideo(videoID: String, accessToken: String) async throws -> YouTubeOwnedVideo {
        var components = URLComponents(url: YouTubeConfig.videosListEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet,status"),
            URLQueryItem(name: "id", value: videoID)
        ]
        let data = try await get(components.url!, accessToken: accessToken)
        return try Self.parseVideo(from: data)
    }

    private func get(_ url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeImportError.apiError(0, "Unreadable response.")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw YouTubeImportError.reconnectRequired
        }
        guard (200...299).contains(http.statusCode) else {
            throw YouTubeImportError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

private struct ChannelsResponse: Decodable {
    struct Item: Decodable {
        let id: String
    }

    let items: [Item]?
}

private struct VideosResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let snippet: Snippet
    }

    struct Snippet: Decodable {
        let title: String
        let channelId: String
    }

    let items: [Item]?
}
