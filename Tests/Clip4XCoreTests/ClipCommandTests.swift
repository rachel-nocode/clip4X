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

@Test func parsesWorkflowAndScheduleOptions() throws {
    let workflow = try ClipCommand.parse([
        "workflow", "https://youtu.be/abcdefghijk",
        "--project", "/tmp/job",
        "--ranker", "claude"
    ])
    #expect(workflow.verb == .workflow)
    #expect(workflow.videoPath == "https://youtu.be/abcdefghijk")
    #expect(workflow.projectPath == "/tmp/job")
    #expect(workflow.rankerPreference == .claude)

    let schedule = try ClipCommand.parse([
        "schedule", "/tmp/job/renders",
        "--start-date", "2026-09-02",
        "--time", "08:00",
        "--timezone", "America/Los_Angeles",
        "--glob", "*-v3.mp4",
        "--env-file", "/tmp/zernio.env"
    ])
    #expect(schedule.verb == .schedule)
    #expect(schedule.startDate == "2026-09-02")
    #expect(schedule.clockTime == "08:00")
    #expect(schedule.timezone == "America/Los_Angeles")
    #expect(schedule.glob == "*-v3.mp4")
    #expect(schedule.envFilePath == "/tmp/zernio.env")
    #expect(!schedule.execute)

    let execute = try ClipCommand.parse([
        "schedule", "/tmp/job/renders",
        "--start-date", "2026-09-02",
        "--time", "08:00",
        "--execute"
    ])
    #expect(execute.execute)
}
