import Foundation
import Testing
@testable import Clip4XCore

@Test func normalizedRectParseAndClamp() throws {
    let rect = try NormalizedRect.parse("0.2, 0.4, 0.5, 0.5")
    #expect(rect.x == 0.2)
    #expect(rect.midX == 0.45)
    #expect(rect.maxY == 0.9)

    let overflow = NormalizedRect(x: -0.2, y: 0.9, width: 2, height: 0.4).clamped()
    #expect(overflow.x == 0)
    #expect(overflow.maxX <= 1)
    #expect(overflow.maxY <= 1)
}

@Test func facePaddingKeepsShouldersAndClamp() {
    let face = NormalizedRect(x: 0.35, y: 0.55, width: 0.22, height: 0.28).paddedForFace()
    #expect(face.width > 0.22)
    #expect(face.height > 0.28)
    #expect(face.maxY <= 1)
}

@Test func fallbackDemoUsesSpaceAboveALowFace() {
    let face = NormalizedRect(x: 0.25, y: 0.48, width: 0.5, height: 0.46)
    let demo = NormalizedRect.fallbackDemo(aroundFace: face)
    #expect(demo.maxY <= face.y + 0.001)
    #expect(demo.area > 0.1)
}

@Test func fallbackDemoUsesOppositeSideForLeftFace() {
    let face = NormalizedRect(x: 0.02, y: 0.2, width: 0.28, height: 0.7)
    let demo = NormalizedRect.fallbackDemo(aroundFace: face)
    #expect(demo.x >= face.maxX)
    #expect(demo.area > 0.15)
}

@Test func cropPlanIsEvenAndInsideSource() {
    let rect = NormalizedRect(x: 0.11, y: 0.22, width: 0.4, height: 0.33)
    let plan = rect.cropPlan(in: VideoSize(width: 1920, height: 1080))
    #expect(plan.x % 2 == 0)
    #expect(plan.y % 2 == 0)
    #expect(plan.width % 2 == 0)
    #expect(plan.height % 2 == 0)
    #expect(plan.x + plan.width <= 1920)
    #expect(plan.y + plan.height <= 1080)
}

@Test func autoLayoutStacksOnlyWhenDemoWasDetected() {
    let size = VideoSize(width: 1920, height: 1080)
    let stacked = ScenePlan(
        face: NormalizedRect(x: 0.3, y: 0.5, width: 0.4, height: 0.4),
        demo: NormalizedRect(x: 0.2, y: 0.05, width: 0.6, height: 0.35),
        demoDetected: true,
        sourceSize: size
    ).resolve(layout: .auto, ratio: .vertical, style: .talkingHead)

    if case .stack = stacked {
        #expect(true)
    } else {
        Issue.record("Expected stack when a demo window was detected")
    }

    let faceOnly = ScenePlan(
        face: NormalizedRect(x: 0.3, y: 0.5, width: 0.4, height: 0.4),
        demo: NormalizedRect(x: 0.2, y: 0.05, width: 0.6, height: 0.35),
        demoDetected: false,
        sourceSize: size
    ).resolve(layout: .auto, ratio: .vertical, style: .talkingHead)

    if case .face = faceOnly {
        #expect(true)
    } else {
        Issue.record("Expected face crop when no demo window was detected")
    }
}

@Test func faceOverrideWinsOnScenePlan() throws {
    let source = ScenePlan(sourceSize: VideoSize(width: 1920, height: 1080))
    let options = ExportOptions(faceOverride: try NormalizedRect.parse("0.1,0.2,0.3,0.4"))
    let applied = source.applying(options)
    #expect(applied.face?.width == 0.3)
}
