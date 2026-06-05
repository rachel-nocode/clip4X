import Foundation
import Testing
@testable import Clip4XCore

@Suite struct YouTubeUploaderTests {
    @Test func scheduledUploadRequiresPrivate() async {
        let uploader = YouTubeUploader()
        let request = YouTubeUploadRequest(
            title: "Test #Shorts",
            privacy: .public,
            publishAt: Date().addingTimeInterval(3600)
        )
        await #expect(throws: YouTubeUploadError.self) {
            _ = try await uploader.upload(
                fileURL: URL(fileURLWithPath: "/tmp/does-not-matter.mp4"),
                request: request,
                accessToken: "token"
            )
        }
    }

    @Test func confirmedByteEndParsesRangeHeader() {
        let uploader = YouTubeUploader()
        let response = HTTPURLResponse(
            url: URL(string: "https://upload.example/session")!,
            statusCode: 308,
            httpVersion: nil,
            headerFields: ["Range": "bytes=0-262143"]
        )!
        #expect(uploader.confirmedByteEnd(from: response) == 262143)
    }

    @Test func confirmedByteEndMissingHeaderReturnsNil() {
        let uploader = YouTubeUploader()
        let response = HTTPURLResponse(
            url: URL(string: "https://upload.example/session")!,
            statusCode: 308,
            httpVersion: nil,
            headerFields: [:]
        )!
        #expect(uploader.confirmedByteEnd(from: response) == nil)
    }

    @Test func configFromEnvironmentReadsClientID() {
        let config = YouTubeConfig.fromEnvironment([YouTubeConfig.clientIDKey: "abc.apps.googleusercontent.com"])
        #expect(config?.clientID == "abc.apps.googleusercontent.com")
        #expect(config?.clientSecret == nil)
    }

    @Test func configFromEnvironmentNilWhenUnset() {
        #expect(YouTubeConfig.fromEnvironment([:]) == nil)
    }
}
