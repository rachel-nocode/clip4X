import CryptoKit
import Foundation

public enum ZernioPlatform: String, Codable, Hashable, Sendable {
    case youtube
    case tiktok
}

public struct ZernioSourceClip: Equatable, Sendable {
    public var fileURL: URL
    public var metadata: WorkflowClipMetadata
    public var media: MediaInspection

    public init(fileURL: URL, metadata: WorkflowClipMetadata, media: MediaInspection) {
        self.fileURL = fileURL
        self.metadata = metadata
        self.media = media
    }
}

public struct ZernioScheduleItem: Equatable, Sendable {
    public var source: ZernioSourceClip
    public var scheduledAt: Date
    public var localDateTime: String

    public init(source: ZernioSourceClip, scheduledAt: Date, localDateTime: String) {
        self.source = source
        self.scheduledAt = scheduledAt
        self.localDateTime = localDateTime
    }
}

public struct ZernioSchedule: Equatable, Sendable {
    public var timezone: String
    public var items: [ZernioScheduleItem]
    public var platforms: [ZernioPlatform]

    public init(timezone: String, items: [ZernioScheduleItem], platforms: [ZernioPlatform] = [.youtube, .tiktok]) {
        self.timezone = timezone
        self.items = items
        self.platforms = platforms
    }

    public static func build(
        clips: [ZernioSourceClip],
        startDate: String,
        time: String,
        timezone: String,
        now: Date = .now
    ) throws -> ZernioSchedule {
        guard !clips.isEmpty else {
            throw Clip4XError.invalidMedia("No videos found to schedule.")
        }
        guard let zone = TimeZone(identifier: timezone) else {
            throw Clip4XError.invalidMedia("Invalid timezone \(timezone).")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.timeZone = zone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd HH:mm"
        parser.isLenient = false
        guard let first = parser.date(from: "\(startDate) \(time)") else {
            throw Clip4XError.invalidMedia("Date/time must use YYYY-MM-DD and HH:MM.")
        }

        let byName = Dictionary(uniqueKeysWithValues: clips.map { ($0.fileURL.standardizedFileURL, $0) })
        let sorted = naturalSort(clips.map(\.fileURL)).compactMap { byName[$0.standardizedFileURL] }
        for clip in sorted {
            try validateMedia(clip.media, fileName: clip.fileURL.lastPathComponent)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let items = try sorted.enumerated().map { index, clip -> ZernioScheduleItem in
            guard let date = calendar.date(byAdding: .day, value: index, to: first) else {
                throw Clip4XError.invalidMedia("Could not build schedule date.")
            }
            return ZernioScheduleItem(source: clip, scheduledAt: date, localDateTime: formatter.string(from: date))
        }
        guard let last = items.last, first > now else {
            throw Clip4XError.invalidMedia("The first scheduled time must be in the future.")
        }
        guard last.scheduledAt <= now.addingTimeInterval(7 * 24 * 3600) else {
            throw Clip4XError.invalidMedia("The final post is more than seven days away; split the batch.")
        }
        return ZernioSchedule(timezone: timezone, items: items)
    }

    public static func naturalSort(_ files: [URL]) -> [URL] {
        files.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private static func validateMedia(_ media: MediaInspection, fileName: String) throws {
        guard (3...180).contains(media.duration) else {
            throw Clip4XError.invalidMedia("\(fileName): duration must be 3–180 seconds.")
        }
        guard media.height > media.width, abs(Double(media.width) / Double(media.height) - 9.0 / 16.0) <= 0.04 else {
            throw Clip4XError.invalidMedia("\(fileName): expected vertical 9:16 video.")
        }
        guard media.videoCodec?.lowercased() == "h264", media.audioCodec?.lowercased() == "aac" else {
            throw Clip4XError.invalidMedia("\(fileName): expected H.264 video and AAC audio.")
        }
    }
}

struct ZernioPostRequest: Encodable {
    var content: String
    var scheduledFor: String
    var timezone: String
    var mediaItems: [MediaItem]
    var tiktokSettings: TikTokSettings
    var platforms: [PlatformItem]
    var tags: [String]?

    init(
        item: ZernioScheduleItem,
        timezone: String,
        mediaURL: String,
        youtubeAccountID: String,
        tiktokAccountID: String
    ) {
        content = item.source.metadata.description
        scheduledFor = item.localDateTime
        self.timezone = timezone
        mediaItems = [MediaItem(type: "video", url: mediaURL)]
        tiktokSettings = TikTokSettings()
        platforms = [
            PlatformItem(
                platform: "youtube",
                accountId: youtubeAccountID,
                platformSpecificData: YouTubeSettings(
                    title: String(item.source.metadata.title.prefix(100)),
                    visibility: "public",
                    madeForKids: false
                )
            ),
            PlatformItem(platform: "tiktok", accountId: tiktokAccountID, platformSpecificData: nil)
        ]
        tags = item.source.metadata.tags.isEmpty ? nil : item.source.metadata.tags
    }

    struct MediaItem: Encodable {
        var type: String
        var url: String
    }

    struct TikTokSettings: Encodable {
        var privacyLevel = "PUBLIC_TO_EVERYONE"
        var allowComment = true
        var allowDuet = true
        var allowStitch = true
        var contentPreviewConfirmed = true
        var expressConsentGiven = true

        enum CodingKeys: String, CodingKey {
            case privacyLevel = "privacy_level"
            case allowComment = "allow_comment"
            case allowDuet = "allow_duet"
            case allowStitch = "allow_stitch"
            case contentPreviewConfirmed = "content_preview_confirmed"
            case expressConsentGiven = "express_consent_given"
        }
    }

    struct PlatformItem: Encodable {
        var platform: String
        var accountId: String
        var platformSpecificData: YouTubeSettings?
    }

    struct YouTubeSettings: Encodable {
        var title: String
        var visibility: String
        var madeForKids: Bool
    }
}

public struct ZernioCredentials: Sendable {
    public var apiKey: String
    public var youtubeAccountID: String?
    public var tiktokAccountID: String?

    public init(apiKey: String, youtubeAccountID: String? = nil, tiktokAccountID: String? = nil) {
        self.apiKey = apiKey
        self.youtubeAccountID = youtubeAccountID
        self.tiktokAccountID = tiktokAccountID
    }

    public static func load(envFile: URL? = nil) throws -> ZernioCredentials {
        var values: [String: String] = [:]
        if let envFile, FileManager.default.fileExists(atPath: envFile.path) {
            for raw in try String(contentsOf: envFile, encoding: .utf8).split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: equals)...]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                values[key] = value
            }
        }
        for key in ["ZERNIO_API_KEY", "ZERNIO_YOUTUBE_ACCOUNT_ID", "ZERNIO_TIKTOK_ACCOUNT_ID"] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty { values[key] = value }
        }
        guard let apiKey = values["ZERNIO_API_KEY"], !apiKey.isEmpty else {
            throw Clip4XError.invalidMedia("ZERNIO_API_KEY is missing.")
        }
        return ZernioCredentials(
            apiKey: apiKey,
            youtubeAccountID: values["ZERNIO_YOUTUBE_ACCOUNT_ID"],
            tiktokAccountID: values["ZERNIO_TIKTOK_ACCOUNT_ID"]
        )
    }
}

public struct VerifiedZernioPost: Sendable {
    public var fileURL: URL
    public var scheduledAt: Date
    public var postID: String
}

struct ZernioAccountCandidate: Equatable, Sendable {
    var id: String
    var platform: String
}

public struct ZernioScheduler: Sendable {
    public var baseURL: URL
    public var session: URLSession

    public init(baseURL: URL = URL(string: "https://zernio.com/api/v1")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func plan(
        directory: URL,
        pattern: String = "*.mp4",
        startDate: String,
        time: String,
        timezone: String,
        now: Date = .now
    ) async throws -> ZernioSchedule {
        guard let ffprobe = await ToolLocator.find("ffprobe") else { throw Clip4XError.missingTool("ffprobe") }
        let metadataURL = directory.appendingPathComponent("metadata.json")
        let metadata: [String: WorkflowClipMetadata] = if FileManager.default.fileExists(atPath: metadataURL.path) {
            try JSONDecoder().decode([String: WorkflowClipMetadata].self, from: Data(contentsOf: metadataURL))
        } else {
            [:]
        }
        let matchingFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { matches($0.lastPathComponent, pattern: pattern) && ["mp4", "mov", "webm"].contains($0.pathExtension.lowercased()) }
        let files = Self.filesForCurrentBatch(matchingFiles, metadata: metadata)
        let tools = MediaTools(ffmpegPath: "ffmpeg", ffprobePath: ffprobe)
        var clips: [ZernioSourceClip] = []
        for file in ZernioSchedule.naturalSort(files) {
            let fallback = cleanTitle(file)
            clips.append(ZernioSourceClip(
                fileURL: file,
                metadata: metadata[file.lastPathComponent] ?? WorkflowClipMetadata(title: fallback, description: fallback, tags: []),
                media: try await tools.inspectMedia(videoURL: file)
            ))
        }
        return try ZernioSchedule.build(
            clips: clips,
            startDate: startDate,
            time: time,
            timezone: timezone,
            now: now
        )
    }

    public func execute(
        _ schedule: ZernioSchedule,
        credentials initialCredentials: ZernioCredentials
    ) async throws -> [VerifiedZernioPost] {
        guard !schedule.items.isEmpty else {
            throw Clip4XError.invalidMedia("No videos found to schedule.")
        }
        let credentials = initialCredentials
        var discovered: [ZernioAccountCandidate] = []
        if credentials.youtubeAccountID == nil || credentials.tiktokAccountID == nil {
            let accounts: AccountsResponse = try await request("GET", path: "accounts", apiKey: credentials.apiKey)
            discovered = accounts.accounts
                .filter { $0.isActive != false && $0.status != "disconnected" && $0.status != "deleted" }
                .map { ZernioAccountCandidate(id: $0.id, platform: $0.platform) }
        }
        let resolved = try Self.resolveAccountIDs(
            accounts: discovered,
            youtubeID: credentials.youtubeAccountID,
            tiktokID: credentials.tiktokAccountID
        )
        let youtubeID = resolved.youtube
        let tiktokID = resolved.tiktok

        let manifestURL = try manifestURL(for: schedule)
        var manifest: BatchManifest
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            do {
                manifest = try JSONDecoder().decode(BatchManifest.self, from: Data(contentsOf: manifestURL))
            } catch {
                throw Clip4XError.exportFailed("Zernio batch manifest is unreadable; reconcile it before retrying.")
            }
        } else {
            manifest = BatchManifest(timezone: schedule.timezone, items: [:])
        }
        var verified: [VerifiedZernioPost] = []
        for item in schedule.items {
            let name = item.source.fileURL.lastPathComponent
            let fingerprint = try Self.itemFingerprint(
                item: item,
                timezone: schedule.timezone,
                youtubeID: youtubeID,
                tiktokID: tiktokID
            )
            var record = manifest.items[name]
            if let existing = record, existing.fingerprint != fingerprint {
                throw Clip4XError.exportFailed(
                    "\(name) changed after scheduling began; reconcile the Zernio batch before retrying."
                )
            }
            if record == nil {
                record = ManifestItem(
                    requestID: UUID().uuidString,
                    scheduledFor: item.localDateTime,
                    fingerprint: fingerprint,
                    postID: nil
                )
            }
            guard var record else { throw Clip4XError.exportFailed("Could not create Zernio manifest record.") }
            manifest.items[name] = record
            try save(manifest, to: manifestURL)

            let postID: String
            if let existing = record.postID {
                postID = existing
            } else {
                let presign: PresignResponse = try await request(
                    "POST",
                    path: "media/presign",
                    apiKey: credentials.apiKey,
                    body: PresignRequest(filename: name, contentType: mimeType(item.source.fileURL))
                )
                try await upload(item.source.fileURL, to: presign.uploadUrl, contentType: mimeType(item.source.fileURL))
                let payload = ZernioPostRequest(
                    item: item,
                    timezone: schedule.timezone,
                    mediaURL: presign.publicUrl,
                    youtubeAccountID: youtubeID,
                    tiktokAccountID: tiktokID
                )
                do {
                    let created: PostEnvelope = try await request(
                        "POST",
                        path: "posts",
                        apiKey: credentials.apiKey,
                        requestID: record.requestID,
                        body: payload
                    )
                    guard let id = created.resolvedID else {
                        throw Clip4XError.exportFailed("Zernio create response omitted a post ID for \(name).")
                    }
                    postID = id
                } catch let error as ZernioRequestError {
                    guard error.status == 409, let id = error.existingPostID else { throw error }
                    postID = id
                }
                record.postID = postID
                manifest.items[name] = record
                try save(manifest, to: manifestURL)
            }

            let remote: PostEnvelope = try await request("GET", path: "posts/\(postID)", apiKey: credentials.apiKey)
            try verify(remote.resolvedPost, item: item, timezone: schedule.timezone)
            verified.append(VerifiedZernioPost(fileURL: item.source.fileURL, scheduledAt: item.scheduledAt, postID: postID))
        }
        return verified
    }

    private func request<Response: Decodable>(
        _ method: String,
        path: String,
        apiKey: String
    ) async throws -> Response {
        try await request(method, path: path, apiKey: apiKey, requestID: nil, body: Optional<EmptyBody>.none)
    }

    private func request<Response: Decodable, Body: Encodable>(
        _ method: String,
        path: String,
        apiKey: String,
        requestID: String? = nil,
        body: Body?
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let requestID { request.setValue(requestID, forHTTPHeaderField: "x-request-id") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Clip4XError.exportFailed("Zernio returned an unreadable response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ZernioRequestError(status: http.statusCode, body: data)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func upload(_ file: URL, to uploadURL: String, contentType: String) async throws {
        guard let url = URL(string: uploadURL), url.scheme == "https" else {
            throw Clip4XError.exportFailed("Zernio returned an invalid upload URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.upload(for: request, fromFile: file)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw Clip4XError.exportFailed("Zernio media upload failed.")
        }
    }

    private func verify(_ post: RemotePost?, item: ZernioScheduleItem, timezone: String) throws {
        guard let post, post.status == "scheduled" else {
            throw Clip4XError.exportFailed("Zernio post read-back was not scheduled.")
        }
        guard Self.remoteLocalDateTime(post.scheduledFor, timezone: timezone) == item.localDateTime else {
            throw Clip4XError.exportFailed("Zernio post read-back time did not match \(item.localDateTime).")
        }
        let platforms = Set(post.platforms.map { $0.platform.lowercased() })
        guard platforms == Set(["youtube", "tiktok"]) else {
            throw Clip4XError.exportFailed("Zernio post read-back did not contain YouTube and TikTok.")
        }
    }

    static func remoteLocalDateTime(_ raw: String?, timezone: String) -> String? {
        guard let raw else { return nil }
        if raw.hasSuffix("Z") || raw.dropFirst(10).contains("+") || raw.dropFirst(10).contains("-") {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: raw) ?? standard.date(from: raw),
                  let zone = TimeZone(identifier: timezone) else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return formatter.string(from: date)
        }
        return String(raw.prefix(19))
    }

    static func resolveAccountIDs(
        accounts: [ZernioAccountCandidate],
        youtubeID: String?,
        tiktokID: String?
    ) throws -> (youtube: String, tiktok: String) {
        func resolve(_ platform: String, explicit: String?) throws -> String {
            if let explicit, !explicit.isEmpty { return explicit }
            let candidates = accounts.filter { $0.platform.lowercased() == platform }
            guard candidates.count == 1, let id = candidates.first?.id else {
                if candidates.count > 1 {
                    throw Clip4XError.invalidMedia(
                        "Multiple active \(platform.capitalized) accounts found. Set ZERNIO_\(platform.uppercased())_ACCOUNT_ID."
                    )
                }
                throw Clip4XError.invalidMedia(
                    "One active \(platform.capitalized) account is required. Set ZERNIO_\(platform.uppercased())_ACCOUNT_ID."
                )
            }
            return id
        }
        return (
            youtube: try resolve("youtube", explicit: youtubeID),
            tiktok: try resolve("tiktok", explicit: tiktokID)
        )
    }

    static func itemFingerprint(
        item: ZernioScheduleItem,
        timezone: String,
        youtubeID: String,
        tiktokID: String
    ) throws -> String {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: item.source.fileURL)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        hasher.update(data: try encoder.encode(item.source.metadata))
        hasher.update(data: Data("\(item.localDateTime)|\(timezone)|\(youtubeID)|\(tiktokID)".utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func filesForCurrentBatch(
        _ files: [URL],
        metadata: [String: WorkflowClipMetadata]
    ) -> [URL] {
        guard !metadata.isEmpty else { return files }
        return files.filter { metadata[$0.lastPathComponent] != nil }
    }

    private func manifestURL(for schedule: ZernioSchedule) throws -> URL {
        let directory = schedule.items[0].source.fileURL.deletingLastPathComponent()
            .appendingPathComponent(".zernio-batches", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = "\(directory.path)|\(schedule.timezone)|\(schedule.items.map(\.localDateTime).joined(separator: ","))"
        let hash = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16)
        return directory.appendingPathComponent("\(hash).json")
    }

    private func save(_ manifest: BatchManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private func cleanTitle(_ file: URL) -> String {
        let stem = file.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"^\d+[\s._-]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[-_ ]*v\d+$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return String(stem.capitalized.prefix(100))
    }

    private func matches(_ name: String, pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: #"\*"#, with: ".*")
            .replacingOccurrences(of: #"\?"#, with: ".")
        return name.range(of: "^\(escaped)$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func mimeType(_ file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "mov": "video/quicktime"
        case "webm": "video/webm"
        default: "video/mp4"
        }
    }
}

private struct EmptyBody: Encodable {}
private struct PresignRequest: Encodable { var filename: String; var contentType: String }
private struct PresignResponse: Decodable { var uploadUrl: String; var publicUrl: String }

private struct AccountsResponse: Decodable {
    var accounts: [RemoteAccount]

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([RemoteAccount].self) {
            accounts = array
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accounts = try container.decode([RemoteAccount].self, forKey: .accounts)
        }
    }

    private enum CodingKeys: String, CodingKey { case accounts }
}

private struct RemoteAccount: Decodable {
    var id: String
    var platform: String
    var isActive: Bool?
    var status: String?

    private enum CodingKeys: String, CodingKey { case id, mongoID = "_id", platform, isActive, status }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .mongoID)
        platform = try container.decode(String.self, forKey: .platform)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive)
        status = try container.decodeIfPresent(String.self, forKey: .status)
    }
}

private struct PostEnvelope: Decodable {
    var post: RemotePost?
    var existingPost: RemotePost?
    var existingPostId: String?
    var id: String?
    var mongoID: String?
    var status: String?
    var scheduledFor: String?
    var platforms: [RemotePlatform]?

    var resolvedID: String? { post?.id ?? existingPost?.id ?? existingPostId ?? id ?? mongoID }
    var resolvedPost: RemotePost? {
        post ?? existingPost ?? resolvedID.map {
            RemotePost(id: $0, status: status, scheduledFor: scheduledFor, platforms: platforms ?? [])
        }
    }

    enum CodingKeys: String, CodingKey {
        case post, existingPost, existingPostId, id, mongoID = "_id", status, scheduledFor, platforms
    }
}

private struct RemotePost: Decodable {
    var id: String?
    var status: String?
    var scheduledFor: String?
    var platforms: [RemotePlatform]

    enum CodingKeys: String, CodingKey { case id, mongoID = "_id", status, scheduledFor, platforms }

    init(id: String?, status: String?, scheduledFor: String?, platforms: [RemotePlatform]) {
        self.id = id
        self.status = status
        self.scheduledFor = scheduledFor
        self.platforms = platforms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .mongoID)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        scheduledFor = try container.decodeIfPresent(String.self, forKey: .scheduledFor)
        platforms = try container.decodeIfPresent([RemotePlatform].self, forKey: .platforms) ?? []
    }
}

private struct RemotePlatform: Decodable { var platform: String }

private struct BatchManifest: Codable {
    var timezone: String
    var items: [String: ManifestItem]
}

private struct ManifestItem: Codable {
    var requestID: String
    var scheduledFor: String
    var fingerprint: String?
    var postID: String?
}

struct ZernioRequestError: LocalizedError {
    var status: Int
    var body: Data

    var existingPostID: String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        if let id = object["existingPostId"] as? String { return id }
        if let post = object["existingPost"] as? [String: Any] {
            return post["id"] as? String ?? post["_id"] as? String
        }
        return nil
    }

    var errorDescription: String? {
        "Zernio HTTP \(status). Check account connections, privacy settings, and schedule details."
    }
}
