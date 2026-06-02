import AppKit
import Foundation

public struct CaptionOverlayRenderer: Sendable {
    public init() {}

    public func writeOverlays(
        clip: ClipCandidate,
        ratio: ExportRatio,
        destinationDirectory: URL
    ) throws -> [TimedOverlay] {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        var overlays: [TimedOverlay] = []
        // Hook title stays pinned at the top for the entire clip (sticky), not just the intro.
        let hookURL = destinationDirectory.appendingPathComponent("hook-\(clip.id.uuidString).png")
        try renderHook(text: clip.title, ratio: ratio, destinationURL: hookURL)
        overlays.append(TimedOverlay(url: hookURL, start: 0, end: clip.duration))

        for (index, caption) in captionChunks(for: clip).enumerated() {
            let captionURL = destinationDirectory.appendingPathComponent("caption-\(clip.id.uuidString)-\(index).png")
            try renderCaption(text: caption.text, ratio: ratio, destinationURL: captionURL)
            overlays.append(TimedOverlay(url: captionURL, start: caption.start, end: caption.end))
        }

        return overlays
    }

    private func renderHook(text: String, ratio: ExportRatio, destinationURL: URL) throws {
        let size = ratio.outputSize
        let canvas = CGSize(width: size.width, height: size.height)
        let boxWidth = min(canvas.width - 180, ratio == .vertical ? 820 : 740)
        let fontSize: CGFloat = ratio == .vertical ? 48 : 38
        let maxHeight: CGFloat = ratio == .vertical ? 150 : 120
        let top: CGFloat = ratio == .vertical ? 220 : 104
        let boxRect = CGRect(
            x: (canvas.width - boxWidth) / 2,
            y: canvas.height - top - maxHeight,
            width: boxWidth,
            height: maxHeight
        )

        try drawPNG(size: canvas, url: destinationURL) { context in
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 18
            shadow.shadowOffset = CGSize(width: 0, height: -6)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.set()

            let path = NSBezierPath(roundedRect: boxRect, xRadius: 18, yRadius: 18)
            NSColor.white.setFill()
            path.fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
            let string = NSAttributedString(string: text.titleCasedForHook(), attributes: attributes)
            let textRect = string.boundingRect(
                with: CGSize(width: boxRect.width - 52, height: boxRect.height - 28),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let drawRect = CGRect(
                x: boxRect.minX + 26,
                y: boxRect.midY - ceil(textRect.height) / 2,
                width: boxRect.width - 52,
                height: ceil(textRect.height) + 4
            )
            string.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            _ = context
        }
    }

    private func renderCaption(text: String, ratio: ExportRatio, destinationURL: URL) throws {
        let size = ratio.outputSize
        let canvas = CGSize(width: size.width, height: size.height)
        let fontSize: CGFloat = ratio == .vertical ? 72 : 50
        let captionHeight: CGFloat = ratio == .vertical ? 230 : 156
        let bottomPadding: CGFloat = ratio == .vertical ? 230 : 96
        let rect = CGRect(
            x: 86,
            y: bottomPadding,
            width: canvas.width - 172,
            height: captionHeight
        )

        try drawPNG(size: canvas, url: destinationURL) { _ in
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping

            let measuringAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
                .paragraphStyle: paragraph
            ]
            let string = NSAttributedString(string: text, attributes: measuringAttributes)
            let bounds = string.boundingRect(
                with: rect.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let drawRect = CGRect(
                x: rect.minX,
                y: rect.midY - ceil(bounds.height) / 2,
                width: rect.width,
                height: ceil(bounds.height) + 8
            )

            drawCaptionOutline(text, in: drawRect, fontSize: fontSize, paragraph: paragraph)
            drawCaptionFill(text, in: drawRect, fontSize: fontSize, paragraph: paragraph)
        }
    }

    private func drawCaptionOutline(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        paragraph: NSParagraphStyle
    ) {
        let radius: CGFloat = 4
        let offsets = [
            CGSize(width: -radius, height: 0),
            CGSize(width: radius, height: 0),
            CGSize(width: 0, height: -radius),
            CGSize(width: 0, height: radius),
            CGSize(width: -radius, height: -radius),
            CGSize(width: radius, height: -radius),
            CGSize(width: -radius, height: radius),
            CGSize(width: radius, height: radius),
            CGSize(width: -radius * 0.7, height: -radius * 1.4),
            CGSize(width: radius * 0.7, height: -radius * 1.4)
        ]

        for offset in offsets {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: NSColor.black.withAlphaComponent(0.92),
                .paragraphStyle: paragraph
            ]
            let offsetRect = rect.offsetBy(dx: offset.width, dy: offset.height)
            NSAttributedString(string: text, attributes: attributes)
                .draw(with: offsetRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    private func drawCaptionFill(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        paragraph: NSParagraphStyle
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private func drawPNG(size: CGSize, url: URL, draw: (CGContext) -> Void) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw Clip4XError.exportFailed("Could not create caption overlay context.")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.cgContext.clear(CGRect(origin: .zero, size: size))
        draw(graphicsContext.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw Clip4XError.exportFailed("Could not encode caption overlay image.")
        }
        try png.write(to: url)
    }

    private func captionChunks(for clip: ClipCandidate) -> [(start: Double, end: Double, text: String)] {
        clip.transcript.flatMap { segment -> [(start: Double, end: Double, text: String)] in
            let localStart = max(0, segment.start - clip.start)
            let localEnd = min(clip.duration, segment.end - clip.start)
            guard localEnd > localStart else { return [] }

            let words = segment.text.split(separator: " ").map(String.init)
            guard words.count > 6 else {
                return [(localStart, localEnd, segment.text)]
            }

            let groups = stride(from: 0, to: words.count, by: 5).map {
                Array(words[$0..<min($0 + 5, words.count)]).joined(separator: " ")
            }
            let groupDuration = (localEnd - localStart) / Double(groups.count)
            return groups.enumerated().map { index, text in
                let start = localStart + Double(index) * groupDuration
                return (start, min(localEnd, start + groupDuration), text)
            }
        }
    }
}

private extension String {
    func titleCasedForHook() -> String {
        split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}
