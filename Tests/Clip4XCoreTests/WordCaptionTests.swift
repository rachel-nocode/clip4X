import Foundation
import Testing
@testable import Clip4XCore

@Suite struct WordCaptionTests {
    @Test func wordsBecomeClipLocalCaptionCards() {
        let words = [
            TranscriptWord(word: "Strong", start: 10, end: 10.4),
            TranscriptWord(word: "hook.", start: 10.4, end: 11),
            TranscriptWord(word: "Next", start: 11.2, end: 11.5),
            TranscriptWord(word: "idea", start: 11.5, end: 11.9)
        ]

        let cards = CaptionTimeline.cards(
            words: words,
            clipStart: 10,
            clipEnd: 20,
            maxWords: 2,
            maxCharacters: 28
        )

        #expect(cards.count == 2)
        #expect(cards[0].text == "Strong hook.")
        #expect(cards[0].start == 0)
        #expect(cards[0].end == 1.08)
        #expect(cards[1].text == "Next idea")
        #expect(abs(cards[1].start - 1.2) < 0.000_001)
    }

    @Test func cardsClampBeforeNextCard() {
        let cards = CaptionTimeline.cards(
            words: [
                TranscriptWord(word: "One", start: 0, end: 1),
                TranscriptWord(word: "Two", start: 1.02, end: 2)
            ],
            clipStart: 0,
            clipEnd: 3,
            maxWords: 1,
            maxCharacters: 28
        )
        #expect(cards[0].end == 1.01)
        #expect(cards[0].end < cards[1].start)
    }

    @Test func transcriptWithoutWordsStillDecodes() throws {
        let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","start":1,"end":2,"text":"Hello"}"#.utf8)
        let segment = try JSONDecoder().decode(TranscriptSegment.self, from: data)
        #expect(segment.words.isEmpty)
    }
}
