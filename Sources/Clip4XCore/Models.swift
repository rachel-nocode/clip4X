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
}

public struct VideoSize: Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct TranscriptSegment: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String

    public init(id: UUID = UUID(), start: Double, end: Double, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
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

public struct CropPlan: Hashable, Sendable {
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
        exportURL: URL? = nil
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
