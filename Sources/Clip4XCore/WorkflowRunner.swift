import Foundation

public struct WorkflowOptions: Sendable {
    public var layout: ExportLayout
    public var maxClips: Int
    public var captions: Bool
    public var rankerPreference: MomentRankerPreference

    public init(
        layout: ExportLayout = .stack,
        maxClips: Int = 8,
        captions: Bool = true,
        rankerPreference: MomentRankerPreference = .auto
    ) {
        self.layout = layout
        self.maxClips = max(1, min(8, maxClips))
        self.captions = captions
        self.rankerPreference = rankerPreference
    }
}

public struct WorkflowQCResult: Equatable, Sendable {
    public var passed: Bool
    public var issues: [String]

    public init(passed: Bool, issues: [String]) {
        self.passed = passed
        self.issues = issues
    }
}

public enum WorkflowQC {
    public static func validate(_ media: MediaInspection, expectedDuration: Double) -> WorkflowQCResult {
        var issues: [String] = []
        if media.width != 1080 || media.height != 1920 {
            issues.append("Expected 1080x1920, got \(media.width)x\(media.height).")
        }
        if media.videoCodec?.lowercased() != "h264" {
            issues.append("Expected H.264 video, got \(media.videoCodec ?? "none").")
        }
        if media.audioCodec?.lowercased() != "aac" {
            issues.append("Expected AAC audio, got \(media.audioCodec ?? "none").")
        }
        if abs(media.duration - expectedDuration) > 0.75 {
            issues.append(String(format: "Expected %.2fs duration, got %.2fs.", expectedDuration, media.duration))
        }
        return WorkflowQCResult(passed: issues.isEmpty, issues: issues)
    }
}

public struct WorkflowRenderedClip: Sendable {
    public var clip: ClipCandidate
    public var url: URL
    public var inspection: MediaInspection
    public var qc: WorkflowQCResult
}

public struct WorkflowResult: Sendable {
    public var project: WorkflowProject
    public var sourceURL: URL
    public var analysis: AnalysisResult
    public var renders: [WorkflowRenderedClip]
}

public struct WorkflowRunner: Sendable {
    public var sourceResolver: WorkflowSourceResolver

    public init(sourceResolver: WorkflowSourceResolver = WorkflowSourceResolver()) {
        self.sourceResolver = sourceResolver
    }

    public static func defaultProjectName(for input: String) -> String {
        if case .youtube(let url) = WorkflowInput.parse(input),
           let id = YouTubeVideoID.parse(url.absoluteString) {
            return "youtube-\(id)"
        }
        let name = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
            .deletingPathExtension().lastPathComponent
        return ClipFileName.safe(name).isEmpty ? "clip4x-project" : ClipFileName.safe(name)
    }

    public func run(
        input rawInput: String,
        project: WorkflowProject,
        options: WorkflowOptions = WorkflowOptions(),
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws -> WorkflowResult {
        guard let input = WorkflowInput.parse(rawInput) else {
            throw Clip4XError.invalidMedia("Input must be a local video or YouTube URL.")
        }
        onStatus?("Ingesting source")
        let sourceURL = try await sourceResolver.resolve(input, into: project)
        let workDirectory = project.analysisDirectory.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        let pipeline = try await ClipPipeline.make(rankerPreference: options.rankerPreference)
        let analysis = try await pipeline.analyze(
            videoURL: sourceURL,
            workDirectory: workDirectory,
            maxClips: options.maxClips,
            onStatus: onStatus
        )
        try project.writeTranscript(analysis.segments)
        try project.writeCandidates(analysis.clips)

        var layouts: [String: WorkflowLayoutArtifact] = [:]
        var metadata: [String: WorkflowClipMetadata] = [:]
        var rendered: [WorkflowRenderedClip] = []
        let exportOptions = ExportOptions(ratio: .vertical, layout: options.layout, captions: options.captions)

        for (index, clip) in analysis.clips.enumerated() {
            onStatus?("Rendering \(index + 1)/\(analysis.clips.count): \(clip.title)")
            let stem = String(format: "%02d-%@", index + 1, slug(clip.title))
            let outputURL = project.uniqueRenderURL(stem: stem)
            let scene = pipeline.scenePlan(
                videoURL: sourceURL,
                clip: clip,
                sourceSize: analysis.sourceSize,
                options: exportOptions
            )
            layouts[outputURL.lastPathComponent] = WorkflowLayoutArtifact(
                sourceWidth: analysis.sourceSize.width,
                sourceHeight: analysis.sourceSize.height,
                face: scene.face,
                screen: scene.demo
            )
            try await pipeline.exportClip(
                videoURL: sourceURL,
                clip: clip,
                sourceSize: analysis.sourceSize,
                options: exportOptions,
                destinationURL: outputURL,
                workDirectory: workDirectory
            )
            let inspection = try await pipeline.mediaTools.inspectMedia(videoURL: outputURL)
            let qc = WorkflowQC.validate(inspection, expectedDuration: clip.duration)
            try await writePreviewFrames(
                mediaTools: pipeline.mediaTools,
                videoURL: outputURL,
                duration: inspection.duration,
                prefix: stem,
                directory: project.previewsDirectory
            )
            metadata[outputURL.lastPathComponent] = WorkflowClipMetadata(
                title: String(clip.title.prefix(100)),
                description: clip.reason,
                tags: clip.theme.isEmpty ? [] : [clip.theme]
            )
            rendered.append(WorkflowRenderedClip(clip: clip, url: outputURL, inspection: inspection, qc: qc))
        }

        try project.writeLayouts(layouts)
        try project.writeMetadata(metadata)
        try writeQC(rendered, to: project.qcURL)
        let failures = rendered.filter { !$0.qc.passed }
        if !failures.isEmpty {
            throw Clip4XError.exportFailed("\(failures.count) render(s) failed QC. See \(project.qcURL.path).")
        }
        return WorkflowResult(project: project, sourceURL: sourceURL, analysis: analysis, renders: rendered)
    }

    private func writePreviewFrames(
        mediaTools: MediaTools,
        videoURL: URL,
        duration: Double,
        prefix: String,
        directory: URL
    ) async throws {
        let times = [min(0.2, duration / 4), duration / 2, max(0, duration - 0.2)]
        for (index, time) in times.enumerated() {
            let destination = directory.appendingPathComponent("\(prefix)-\(["start", "middle", "end"][index]).png")
            try await mediaTools.extractFrame(videoURL: videoURL, at: time, destinationURL: destination)
        }
    }

    private func writeQC(_ renders: [WorkflowRenderedClip], to url: URL) throws {
        let rows = renders.map { render in
            let status = render.qc.passed ? "PASS" : "FAIL"
            let issues = render.qc.issues.isEmpty ? "none" : render.qc.issues.joined(separator: "; ")
            return "- \(status) `\(render.url.lastPathComponent)` — \(render.inspection.width)x\(render.inspection.height), \(String(format: "%.2f", render.inspection.duration))s, issues: \(issues)"
        }
        try ("# Render QC\n\n" + rows.joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private func slug(_ value: String) -> String {
        let safe = ClipFileName.safe(value).lowercased()
        return safe.split(whereSeparator: { $0 == " " }).joined(separator: "-")
    }
}
