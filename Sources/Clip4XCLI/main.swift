import Clip4XCore
import Darwin
import Foundation

@main
struct Clip4XCLI {
    static func main() async {
        do {
            try await execute(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func execute(_ arguments: [String]) async throws {
        let invocation = try ClipCommand.parse(arguments)
        if invocation.verb == .help {
            print(ClipInvocation.helpText)
            return
        }

        if invocation.verb == .workflow {
            try await runWorkflow(invocation)
            return
        }
        if invocation.verb == .schedule {
            try await runSchedule(invocation)
            return
        }

        guard let videoPath = invocation.videoPath else {
            throw Clip4XError.invalidMedia("Pass a video path.")
        }
        let videoURL = URL(fileURLWithPath: (videoPath as NSString).expandingTildeInPath)
        guard FileManager.default.isReadableFile(atPath: videoURL.path) else {
            throw Clip4XError.invalidMedia("Cannot read \(videoURL.path).")
        }

        let pipeline = try await ClipPipeline.make(
            requireWhisper: invocation.requiresWhisper,
            rankerPreference: invocation.rankerPreference
        )
        let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("clip4x-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        switch invocation.verb {
        case .help:
            print(ClipInvocation.helpText)
        case .analyze:
            let result = try await analyze(pipeline: pipeline, videoURL: videoURL, workDirectory: workDirectory, invocation: invocation)
            if invocation.json {
                print(jsonReport(result: result, scene: nil))
            } else {
                printAnalysis(result)
            }
        case .frame:
            try await renderFrame(pipeline: pipeline, videoURL: videoURL, invocation: invocation)
        case .export:
            try await export(pipeline: pipeline, videoURL: videoURL, workDirectory: workDirectory, invocation: invocation)
        case .run:
            try await export(pipeline: pipeline, videoURL: videoURL, workDirectory: workDirectory, invocation: invocation)
        case .workflow, .schedule:
            break
        }
    }

    private static func runWorkflow(_ invocation: ClipInvocation) async throws {
        guard let input = invocation.videoPath else {
            throw Clip4XError.invalidMedia("Pass a local video or YouTube URL.")
        }
        let projectRoot: URL
        if let path = invocation.projectPath {
            projectRoot = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            projectRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Movies")
                .appendingPathComponent("Clip4X")
                .appendingPathComponent(WorkflowRunner.defaultProjectName(for: input))
        }
        let project = try WorkflowProject.create(root: projectRoot)
        let result = try await WorkflowRunner().run(
            input: input,
            project: project,
            options: WorkflowOptions(
                layout: invocation.layout,
                maxClips: invocation.maxClips,
                captions: invocation.captions,
                rankerPreference: invocation.rankerPreference
            )
        ) { message in
            if !invocation.json {
                FileHandle.standardError.write(Data("\(message)\n".utf8))
            }
        }
        if invocation.json {
            print(jsonObject([
                "project": result.project.root.path,
                "ranker": result.analysis.rankerName ?? "heuristic",
                "renders": result.renders.map { $0.url.path }
            ]))
        } else {
            print("project \(result.project.root.path)")
            for render in result.renders {
                print(render.url.path)
            }
        }
    }

    private static func runSchedule(_ invocation: ClipInvocation) async throws {
        guard let folderPath = invocation.videoPath,
              let startDate = invocation.startDate,
              let clockTime = invocation.clockTime else {
            throw Clip4XError.invalidMedia("Schedule requires RENDERS, --start-date, and --time.")
        }
        let folder = URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath)
        let scheduler = ZernioScheduler()
        let schedule = try await scheduler.plan(
            directory: folder,
            pattern: invocation.glob,
            startDate: startDate,
            time: clockTime,
            timezone: invocation.timezone
        )

        if invocation.json, !invocation.execute {
            print(jsonObject([
                "execute": false,
                "timezone": schedule.timezone,
                "platforms": schedule.platforms.map(\.rawValue),
                "items": schedule.items.map {
                    ["file": $0.source.fileURL.path, "title": $0.source.metadata.title, "scheduledFor": $0.localDateTime]
                }
            ]))
            return
        }

        if !invocation.json {
            print("preview \(schedule.items.count) videos → YouTube Shorts + TikTok")
            print("timezone \(schedule.timezone)")
            for (index, item) in schedule.items.enumerated() {
                print(String(format: "%02d. %@ | %@ | %@", index + 1, item.localDateTime, item.source.fileURL.lastPathComponent, item.source.metadata.title))
            }
        }
        guard invocation.execute else {
            if !invocation.json { print("DRY RUN ONLY — nothing uploaded or scheduled") }
            return
        }

        let envFile = invocation.envFilePath.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        }
        let credentials = try ZernioCredentials.load(envFile: envFile)
        let verified = try await scheduler.execute(schedule, credentials: credentials)
        if invocation.json {
            print(jsonObject([
                "verified": verified.map {
                    ["file": $0.fileURL.path, "postId": $0.postID]
                }
            ]))
        } else {
            print("VERIFIED SCHEDULE")
            for post in verified {
                print("\(post.fileURL.lastPathComponent) | post \(post.postID)")
            }
        }
    }

    @discardableResult
    private static func analyze(
        pipeline: ClipPipeline,
        videoURL: URL,
        workDirectory: URL,
        invocation: ClipInvocation
    ) async throws -> AnalysisResult {
        try await pipeline.analyze(
            videoURL: videoURL,
            workDirectory: workDirectory,
            maxClips: invocation.maxClips
        ) { message in
            if !invocation.json {
                FileHandle.standardError.write(Data("\(message)\n".utf8))
            }
        }
    }

    private static func renderFrame(
        pipeline: ClipPipeline,
        videoURL: URL,
        invocation: ClipInvocation
    ) async throws {
        let sourceSize = try await pipeline.mediaTools.probeVideoSize(videoURL: videoURL)
        let duration = try await pipeline.mediaTools.probeDuration(videoURL: videoURL)
        let at = invocation.at ?? duration * 0.38
        let outputURL = outputURL(
            invocation: invocation,
            defaultDirectory: FileManager.default.temporaryDirectory,
            fileName: "clip4x-frame.png"
        )
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let scene = try await pipeline.exportFrame(
            videoURL: videoURL,
            at: at,
            sourceSize: sourceSize,
            options: invocation.exportOptions,
            destinationURL: outputURL
        )
        if invocation.json {
            print(jsonReport(result: nil, scene: scene, extra: [
                "at": at,
                "output": outputURL.path,
                "layout": invocation.layout.rawValue
            ]))
        } else {
            print("wrote \(outputURL.path)")
            print(sceneSummary(scene))
        }
    }

    private static func export(
        pipeline: ClipPipeline,
        videoURL: URL,
        workDirectory: URL,
        invocation: ClipInvocation
    ) async throws {
        let sourceSize = try await pipeline.mediaTools.probeVideoSize(videoURL: videoURL)
        let clips: [ClipCandidate]
        if invocation.hasManualWindow, let start = invocation.start, let end = invocation.end {
            clips = [
                ClipCandidate(
                    title: invocation.title ?? "clip",
                    theme: "manual",
                    reason: "Manual window \(DurationFormatter.short(start))–\(DurationFormatter.short(end)).",
                    start: start,
                    end: end,
                    score: 100,
                    transcript: []
                )
            ]
        } else {
            let result = try await analyze(
                pipeline: pipeline,
                videoURL: videoURL,
                workDirectory: workDirectory,
                invocation: invocation
            )
            if !invocation.json {
                printAnalysis(result)
            }
            if let index = invocation.clipIndex {
                guard result.clips.indices.contains(index) else {
                    throw Clip4XError.invalidMedia("clip-index \(index) is out of range (0..<\(result.clips.count)).")
                }
                clips = [result.clips[index]]
            } else {
                clips = result.clips
            }
        }

        guard !clips.isEmpty else {
            throw Clip4XError.exportFailed("No clips to export.")
        }

        let exportRoot = outputDirectory(invocation: invocation, videoURL: videoURL)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        var exported: [String] = []

        for (index, var clip) in clips.enumerated() {
            if let title = invocation.title, clips.count == 1 {
                clip.title = title
            }
            if !invocation.json {
                FileHandle.standardError.write(Data("exporting \(index + 1)/\(clips.count) \(clip.title)\n".utf8))
            }
            let destination: URL
            if clips.count == 1,
               let outputPath = invocation.outputPath,
               outputPath.lowercased().hasSuffix(".mp4") {
                destination = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            } else {
                let fileName = ClipFileName.clipFile(title: clip.title, start: clip.start)
                destination = exportRoot.appendingPathComponent(fileName).appendingPathExtension("mp4")
            }
            try await pipeline.exportClip(
                videoURL: videoURL,
                clip: clip,
                sourceSize: sourceSize,
                options: invocation.exportOptions,
                destinationURL: destination,
                workDirectory: workDirectory
            )
            exported.append(destination.path)
            if !invocation.json {
                print(destination.path)
            }
        }

        if invocation.json {
            print(jsonObject([
                "layout": invocation.layout.rawValue,
                "ratio": invocation.ratio.label,
                "exported": exported
            ]))
        }
    }

    private static func outputDirectory(invocation: ClipInvocation, videoURL: URL) -> URL {
        if let outputPath = invocation.outputPath {
            let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            if outputPath.lowercased().hasSuffix(".mp4") {
                return url.deletingLastPathComponent()
            }
            return url
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("Clip4X Exports")
            .appendingPathComponent(videoURL.deletingPathExtension().lastPathComponent)
            .appendingPathComponent(ClipFileName.layoutFolder(ratio: invocation.ratio, layout: invocation.layout))
    }

    private static func outputURL(invocation: ClipInvocation, defaultDirectory: URL, fileName: String) -> URL {
        guard let outputPath = invocation.outputPath else {
            return defaultDirectory.appendingPathComponent(fileName)
        }
        let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        if outputPath.hasSuffix("/") {
            return url.appendingPathComponent(fileName)
        }
        return url
    }

    private static func printAnalysis(_ result: AnalysisResult) {
        let ranker = result.rankerName.map { "  (\($0.lowercased()))" } ?? ""
        print("duration \(DurationFormatter.short(result.duration))  \(result.sourceSize.width)x\(result.sourceSize.height)  clips \(result.clips.count)\(ranker)")
        for (index, clip) in result.clips.enumerated() {
            print(String(
                format: "[%d] %5.1f–%5.1f  %3d  %@",
                index,
                clip.start,
                clip.end,
                clip.score,
                clip.title
            ))
        }
    }

    private static func sceneSummary(_ scene: ScenePlan) -> String {
        func describe(_ name: String, _ rect: NormalizedRect?, detected: Bool = true) -> String {
            guard let rect else { return "\(name): none" }
            let flag = detected ? "" : " (guess)"
            return String(
                format: "%@: %.3f,%.3f,%.3f,%.3f%@",
                name,
                rect.x,
                rect.y,
                rect.width,
                rect.height,
                flag
            )
        }
        return [
            describe("face", scene.face),
            describe("demo", scene.demo, detected: scene.demoDetected)
        ].joined(separator: "\n")
    }

    private static func jsonReport(
        result: AnalysisResult?,
        scene: ScenePlan?,
        extra: [String: Any] = [:]
    ) -> String {
        var object: [String: Any] = extra
        if let result {
            object["duration"] = result.duration
            object["size"] = ["width": result.sourceSize.width, "height": result.sourceSize.height]
            object["usedCodex"] = result.usedCodex
            object["ranker"] = result.rankerName ?? "heuristic"
            object["clips"] = result.clips.enumerated().map { index, clip in
                [
                    "index": index,
                    "title": clip.title,
                    "theme": clip.theme,
                    "reason": clip.reason,
                    "start": clip.start,
                    "end": clip.end,
                    "score": clip.score
                ]
            }
        }
        if let scene {
            if let face = scene.face {
                object["face"] = rectJSON(face)
            }
            if let demo = scene.demo {
                object["demo"] = rectJSON(demo)
            }
            object["demoDetected"] = scene.demoDetected
        }
        return jsonObject(object)
    }

    private static func rectJSON(_ rect: NormalizedRect) -> [String: Double] {
        ["x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height]
    }

    private static func jsonObject(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }
}
