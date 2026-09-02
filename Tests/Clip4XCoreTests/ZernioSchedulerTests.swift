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
    }
}
