import Foundation

/// Privacy for an uploaded video. Scheduling requires `.private`.
public enum YouTubePrivacy: String, Sendable {
    case `private`
    case unlisted
    case `public`
}

/// Metadata for a single upload.
public struct YouTubeUploadRequest: Sendable {
    public var title: String
    public var description: String
    public var tags: [String]
    public var categoryID: String
    public var privacy: YouTubePrivacy
    /// When set (with `.private`), YouTube auto-publishes at this time.
    public var publishAt: Date?

    public init(
        title: String,
        description: String = "",
        tags: [String] = [],
        categoryID: String = "22", // People & Blogs
        privacy: YouTubePrivacy = .private,
        publishAt: Date? = nil
    ) {
        self.title = title
        self.description = description
        self.tags = tags
        self.categoryID = categoryID
        self.privacy = privacy
        self.publishAt = publishAt
    }
}

public enum YouTubeUploadError: LocalizedError, Sendable {
    case scheduleRequiresPrivate
    case missingSessionURL
    case httpError(Int, String)
    case malformedResponse
    case fileUnreadable(String)

    public var errorDescription: String? {
        switch self {
        case .scheduleRequiresPrivate:
            "Scheduled uploads must use private privacy."
        case .missingSessionURL:
            "YouTube did not return a resumable upload URL."
        case let .httpError(code, body):
            "YouTube upload failed (HTTP \(code)): \(body)"
        case .malformedResponse:
            "YouTube returned an unreadable response."
        case let .fileUnreadable(path):
            "Cannot read clip file at \(path)."
        }
    }
}

/// Uploads a local MP4 to YouTube via the Data API v3 resumable protocol.
///
/// Marking a video as a Short is geometry-driven (vertical/square, <=3min); the
/// only API "signal" is `#Shorts` in the title/description, which the caller is
/// expected to include.
public struct YouTubeUploader: Sendable {
    /// 8 MB chunks (multiple of 256 KB, required for non-final chunks).
    private let chunkSize = 8 * 1024 * 1024
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Uploads `fileURL` and returns the new video ID.
    /// - Parameter progress: called on the main-free side with 0...1 fraction.
    public func upload(
        fileURL: URL,
        request: YouTubeUploadRequest,
        accessToken: String,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> String {
        if request.publishAt != nil, request.privacy != .private {
            throw YouTubeUploadError.scheduleRequiresPrivate
        }

        let fileSize = try fileSize(of: fileURL)
        let sessionURL = try await startSession(request: request, accessToken: accessToken, fileSize: fileSize)
        return try await uploadBytes(
            fileURL: fileURL,
            fileSize: fileSize,
            sessionURL: sessionURL,
            accessToken: accessToken,
            progress: progress
        )
    }

    // MARK: - Step 1: initiate resumable session

    private func startSession(request: YouTubeUploadRequest, accessToken: String, fileSize: Int) async throws -> URL {
        var urlRequest = URLRequest(url: YouTubeConfig.resumableUploadEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("video/*", forHTTPHeaderField: "X-Upload-Content-Type")
        urlRequest.setValue(String(fileSize), forHTTPHeaderField: "X-Upload-Content-Length")
        urlRequest.httpBody = try metadataJSON(for: request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw YouTubeUploadError.malformedResponse }
        guard (200...299).contains(http.statusCode) else {
            throw YouTubeUploadError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let location = http.value(forHTTPHeaderField: "Location"),
              let sessionURL = URL(string: location) else {
            throw YouTubeUploadError.missingSessionURL
        }
        return sessionURL
    }

    private func metadataJSON(for request: YouTubeUploadRequest) throws -> Data {
        var status: [String: Any] = ["privacyStatus": request.privacy.rawValue]
        if let publishAt = request.publishAt {
            status["publishAt"] = ISO8601DateFormatter().string(from: publishAt)
        }
        let snippet: [String: Any] = [
            "title": String(request.title.prefix(100)),
            "description": request.description,
            "tags": request.tags,
            "categoryId": request.categoryID
        ]
        let body: [String: Any] = ["snippet": snippet, "status": status]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Step 2: chunked, resumable byte upload

    private func uploadBytes(
        fileURL: URL,
        fileSize: Int,
        sessionURL: URL,
        accessToken: String,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var offset = 0
        while offset < fileSize {
            let end = min(offset + chunkSize, fileSize)
            try handle.seek(toOffset: UInt64(offset))
            let chunk = try handle.read(upToCount: end - offset) ?? Data()

            var urlRequest = URLRequest(url: sessionURL)
            urlRequest.httpMethod = "PUT"
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue(String(chunk.count), forHTTPHeaderField: "Content-Length")
            urlRequest.setValue("bytes \(offset)-\(end - 1)/\(fileSize)", forHTTPHeaderField: "Content-Range")

            let (data, response) = try await session.upload(for: urlRequest, from: chunk)
            guard let http = response as? HTTPURLResponse else { throw YouTubeUploadError.malformedResponse }

            switch http.statusCode {
            case 200, 201:
                progress(1)
                return try videoID(from: data)
            case 308:
                // Resume Incomplete — trust the server's confirmed range.
                if let confirmed = confirmedByteEnd(from: http) {
                    offset = confirmed + 1
                } else {
                    offset = end
                }
                progress(Double(offset) / Double(fileSize))
            default:
                throw YouTubeUploadError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
        }
        throw YouTubeUploadError.malformedResponse
    }

    /// Parses the upper bound from a `Range: bytes=0-N` header (308 responses).
    func confirmedByteEnd(from response: HTTPURLResponse) -> Int? {
        guard let range = response.value(forHTTPHeaderField: "Range"),
              let dash = range.lastIndex(of: "-") else { return nil }
        return Int(range[range.index(after: dash)...])
    }

    private func videoID(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else {
            throw YouTubeUploadError.malformedResponse
        }
        return id
    }

    private func fileSize(of url: URL) throws -> Int {
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int else {
            throw YouTubeUploadError.fileUnreadable(url.path)
        }
        return size
    }
}
