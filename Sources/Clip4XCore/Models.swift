import Foundation

public enum ExportRatio: String, CaseIterable, Identifiable, Sendable {
    case vertical
    case square

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .vertical: "9:16"
        case .square: "1:1"
        }
    }

    public var outputSize: VideoSize {
        switch self {
        case .vertical: VideoSize(width: 1080, height: 1920)
        case .square: VideoSize(width: 1080, height: 1080)
        }
    }

    public var aspectRatio: Double {
        Double(outputSize.width) / Double(outputSize.height)
    }

    public static func parse(_ raw: String) -> ExportRatio? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "9:16", "916", "vertical", "portrait": .vertical
        case "1:1", "11", "square": .square
        default: nil
        }
    }
}

public enum ExportLayout: String, CaseIterable, Identifiable, Sendable {
    case auto
    case stack
    case face
    case fit

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .stack: "Stack"
        case .face: "Face"
        case .fit: "Fit"
        }
    }

    public var detail: String {
        switch self {
        case .auto: "Stack when a demo window is found, else face crop, else fit"
        case .stack: "Face on the bottom, rounded demo window on top"
        case .face: "Tight 9:16 crop around the speaker"
        case .fit: "Keep the full frame, letterboxed on a blur fill"
        }
    }

    public var systemImage: String {
        switch self {
        case .auto: "wand.and.stars"
        case .stack: "rectangle.stack"
        case .face: "person.crop.rectangle"
        case .fit: "arrow.up.left.and.arrow.down.right"
        }
    }
}

public struct StackStyle: Hashable, Sendable {
    public var faceBand: Double
    public var demoTopPadding: Int
    public var demoSidePadding: Int
    public var demoOverlap: Int
    public var cornerRadius: Int

    public init(
        faceBand: Double = 0.66,
        demoTopPadding: Int = 56,
        demoSidePadding: Int = 52,
        demoOverlap: Int = 96,
        cornerRadius: Int = 32
    ) {
        self.faceBand = min(0.82, max(0.42, faceBand))
        self.demoTopPadding = PixelMath.even(max(16, demoTopPadding))
        self.demoSidePadding = PixelMath.even(max(16, demoSidePadding))
        self.demoOverlap = PixelMath.even(max(0, demoOverlap))
        self.cornerRadius = max(8, cornerRadius)
    }

    public static let talkingHead = StackStyle()
}

public struct ExportOptions: Hashable, Sendable {
    public var ratio: ExportRatio
    public var layout: ExportLayout
    public var style: StackStyle
    public var faceOverride: NormalizedRect?
    public var demoOverride: NormalizedRect?
    public var captions: Bool

    public init(
        ratio: ExportRatio = .vertical,
        layout: ExportLayout = .auto,
        style: StackStyle = .talkingHead,
        faceOverride: NormalizedRect? = nil,
        demoOverride: NormalizedRect? = nil,
        captions: Bool = true
    ) {
        self.ratio = ratio
        self.layout = layout
        self.style = style
        self.faceOverride = faceOverride
        self.demoOverride = demoOverride
        self.captions = captions
    }
}

public struct VideoSize: Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct TranscriptWord: Codable, Hashable, Sendable {
    public var word: String
    public var start: Double
    public var end: Double

    public init(word: String, start: Double, end: Double) {
        self.word = word
        self.start = start
        self.end = end
    }
}

public struct TranscriptSegment: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    public var words: [TranscriptWord]

    public init(id: UUID = UUID(), start: Double, end: Double, text: String, words: [TranscriptWord] = []) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, text, words
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try container.decode(Double.self, forKey: .start)
        end = try container.decode(Double.self, forKey: .end)
        text = try container.decode(String.self, forKey: .text)
        words = try container.decodeIfPresent([TranscriptWord].self, forKey: .words) ?? []
    }
}

public enum TextBand: String, Codable, Sendable {
    case top
    case bottom
}

public struct TextLayout: Hashable, Sendable {
    public var hookBand: TextBand
    public var captionBand: TextBand

    public init(hookBand: TextBand, captionBand: TextBand) {
        self.hookBand = hookBand
        self.captionBand = captionBand
    }

    public static let split = TextLayout(hookBand: .top, captionBand: .bottom)
}

public struct CropPlan: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var ffmpegFilter: String {
        "crop=\(width):\(height):\(x):\(y)"
    }
}

public struct TimedOverlay: Hashable, Sendable {
    public var url: URL
    public var start: Double
    public var end: Double

    public init(url: URL, start: Double, end: Double) {
        self.url = url
        self.start = start
        self.end = end
    }
}

public enum UploadState: Hashable, Sendable {
    case idle
    case uploading(progress: Double)
    case scheduled(Date)
    case published
    case failed(String)
}

public struct ClipCandidate: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var theme: String
    public var reason: String
    public var start: Double
    public var end: Double
    public var score: Int
    public var transcript: [TranscriptSegment]
    public var isSelected: Bool
    public var exportURL: URL?
    public var youtubeVideoID: String?
    public var uploadState: UploadState

    public init(
        id: UUID = UUID(),
        title: String,
        theme: String,
        reason: String,
        start: Double,
        end: Double,
        score: Int,
        transcript: [TranscriptSegment],
        isSelected: Bool = true,
        exportURL: URL? = nil,
        youtubeVideoID: String? = nil,
        uploadState: UploadState = .idle
    ) {
        self.id = id
        self.title = title
        self.theme = theme
        self.reason = reason
        self.start = start
        self.end = end
        self.score = score
        self.transcript = transcript
        self.isSelected = isSelected
        self.exportURL = exportURL
        self.youtubeVideoID = youtubeVideoID
        self.uploadState = uploadState
    }

    public var youtubeURL: URL? {
        guard let youtubeVideoID else { return nil }
        return URL(string: "https://youtu.be/\(youtubeVideoID)")
    }

    public var duration: Double {
        max(0, end - start)
    }

    public var displayDuration: String {
        DurationFormatter.short(duration)
    }
}

public enum Clip4XError: LocalizedError, Sendable {
    case missingTool(String)
    case commandFailed(String, Int32, String)
    case invalidMedia(String)
    case noTranscript
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .missingTool(tool):
            "\(tool) is missing. Install it or add it to PATH."
        case let .commandFailed(command, status, stderr):
            "\(command) failed with exit \(status): \(stderr)"
        case let .invalidMedia(reason):
            reason
        case .noTranscript:
            "Whisper did not return transcript segments."
        case let .exportFailed(reason):
            reason
        }
    }
}

public enum DurationFormatter {
    public static func short(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }
}
