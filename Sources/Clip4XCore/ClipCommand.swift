import Foundation

public enum ClipVerb: String, CaseIterable, Sendable {
    case analyze
    case export
    case run
    case frame
    case help
}

public struct ClipInvocation: Equatable, Sendable {
    public var verb: ClipVerb
    public var videoPath: String?
    public var json: Bool
    public var outputPath: String?
    public var layout: ExportLayout
    public var ratio: ExportRatio
    public var start: Double?
    public var end: Double?
    public var title: String?
    public var face: NormalizedRect?
    public var demo: NormalizedRect?
    public var faceBand: Double?
    public var maxClips: Int
    public var at: Double?
    public var clipIndex: Int?
    public var captions: Bool

    public init(
        verb: ClipVerb,
        videoPath: String? = nil,
        json: Bool = false,
        outputPath: String? = nil,
        layout: ExportLayout = .auto,
        ratio: ExportRatio = .vertical,
        start: Double? = nil,
        end: Double? = nil,
        title: String? = nil,
        face: NormalizedRect? = nil,
        demo: NormalizedRect? = nil,
        faceBand: Double? = nil,
        maxClips: Int = 8,
        at: Double? = nil,
        clipIndex: Int? = nil,
        captions: Bool = true
    ) {
        self.verb = verb
        self.videoPath = videoPath
        self.json = json
        self.outputPath = outputPath
        self.layout = layout
        self.ratio = ratio
        self.start = start
        self.end = end
        self.title = title
        self.face = face
        self.demo = demo
        self.faceBand = faceBand
        self.maxClips = maxClips
        self.at = at
        self.clipIndex = clipIndex
        self.captions = captions
    }

    public var exportOptions: ExportOptions {
        ExportOptions(
            ratio: ratio,
            layout: layout,
            style: StackStyle(faceBand: faceBand ?? 0.66),
            faceOverride: face,
            demoOverride: demo,
            captions: captions
        )
    }

    public static let helpText = """
    clip4x — cut talking-head + demo videos into vertical Shorts from the terminal.

    Usage:
      clip4x run VIDEO [options]         Transcribe, rank, and export
      clip4x analyze VIDEO [--json]      Find clip moments only
      clip4x export VIDEO [options]      Export (uses --start/--end or detect)
      clip4x frame VIDEO [--at SEC]      Write one composed PNG to tune crop
      clip4x help

    Layouts:
      auto   Stack when a demo window is found, else face crop, else fit (default)
      stack  Face in the lower ~66%, rounded demo card on top — the Shorts look
      face   Tight crop around the speaker (cuts the demo if it sits above you)
      fit    Full frame letterboxed on a blur fill (keeps everything, small)

    Precision:
      1. Record landscape with your face large in the lower half and the
         product window visible (above you or beside you).
      2. Preview the crop:
           clip4x frame talk.mov --layout stack --out /tmp/preview.png
      3. If the window or face is off, pin normalized regions (x,y,w,h in 0...1,
         origin top-left) printed by `--json`:
           clip4x frame talk.mov --at 8 --json --layout stack \\
             --face 0.22,0.46,0.56,0.50 --demo 0.16,0.04,0.68,0.36 \\
             --out /tmp/preview.png
      4. Export:
           clip4x run talk.mov --layout stack --out ~/Desktop/Clip4X\\ Exports

    Options:
      --layout auto|stack|face|fit
      --ratio 9:16|1:1
      --out PATH
      --start SEC  --end SEC     Manual clip window (export)
      --title TEXT
      --face x,y,w,h             Normalized speaker crop
      --demo x,y,w,h             Normalized demo-window crop
      --face-band 0.66           How much of the 9:16 frame the face occupies
      --at SEC                   Timestamp for `frame`
      --clip-index N             Export only this detected clip (0-based)
      --max-clips N
      --no-captions
      --json
    """
}

public enum ClipCommand {
    public static func parse(_ arguments: [String]) throws -> ClipInvocation {
        if arguments.isEmpty || arguments.contains(where: { ["-h", "--help", "help"].contains($0) }) {
            return ClipInvocation(verb: .help)
        }

        var tokens = arguments
        let verbs = Set(ClipVerb.allCases.map(\.rawValue))
        let verb: ClipVerb
        if let first = tokens.first, verbs.contains(first), let parsed = ClipVerb(rawValue: first) {
            verb = parsed
            tokens.removeFirst()
        } else {
            verb = .run
        }

        var invocation = ClipInvocation(verb: verb)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "--json" {
                invocation.json = true
            } else if token == "--no-captions" {
                invocation.captions = false
            } else if token.hasPrefix("--") {
                let body = String(token.dropFirst(2))
                let name: String
                let value: String
                if let equals = body.firstIndex(of: "=") {
                    name = String(body[..<equals])
                    value = String(body[body.index(after: equals)...])
                } else {
                    name = body
                    guard index + 1 < tokens.count else {
                        throw Clip4XError.invalidMedia("Missing value for --\(name).")
                    }
                    index += 1
                    value = tokens[index]
                }
                try apply(flag: name, value: value, to: &invocation)
            } else if token.hasPrefix("-") {
                throw Clip4XError.invalidMedia("Unknown flag \(token).")
            } else if invocation.videoPath == nil {
                invocation.videoPath = token
            } else {
                throw Clip4XError.invalidMedia("Unexpected argument '\(token)'.")
            }
            index += 1
        }

        if verb != .help, invocation.videoPath == nil {
            throw Clip4XError.invalidMedia("Pass a video path. See clip4x help.")
        }
        return invocation
    }

    private static func apply(flag: String, value: String, to invocation: inout ClipInvocation) throws {
        let name = flag.split(separator: "=").first.map(String.init) ?? flag
        let resolved = value
        switch name {
        case "out", "output":
            invocation.outputPath = resolved
        case "layout":
            guard let layout = ExportLayout(rawValue: resolved.lowercased()) else {
                throw Clip4XError.invalidMedia("Layout must be auto, stack, face, or fit.")
            }
            invocation.layout = layout
        case "ratio":
            guard let ratio = ExportRatio.parse(resolved) else {
                throw Clip4XError.invalidMedia("Ratio must be 9:16 or 1:1.")
            }
            invocation.ratio = ratio
        case "start":
            invocation.start = try number(resolved, flag: name)
        case "end":
            invocation.end = try number(resolved, flag: name)
        case "title":
            invocation.title = resolved
        case "face":
            invocation.face = try NormalizedRect.parse(resolved)
        case "demo":
            invocation.demo = try NormalizedRect.parse(resolved)
        case "face-band":
            invocation.faceBand = try number(resolved, flag: name)
        case "at":
            invocation.at = try number(resolved, flag: name)
        case "clip-index":
            invocation.clipIndex = Int(try number(resolved, flag: name))
        case "max-clips":
            invocation.maxClips = max(1, Int(try number(resolved, flag: name)))
        default:
            throw Clip4XError.invalidMedia("Unknown flag --\(name).")
        }
    }

    private static func number(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw) else {
            throw Clip4XError.invalidMedia(" --\(flag) needs a number. Got '\(raw)'.")
        }
        return value
    }
}
