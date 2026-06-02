import Testing
@testable import Clip4XCore

@Test func detectorPrefersViewerFacingPayoff() {
    let segments = [
        TranscriptSegment(start: 0, end: 4, text: "Today I am testing a workflow and setting up the context."),
        TranscriptSegment(start: 4, end: 10, text: "Here is the problem with most clipping tools."),
        TranscriptSegment(start: 10, end: 18, text: "They give you random cuts but they do not know what the viewer gets from it."),
        TranscriptSegment(start: 18, end: 29, text: "Instead you can use the transcript to find one idea and keep the payoff clean."),
        TranscriptSegment(start: 29, end: 40, text: "Because the clip has one clear promise, it works better on social."),
        TranscriptSegment(start: 40, end: 50, text: "Then you export vertical or square versions without rebuilding the edit.")
    ]

    let detector = ClipMomentDetector(minDuration: 16, maxDuration: 48, maxClips: 3)
    let clips = detector.detect(in: segments, sourceDuration: 55)

    #expect(!clips.isEmpty)
    #expect(clips.first?.score ?? 0 >= 70)
    #expect(clips.contains { $0.transcript.map(\.text).joined().contains("Instead you can use") })
}

@Test func detectorAvoidsHeavyOverlap() {
    let segments = (0..<12).map { index in
        TranscriptSegment(
            start: Double(index * 5),
            end: Double(index * 5 + 5),
            text: "Here is why this better workflow matters because you can move faster segment \(index)."
        )
    }

    let detector = ClipMomentDetector(minDuration: 15, maxDuration: 30, maxClips: 4)
    let clips = detector.detect(in: segments, sourceDuration: 65)

    #expect(clips.count <= 4)
    for index in clips.indices.dropFirst() {
        let previous = clips[index - 1]
        let current = clips[index]
        let overlap = max(0, min(previous.end, current.end) - max(previous.start, current.start))
        #expect(overlap < min(previous.duration, current.duration) * 0.6)
    }
}
