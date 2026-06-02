import AVFoundation
import Foundation
import Vision

public struct FrameAnalysis: Sendable {
    public var cropPlan: CropPlan
    public var textLayout: TextLayout

    public init(cropPlan: CropPlan, textLayout: TextLayout) {
        self.cropPlan = cropPlan
        self.textLayout = textLayout
    }
}

public struct FaceAndCropAnalyzer: Sendable {
    public init() {}

    public func analyze(
        videoURL: URL,
        clip: ClipCandidate,
        ratio: ExportRatio,
        sourceSize: VideoSize
    ) async -> FrameAnalysis {
        let samples = sampleFaces(videoURL: videoURL, clip: clip)
        let focus = averageFocus(from: samples) ?? CGPoint(x: 0.5, y: 0.5)
        let cropPlan = makeCropPlan(sourceSize: sourceSize, targetAspect: ratio.aspectRatio, focus: focus)
        let layout = makeTextLayout(samples: samples)
        return FrameAnalysis(cropPlan: cropPlan, textLayout: layout)
    }

    private func sampleFaces(videoURL: URL, clip: ClipCandidate) -> [CGRect] {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let duration = max(0.2, clip.duration)
        let seconds = [0.18, 0.5, 0.82].map { clip.start + duration * $0 }
        var faces: [CGRect] = []

        for second in seconds {
            do {
                let image = try generator.copyCGImage(at: CMTime(seconds: second, preferredTimescale: 600), actualTime: nil)
                let request = VNDetectFaceRectanglesRequest()
                let handler = VNImageRequestHandler(cgImage: image)
                try handler.perform([request])
                let observations = request.results ?? []
                faces.append(contentsOf: observations.map(\.boundingBox))
            } catch {
                continue
            }
        }

        return faces
    }

    private func averageFocus(from faces: [CGRect]) -> CGPoint? {
        guard !faces.isEmpty else { return nil }

        let totalArea = faces.reduce(CGFloat(0)) { $0 + max(0.001, $1.width * $1.height) }
        let x = faces.reduce(CGFloat(0)) { partial, face in
            partial + face.midX * max(0.001, face.width * face.height)
        } / totalArea
        let y = faces.reduce(CGFloat(0)) { partial, face in
            partial + face.midY * max(0.001, face.width * face.height)
        } / totalArea

        return CGPoint(x: x, y: y)
    }

    private func makeTextLayout(samples: [CGRect]) -> TextLayout {
        guard !samples.isEmpty else { return .split }

        let topHits = samples.filter { $0.maxY > 0.64 }.count
        let bottomHits = samples.filter { $0.minY < 0.36 }.count

        if bottomHits > topHits {
            return TextLayout(hookBand: .top, captionBand: .top)
        }
        if topHits > bottomHits {
            return TextLayout(hookBand: .bottom, captionBand: .bottom)
        }
        return .split
    }

    private func makeCropPlan(sourceSize: VideoSize, targetAspect: Double, focus: CGPoint) -> CropPlan {
        let sourceAspect = Double(sourceSize.width) / Double(sourceSize.height)

        if sourceAspect > targetAspect {
            let cropHeight = even(sourceSize.height)
            let cropWidth = even(Int(Double(cropHeight) * targetAspect))
            let targetCenterX = Int(focus.x * Double(sourceSize.width))
            let rawX = targetCenterX - cropWidth / 2
            let x = even(clamp(rawX, min: 0, max: sourceSize.width - cropWidth))
            return CropPlan(x: x, y: 0, width: cropWidth, height: cropHeight)
        } else {
            let cropWidth = even(sourceSize.width)
            let cropHeight = even(Int(Double(cropWidth) / targetAspect))
            let targetCenterYFromTop = Int((1 - focus.y) * Double(sourceSize.height))
            let rawY = targetCenterYFromTop - cropHeight / 2
            let y = even(clamp(rawY, min: 0, max: sourceSize.height - cropHeight))
            return CropPlan(x: 0, y: y, width: cropWidth, height: cropHeight)
        }
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }

    private func even(_ value: Int) -> Int {
        value - value % 2
    }
}
