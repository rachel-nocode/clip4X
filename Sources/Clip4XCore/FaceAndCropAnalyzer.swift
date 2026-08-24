import AVFoundation
import CoreGraphics
import Foundation
import Vision

public struct FrameAnalysis: Sendable {
    public var cropPlan: CropPlan
    public var textLayout: TextLayout
    public var scene: ScenePlan

    public init(cropPlan: CropPlan, textLayout: TextLayout, scene: ScenePlan) {
        self.cropPlan = cropPlan
        self.textLayout = textLayout
        self.scene = scene
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
        let scene = analyzeScene(videoURL: videoURL, clip: clip, sourceSize: sourceSize)
        let resolved = scene.resolve(layout: .face, ratio: ratio, style: .talkingHead)
        let cropPlan: CropPlan
        if case let .face(plan) = resolved {
            cropPlan = plan
        } else {
            cropPlan = makeAspectCrop(
                sourceSize: sourceSize,
                targetAspect: ratio.aspectRatio,
                focus: scene.face ?? NormalizedRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
            )
        }
        return FrameAnalysis(cropPlan: cropPlan, textLayout: scene.textLayout, scene: scene)
    }

    public func analyzeScene(
        videoURL: URL,
        clip: ClipCandidate,
        sourceSize: VideoSize
    ) -> ScenePlan {
        let samples = sampleFrames(videoURL: videoURL, clip: clip)
        let faces = samples.flatMap(\.faces)
        let face = NormalizedRect.average(faces)
        let demoSamples = samples.compactMap { sample in
            demoCandidate(rectangles: sample.rectangles, textBoxes: sample.textBoxes, face: NormalizedRect.average(sample.faces) ?? face)
        }
        let detectedDemo = NormalizedRect.average(demoSamples)
        let layout = makeTextLayout(samples: faces)
        return ScenePlan(
            face: face,
            demo: detectedDemo ?? face.map(NormalizedRect.fallbackDemo(aroundFace:)),
            demoDetected: detectedDemo != nil,
            textLayout: layout,
            sourceSize: sourceSize
        )
    }

    private struct FrameSample {
        var faces: [NormalizedRect]
        var rectangles: [NormalizedRect]
        var textBoxes: [NormalizedRect]
    }

    private func sampleFrames(videoURL: URL, clip: ClipCandidate) -> [FrameSample] {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let duration = max(0.2, clip.duration)
        let seconds = [0.12, 0.32, 0.50, 0.68, 0.88].map { clip.start + duration * $0 }
        var samples: [FrameSample] = []

        for second in seconds {
            do {
                let image = try generator.copyCGImage(
                    at: CMTime(seconds: second, preferredTimescale: 600),
                    actualTime: nil
                )
                samples.append(detectRegions(in: image))
            } catch {
                continue
            }
        }

        return samples
    }

    private func detectRegions(in image: CGImage) -> FrameSample {
        let handler = VNImageRequestHandler(cgImage: image)
        let faceRequest = VNDetectFaceRectanglesRequest()
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.minimumAspectRatio = 0.28
        rectangleRequest.maximumAspectRatio = 3.2
        rectangleRequest.minimumSize = 0.10
        rectangleRequest.maximumObservations = 8
        rectangleRequest.quadratureTolerance = 22
        rectangleRequest.minimumConfidence = 0.35

        var faces: [NormalizedRect] = []
        var rectangles: [NormalizedRect] = []
        var textBoxes: [NormalizedRect] = []

        do {
            try handler.perform([faceRequest, rectangleRequest])
            faces = (faceRequest.results ?? []).map { fromVision($0.boundingBox) }
            rectangles = (rectangleRequest.results ?? []).map { fromVision($0.boundingBox) }
        } catch {
            return FrameSample(faces: faces, rectangles: rectangles, textBoxes: textBoxes)
        }

        if rectangles.isEmpty {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .fast
            textRequest.usesLanguageCorrection = false
            do {
                try handler.perform([textRequest])
                textBoxes = (textRequest.results ?? []).map { fromVision($0.boundingBox) }
            } catch {
                // Text is a fallback detector only.
            }
        }

        return FrameSample(faces: faces, rectangles: rectangles, textBoxes: textBoxes)
    }

    private func demoCandidate(
        rectangles: [NormalizedRect],
        textBoxes: [NormalizedRect],
        face: NormalizedRect?
    ) -> NormalizedRect? {
        let usableRects = rectangles.filter { rect in
            guard rect.area >= 0.08 else { return false }
            if let face, rect.overlapRatio(with: face) > 0.35 { return false }
            return true
        }
        .sorted { lhs, rhs in
            if abs(lhs.area - rhs.area) > 0.04 { return lhs.area > rhs.area }
            return lhs.y < rhs.y
        }
        if let best = usableRects.first {
            return best.inset(by: -0.015)
        }

        let usableText = textBoxes.filter { box in
            if let face, box.overlapRatio(with: face) > 0.40 { return false }
            return true
        }
        if let cluster = NormalizedRect.union(usableText), cluster.area >= 0.10 {
            return cluster.inset(by: -0.02)
        }
        return nil
    }

    private func makeTextLayout(samples: [NormalizedRect]) -> TextLayout {
        guard !samples.isEmpty else { return .split }

        let topHits = samples.filter { $0.y < 0.36 }.count
        let bottomHits = samples.filter { $0.maxY > 0.64 }.count

        if bottomHits > topHits {
            return TextLayout(hookBand: .top, captionBand: .top)
        }
        if topHits > bottomHits {
            return TextLayout(hookBand: .bottom, captionBand: .bottom)
        }
        return .split
    }

    /// Vision boxes are origin-bottom-left. Convert to top-left normalized space.
    private func fromVision(_ box: CGRect) -> NormalizedRect {
        NormalizedRect(
            x: Double(box.origin.x),
            y: Double(1 - box.origin.y - box.height),
            width: Double(box.width),
            height: Double(box.height)
        ).clamped()
    }
}
