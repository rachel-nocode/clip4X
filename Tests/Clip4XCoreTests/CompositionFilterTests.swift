import Foundation
import Testing
@testable import Clip4XCore

@Test func stackFilterCropsFaceAndDemoAndRoundsCorners() {
    let layout = ResolvedLayout.stack(
        face: CropPlan(x: 400, y: 200, width: 800, height: 700),
        demo: CropPlan(x: 240, y: 20, width: 1100, height: 620),
        style: .talkingHead
    )
    let graph = CompositionFilter.baseGraph(ratio: .vertical, layout: layout).joined(separator: ";")

    #expect(graph.contains("split=3[bg][face][demo]"))
    #expect(graph.contains("crop=800:700:400:200"))
    #expect(graph.contains("crop=1100:620:240:20"))
    #expect(graph.contains("geq=r='r(X,Y)'"))
    #expect(graph.contains("[v0]"))

    let metrics = CompositionFilter.stackMetrics(size: ExportRatio.vertical.outputSize, style: .talkingHead)
    #expect(metrics.faceHeight % 2 == 0)
    #expect(metrics.demoMaxWidth % 2 == 0)
    #expect(metrics.faceY + metrics.faceHeight == 1920)
    #expect(graph.contains("overlay=0:\(metrics.faceY)"))
}

@Test func fitFilterKeepsLetterboxPath() {
    let graph = CompositionFilter.baseGraph(ratio: .vertical, layout: .fit).joined(separator: ";")
    #expect(graph.contains("split=2[bg][fg]"))
    #expect(graph.contains("gblur=sigma=32"))
    #expect(!graph.contains("split=3"))
}

@Test func faceFilterCropsBeforeLetterbox() {
    let crop = CropPlan(x: 300, y: 0, width: 720, height: 1280)
    let graph = CompositionFilter.baseGraph(ratio: .vertical, layout: .face(crop)).joined(separator: ";")
    #expect(graph.contains("crop=720:1280:300:0,split=2"))
}
