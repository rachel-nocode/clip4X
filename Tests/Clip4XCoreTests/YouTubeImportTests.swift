import Foundation
import Testing
@testable import Clip4XCore

@Suite struct YouTubeImportTests {
    @Test func parsesWatchURL() {
        #expect(YouTubeVideoID.parse("https://www.youtube.com/watch?v=dQw4w9wgWcQ") == "dQw4w9wgWcQ")
        #expect(YouTubeVideoID.parse("https://youtube.com/watch?v=dQw4w9wgWcQ&t=12s") == "dQw4w9wgWcQ")
        #expect(YouTubeVideoID.parse("www.youtube.com/watch?v=dQw4w9wgWcQ") == "dQw4w9wgWcQ")
    }

    @Test func parsesShortShareAndLiveURLs() {
        #expect(YouTubeVideoID.parse("https://youtu.be/dQw4w9wgWcQ") == "dQw4w9wgWcQ")
        #expect(YouTubeVideoID.parse("https://www.youtube.com/shorts/dQw4w9wgWcQ") == "dQw4w9wgWcQ")
        #expect(YouTubeVideoID.parse("https://www.youtube.com/live/dQw4w9wgWcQ") == "dQw4w9wgWcQ")
        #expect(YouTubeVideoID.parse("https://www.youtube.com/embed/dQw4w9wgWcQ") == "dQw4w9wgWcQ")
    }

    @Test func parsesRawVideoID() {
        #expect(YouTubeVideoID.parse("dQw4w9wgWcQ") == "dQw4w9wgWcQ")
        #expect(YouTubeVideoID.parse("  dQw4w9wgWcQ  ") == "dQw4w9wgWcQ")
    }

    @Test func rejectsGarbage() {
        #expect(YouTubeVideoID.parse("") == nil)
        #expect(YouTubeVideoID.parse("not a url") == nil)
        #expect(YouTubeVideoID.parse("https://example.com/watch?v=dQw4w9wgWcQ") == "dQw4w9wgWcQ")
        #expect(YouTubeVideoID.parse("https://vimeo.com/12345") == nil)
        #expect(YouTubeVideoID.parse("shortid") == nil)
    }

    @Test func parseChannelIDReadsFirstItem() throws {
        let data = Data(#"{"items":[{"id":"UCminechannel"}]}"#.utf8)
        #expect(try YouTubeLibrary.parseChannelID(from: data) == "UCminechannel")
    }

    @Test func parseChannelIDEmptyThrows() {
        let data = Data(#"{"items":[]}"#.utf8)
        #expect(throws: YouTubeImportError.self) {
            _ = try YouTubeLibrary.parseChannelID(from: data)
        }
    }

    @Test func parseVideoReadsSnippet() throws {
        let data = Data(#"""
        {"items":[{"id":"dQw4w9wgWcQ","snippet":{"title":"My talk","channelId":"UCminechannel"}}]}
        """#.utf8)
        let video = try YouTubeLibrary.parseVideo(from: data)
        #expect(video.id == "dQw4w9wgWcQ")
        #expect(video.title == "My talk")
        #expect(video.channelID == "UCminechannel")
    }

    @Test func parseVideoMissingThrows() {
        let data = Data(#"{"items":[]}"#.utf8)
        #expect(throws: YouTubeImportError.self) {
            _ = try YouTubeLibrary.parseVideo(from: data)
        }
    }

    @Test func ownershipAcceptsMatchingChannel() throws {
        let video = YouTubeOwnedVideo(id: "dQw4w9wgWcQ", title: "My talk", channelID: "UCminechannel")
        let owned = try YouTubeLibrary.confirmOwnership(video: video, channelID: "UCminechannel")
        #expect(owned.id == "dQw4w9wgWcQ")
    }

    @Test func ownershipRejectsOtherChannel() {
        let video = YouTubeOwnedVideo(id: "dQw4w9wgWcQ", title: "Someone else", channelID: "UCother")
        #expect(throws: YouTubeImportError.self) {
            _ = try YouTubeLibrary.confirmOwnership(video: video, channelID: "UCminechannel")
        }
    }

    @Test func mapsPrivateDownloadErrors() {
        #expect(
            YouTubeDownloader.mapDownloadFailure("ERROR: Private video")
                == .privateDownloadFailed
        )
        #expect(
            YouTubeDownloader.mapDownloadFailure("Sign in to confirm your age")
                == .privateDownloadFailed
        )
        if case let .downloadFailed(detail) = YouTubeDownloader.mapDownloadFailure("HTTP 429") {
            #expect(detail.contains("429"))
        } else {
            Issue.record("Expected downloadFailed")
        }
    }

    @Test func importErrorsExposeReadableDescriptions() {
        #expect(YouTubeImportError.invalidURL.errorDescription == "Paste a YouTube video URL or video ID.")
        #expect(YouTubeImportError.privateDownloadFailed.errorDescription?.contains("private") == true)
    }

    @Test func configScopesIncludeReadonly() {
        #expect(YouTubeConfig.scopes.contains(YouTubeConfig.scope))
        #expect(YouTubeConfig.scopes.contains(YouTubeConfig.readonlyScope))
    }
}
