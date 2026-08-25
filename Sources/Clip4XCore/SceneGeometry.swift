import Foundation

public enum PixelMath {
    public static func even(_ value: Int) -> Int {
        value - value % 2
    }

    public static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }
}

/// Axis-aligned rectangle in normalized image space. Origin is the top-left, values are 0...1.
public struct NormalizedRect: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var area: Double { max(0, width) * max(0, height) }

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    public static func parse(_ raw: String) throws -> NormalizedRect {
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              let width = Double(parts[2]),
              let height = Double(parts[3]),
              width > 0,
              height > 0
        else {
            throw Clip4XError.invalidMedia("Region must be x,y,w,h in 0...1. Got '\(raw)'.")
        }
        return NormalizedRect(x: x, y: y, width: width, height: height).clamped()
    }

    public func clamped() -> NormalizedRect {
        let x = min(max(self.x, 0), 0.98)
        let y = min(max(self.y, 0), 0.98)
        let width = min(max(self.width, 0.02), 1 - x)
        let height = min(max(self.height, 0.02), 1 - y)
        return NormalizedRect(x: x, y: y, width: width, height: height)
    }

    public func inset(by amount: Double) -> NormalizedRect {
        NormalizedRect(
            x: x + amount,
            y: y + amount,
            width: width - amount * 2,
            height: height - amount * 2
        ).clamped()
    }

    public func paddedForFace() -> NormalizedRect {
        let padX = width * 0.55
        let padTop = height * 0.50
        let padBottom = height * 0.90
        return NormalizedRect(
            x: x - padX,
            y: y - padTop,
            width: width + padX * 2,
            height: height + padTop + padBottom
        ).clamped()
    }

    public func intersection(_ other: NormalizedRect) -> NormalizedRect {
        let x1 = max(x, other.x)
        let y1 = max(y, other.y)
        let x2 = min(maxX, other.maxX)
        let y2 = min(maxY, other.maxY)
        return NormalizedRect(x: x1, y: y1, width: max(0, x2 - x1), height: max(0, y2 - y1))
    }

    public func overlapRatio(with other: NormalizedRect) -> Double {
        intersection(other).area / max(0.0001, min(area, other.area))
    }

    public func cropPlan(in source: VideoSize) -> CropPlan {
        let x = PixelMath.even(Int((x * Double(source.width)).rounded(.down)))
        let y = PixelMath.even(Int((y * Double(source.height)).rounded(.down)))
        var width = PixelMath.even(Int((width * Double(source.width)).rounded(.up)))
        var height = PixelMath.even(Int((height * Double(source.height)).rounded(.up)))
        width = min(max(2, width), PixelMath.even(max(2, source.width - x)))
        height = min(max(2, height), PixelMath.even(max(2, source.height - y)))
        return CropPlan(x: max(0, x), y: max(0, y), width: width, height: height)
    }

    public static func union(_ rects: [NormalizedRect]) -> NormalizedRect? {
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() {
            let x = min(result.x, rect.x)
            let y = min(result.y, rect.y)
            result = NormalizedRect(
                x: x,
                y: y,
                width: max(result.maxX, rect.maxX) - x,
                height: max(result.maxY, rect.maxY) - y
            )
        }
        return result.clamped()
    }

    public static func average(_ rects: [NormalizedRect]) -> NormalizedRect? {
        guard !rects.isEmpty else { return nil }
        let count = Double(rects.count)
        return NormalizedRect(
            x: rects.map(\.x).reduce(0, +) / count,
            y: rects.map(\.y).reduce(0, +) / count,
            width: rects.map(\.width).reduce(0, +) / count,
            height: rects.map(\.height).reduce(0, +) / count
        ).clamped()
    }

    /// When no window detector fires, guess the demo from leftover space around the face.
    public static func fallbackDemo(aroundFace face: NormalizedRect) -> NormalizedRect {
        let gap = 0.03
        let above = face.y - gap
        if above >= 0.20 {
            let height = min(above - 0.02, max(0.28, above * 0.92))
            let width = min(0.90, max(0.55, height * 16.0 / 9.0))
            return NormalizedRect(
                x: (1 - width) / 2,
                y: max(0.02, face.y - height - gap),
                width: width,
                height: height
            ).clamped()
        }
        if face.midX < 0.40 {
            let x = min(0.97, face.maxX + 0.03)
            return NormalizedRect(x: x, y: 0.05, width: max(0.20, 0.97 - x), height: 0.90).clamped()
        }
        if face.midX > 0.60 {
            return NormalizedRect(x: 0.03, y: 0.05, width: max(0.20, face.x - 0.06), height: 0.90).clamped()
        }
        return NormalizedRect(x: 0.08, y: 0.03, width: 0.84, height: 0.38).clamped()
    }
}

public struct ScenePlan: Hashable, Sendable {
    public var face: NormalizedRect?
    public var demo: NormalizedRect?
    public var demoDetected: Bool
    public var textLayout: TextLayout
    public var sourceSize: VideoSize

    public init(
        face: NormalizedRect? = nil,
        demo: NormalizedRect? = nil,
        demoDetected: Bool = false,
        textLayout: TextLayout = .split,
        sourceSize: VideoSize
    ) {
        self.face = face
        self.demo = demo
        self.demoDetected = demoDetected
        self.textLayout = textLayout
        self.sourceSize = sourceSize
    }

    public func applying(_ options: ExportOptions) -> ScenePlan {
        var copy = self
        if let faceOverride = options.faceOverride {
            copy.face = faceOverride.clamped()
        }
        if let demoOverride = options.demoOverride {
            copy.demo = demoOverride.clamped()
            copy.demoDetected = true
        }
        return copy
    }

    public func resolve(layout: ExportLayout, ratio: ExportRatio, style: StackStyle) -> ResolvedLayout {
        switch layout {
        case .fit:
            return .fit
        case .face:
            return .face(faceCrop(targetAspect: ratio.aspectRatio))
        case .stack:
            return stackLayout(style: style)
        case .auto:
            if face != nil, demoDetected {
                return stackLayout(style: style)
            }
            if face != nil {
                return .face(faceCrop(targetAspect: ratio.aspectRatio))
            }
            return .fit
        }
    }

    private func faceCrop(targetAspect: Double) -> CropPlan {
        let focus = face?.paddedForFace() ?? NormalizedRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
        return makeAspectCrop(sourceSize: sourceSize, targetAspect: targetAspect, focus: focus)
    }

    private func stackLayout(style: StackStyle) -> ResolvedLayout {
        let faceRect = (face ?? NormalizedRect(x: 0.18, y: 0.38, width: 0.64, height: 0.58)).paddedForFace()
        let demoRect = demo ?? NormalizedRect.fallbackDemo(aroundFace: face ?? faceRect)
        return .stack(
            face: faceRect.cropPlan(in: sourceSize),
            demo: demoRect.cropPlan(in: sourceSize),
            style: style
        )
    }
}

public enum ResolvedLayout: Hashable, Sendable {
    case fit
    case face(CropPlan)
    case stack(face: CropPlan, demo: CropPlan, style: StackStyle)

    /// Stack junction offsets apply only after `auto` (or an explicit request)
    /// has resolved to a face+demo stack — never for unresolved `.auto`.
    public var usesStackPlacement: Bool {
        if case .stack = self { return true }
        return false
    }
}

func makeAspectCrop(sourceSize: VideoSize, targetAspect: Double, focus: NormalizedRect) -> CropPlan {
    let sourceAspect = Double(sourceSize.width) / Double(sourceSize.height)
    let focusX = focus.midX
    let focusY = focus.midY

    if sourceAspect > targetAspect {
        let cropHeight = PixelMath.even(sourceSize.height)
        let cropWidth = PixelMath.even(Int(Double(cropHeight) * targetAspect))
        let targetCenterX = Int(focusX * Double(sourceSize.width))
        let rawX = targetCenterX - cropWidth / 2
        let x = PixelMath.even(PixelMath.clamp(rawX, min: 0, max: sourceSize.width - cropWidth))
        return CropPlan(x: x, y: 0, width: cropWidth, height: cropHeight)
    }

    let cropWidth = PixelMath.even(sourceSize.width)
    let cropHeight = PixelMath.even(Int(Double(cropWidth) / targetAspect))
    let targetCenterY = Int(focusY * Double(sourceSize.height))
    let rawY = targetCenterY - cropHeight / 2
    let y = PixelMath.even(PixelMath.clamp(rawY, min: 0, max: sourceSize.height - cropHeight))
    return CropPlan(x: 0, y: y, width: cropWidth, height: cropHeight)
}
