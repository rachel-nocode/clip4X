import Foundation
import Testing
@testable import Clip4XCore

@Suite struct ZernioSchedulerTests {
    private func source(_ name: String) -> ZernioSourceClip {
        ZernioSourceClip(
            fileURL: URL(fileURLWithPath: "/tmp/\(name)"),
            metadata: WorkflowClipMetadata(title: name, description: name, tags: ["AI"]),
            media: MediaInspection(width: 1080, height: 1920, duration: 30, videoCodec: "h264", audioCodec: "aac")
        )
    }

    @Test func scheduleKeepsLocalClockAcrossDSTAndTargetsBothPlatforms() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 8)))
        let schedule = try ZernioSchedule.build(
            clips: [source("01-first.mp4"), source("02-second.mp4")],
            startDate: "2026-10-31",
            time: "08:00",
            timezone: zone.identifier,
            now: now
        )

        #expect(schedule.platforms == [.youtube, .tiktok])
        #expect(schedule.items.map(\.localDateTime) == ["2026-10-31T08:00:00", "2026-11-01T08:00:00"])
        #expect(schedule.items[1].scheduledAt.timeIntervalSince(schedule.items[0].scheduledAt) == 25 * 3600)
    }

    @Test func scheduleNaturalSortsFiles() {
        let sorted = ZernioSchedule.naturalSort([
            URL(fileURLWithPath: "/tmp/10-last.mp4"),
            URL(fileURLWithPath: "/tmp/2-middle.mp4"),
            URL(fileURLWithPath: "/tmp/1-first.mp4")
        ])
        #expect(sorted.map(\.lastPathComponent) == ["1-first.mp4", "2-middle.mp4", "10-last.mp4"])
    }

    @Test func scheduleRejectsTemporaryUploadBeyondSevenDays() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 7)))
        #expect(throws: Clip4XError.self) {
            _ = try ZernioSchedule.build(
                clips: (1...8).map { source(String(format: "%02d.mp4", $0)) },
                startDate: "2026-09-02",
                time: "08:00",
                timezone: zone.identifier,
                now: now
            )
        }
    }

    @Test func postPayloadReusesMediaForYouTubeAndTikTokWithoutPublishNow() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let item = ZernioScheduleItem(
            source: source("01-first.mp4"),
            scheduledAt: try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 8))),
            localDateTime: "2026-09-02T08:00:00"
        )
        let payload = ZernioPostRequest(
            item: item,
            timezone: zone.identifier,
            mediaURL: "https://media.example/video.mp4",
            youtubeAccountID: "youtube-id",
            tiktokAccountID: "tiktok-id"
        )
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        let platforms = try #require(object["platforms"] as? [[String: Any]])
        let media = try #require(object["mediaItems"] as? [[String: Any]])

        #expect(Set(platforms.compactMap { $0["platform"] as? String }) == ["youtube", "tiktok"])
        #expect(media.count == 1)
        #expect(media[0]["url"] as? String == "https://media.example/video.mp4")
        #expect(object["scheduledFor"] as? String == "2026-09-02T08:00:00")
        #expect(object["publishNow"] == nil)
    }

    @Test func zernioErrorsDoNotExposeResponseBodies() {
        let error = ZernioRequestError(
            status: 400,
            body: Data(#"{"uploadUrl":"https://secret.example/token","accountId":"acct-secret"}"#.utf8)
        )
        #expect(error.errorDescription == "Zernio HTTP 400. Check account connections, privacy settings, and schedule details.")
        #expect(error.errorDescription?.contains("secret") == false)
        #expect(error.existingPostID == nil)
        #expect(ZernioRequestError(status: 409, body: Data(#"{"existingPostId":"post-1"}"#.utf8)).existingPostID == "post-1")
    }

    @Test func metadataLimitsSchedulingToCurrentRenderVersions() {
        let files = ["01-hook.mp4", "01-hook-v2.mp4", "02-demo.mp4"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        let metadata = [
            "01-hook-v2.mp4": WorkflowClipMetadata(title: "Hook", description: "", tags: []),
            "02-demo.mp4": WorkflowClipMetadata(title: "Demo", description: "", tags: [])
        ]
        #expect(ZernioScheduler.filesForCurrentBatch(files, metadata: metadata).map(\.lastPathComponent) == ["01-hook-v2.mp4", "02-demo.mp4"])
    }

    @Test func accountDiscoveryRejectsAmbiguousPlatforms() {
        let accounts = [
            ZernioAccountCandidate(id: "yt-1", platform: "youtube"),
            ZernioAccountCandidate(id: "yt-2", platform: "youtube"),
            ZernioAccountCandidate(id: "tt-1", platform: "tiktok")
        ]
        #expect(throws: Clip4XError.self) {
            _ = try ZernioScheduler.resolveAccountIDs(
                accounts: accounts,
                youtubeID: nil,
                tiktokID: nil
            )
        }
    }

    @Test func accountDiscoveryUsesOnlyUnambiguousPlatforms() throws {
        let resolved = try ZernioScheduler.resolveAccountIDs(
            accounts: [
                ZernioAccountCandidate(id: "yt-1", platform: "youtube"),
                ZernioAccountCandidate(id: "tt-1", platform: "tiktok")
            ],
            youtubeID: nil,
            tiktokID: nil
        )
        #expect(resolved.youtube == "yt-1")
        #expect(resolved.tiktok == "tt-1")
    }

    @Test func remoteTimesParseWithAndWithoutFractionalSeconds() {
        #expect(
            ZernioScheduler.remoteLocalDateTime(
                "2026-09-02T15:00:00.000Z",
                timezone: "America/Los_Angeles"
            ) == "2026-09-02T08:00:00"
        )
        #expect(
            ZernioScheduler.remoteLocalDateTime(
                "2026-09-02T15:00:00Z",
                timezone: "America/Los_Angeles"
            ) == "2026-09-02T08:00:00"
        )
    }

    @Test func manifestFingerprintChangesWithFileMetadataOrTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip4x-zernio-fingerprint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("clip.mp4")
        try Data("first".utf8).write(to: file)
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 8)))
        let source = ZernioSourceClip(
            fileURL: file,
            metadata: WorkflowClipMetadata(title: "Title", description: "Description", tags: ["AI"]),
            media: MediaInspection(width: 1080, height: 1920, duration: 30, videoCodec: "h264", audioCodec: "aac")
        )
        let item = ZernioScheduleItem(source: source, scheduledAt: date, localDateTime: "2026-09-02T08:00:00")
        let first = try ZernioScheduler.itemFingerprint(item: item, timezone: zone.identifier, youtubeID: "yt", tiktokID: "tt")

        try Data("second".utf8).write(to: file)
        let changedFile = try ZernioScheduler.itemFingerprint(item: item, timezone: zone.identifier, youtubeID: "yt", tiktokID: "tt")
        var changedMetadataItem = item
        changedMetadataItem.source.metadata.title = "New title"
        let changedMetadata = try ZernioScheduler.itemFingerprint(item: changedMetadataItem, timezone: zone.identifier, youtubeID: "yt", tiktokID: "tt")
        let changedTarget = try ZernioScheduler.itemFingerprint(item: changedMetadataItem, timezone: zone.identifier, youtubeID: "yt-2", tiktokID: "tt")

        #expect(first != changedFile)
        #expect(changedFile != changedMetadata)
        #expect(changedMetadata != changedTarget)
    }

    @Test func executeUploadsCreatesVerifiesAndResumesWithoutDuplicatePost() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip4x-zernio-http-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("clip.mp4")
        try Data("video".utf8).write(to: file)
        let item = ZernioScheduleItem(
            source: ZernioSourceClip(
                fileURL: file,
                metadata: WorkflowClipMetadata(title: "Title", description: "Description", tags: []),
                media: MediaInspection(width: 1080, height: 1920, duration: 30, videoCodec: "h264", audioCodec: "aac")
            ),
            scheduledAt: Date(timeIntervalSince1970: 1_788_368_400),
            localDateTime: "2026-09-02T08:00:00"
        )
        let schedule = ZernioSchedule(timezone: "America/Los_Angeles", items: [item])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ZernioMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        ZernioMockURLProtocol.reset()
        let scheduler = ZernioScheduler(baseURL: URL(string: "https://api.test/v1")!, session: session)
        let credentials = ZernioCredentials(apiKey: "secret", youtubeAccountID: "yt", tiktokAccountID: "tt")

        let first = try await scheduler.execute(schedule, credentials: credentials)
        let second = try await scheduler.execute(schedule, credentials: credentials)

        #expect(first.map(\.postID) == ["post-1"])
        #expect(second.map(\.postID) == ["post-1"])
        #expect(ZernioMockURLProtocol.count(method: "POST", suffix: "/media/presign") == 1)
        #expect(ZernioMockURLProtocol.count(method: "PUT", suffix: "/upload") == 1)
        #expect(ZernioMockURLProtocol.count(method: "POST", suffix: "/posts") == 1)
        #expect(ZernioMockURLProtocol.count(method: "GET", suffix: "/posts/post-1") == 2)

        try Data("changed-video".utf8).write(to: file)
        await #expect(throws: Clip4XError.self) {
            _ = try await scheduler.execute(schedule, credentials: credentials)
        }
        #expect(ZernioMockURLProtocol.count(method: "POST", suffix: "/posts") == 1)

        try Data("video".utf8).write(to: file)
        let manifestDirectory = root.appendingPathComponent(".zernio-batches")
        let manifestName = try #require(FileManager.default.contentsOfDirectory(atPath: manifestDirectory.path).first)
        try Data("not-json".utf8).write(to: manifestDirectory.appendingPathComponent(manifestName))
        await #expect(throws: Clip4XError.self) {
            _ = try await scheduler.execute(schedule, credentials: credentials)
        }
        #expect(ZernioMockURLProtocol.count(method: "POST", suffix: "/posts") == 1)
    }
}

private final class ZernioMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var requests: [(String, String)] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); requests = []; lock.unlock()
    }

    static func count(method: String, suffix: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.0 == method && $0.1.hasSuffix(suffix) }.count
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        Self.lock.lock(); Self.requests.append((method, path)); Self.lock.unlock()
        let body: String
        if method == "POST", path.hasSuffix("/media/presign") {
            body = #"{"uploadUrl":"https://upload.test/upload","publicUrl":"https://media.test/clip.mp4"}"#
        } else if method == "POST", path.hasSuffix("/posts") {
            body = #"{"post":{"_id":"post-1"}}"#
        } else if method == "GET", path.hasSuffix("/posts/post-1") {
            body = #"{"post":{"_id":"post-1","status":"scheduled","scheduledFor":"2026-09-02T15:00:00.000Z","platforms":[{"platform":"youtube"},{"platform":"tiktok"}]}}"#
        } else {
            body = "{}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
