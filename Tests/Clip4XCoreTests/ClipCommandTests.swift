import Foundation
import Testing
@testable import Clip4XCore

@Test func parseHelpAndImplicitRun() throws {
    #expect(try ClipCommand.parse(["help"]).verb == .help)
    #expect(try ClipCommand.parse(["--help"]).verb == .help)

    let run = try ClipCommand.parse(["talk.mov", "--layout", "stack"])
    #expect(run.verb == .run)
    #expect(run.videoPath == "talk.mov")
    #expect(run.layout == .stack)
}

@Test func parseExportOverrides() throws {
    let command = try ClipCommand.parse([
        "export", "demo.mp4",
        "--ratio=1:1",
        "--start", "12",
        "--end", "40",
        "--face", "0.2,0.4,0.5,0.5",
        "--demo", "0.1,0.05,0.8,0.35",
        "--no-captions",
        "--out", "~/Desktop/out"
    ])
    #expect(command.verb == .export)
    #expect(command.ratio == .square)
    #expect(command.start == 12)
    #expect(command.end == 40)
    #expect(command.captions == false)
    #expect(command.face?.width == 0.5)
    #expect(command.demo?.height == 0.35)
    #expect(command.outputPath == "~/Desktop/out")
}

@Test func parseRejectsUnknownFlag() {
    #expect(throws: Clip4XError.self) {
        _ = try ClipCommand.parse(["analyze", "a.mp4", "--nope", "1"])
    }
}

@Test func parseHelpIgnoresOptionValues() throws {
    let titled = try ClipCommand.parse(["export", "demo.mp4", "--title", "help"])
    #expect(titled.verb == .export)
    #expect(titled.title == "help")

    let out = try ClipCommand.parse(["run", "talk.mov", "--out", "help"])
    #expect(out.verb == .run)
    #expect(out.outputPath == "help")

    #expect(try ClipCommand.parse(["run", "talk.mov", "--help"]).verb == .help)
    #expect(try ClipCommand.parse(["-h"]).verb == .help)
}

@Test func runWithManualWindowDoesNotNeedWhisper() throws {
    let windowed = try ClipCommand.parse(["run", "talk.mov", "--start", "2", "--end", "10"])
    #expect(windowed.hasManualWindow)
    #expect(!windowed.requiresWhisper)

    let detect = try ClipCommand.parse(["run", "talk.mov"])
    #expect(detect.requiresWhisper)

    let exportWindow = try ClipCommand.parse(["export", "talk.mov", "--start", "1", "--end", "4"])
    #expect(!exportWindow.requiresWhisper)
}
