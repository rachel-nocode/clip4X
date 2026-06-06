import AppKit
import Clip4XCore
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var sourceURL: URL?
    @Published var outputDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop")
        .appendingPathComponent("Clip4X Exports")
    @Published var selectedRatio: ExportRatio = .vertical
    @Published var clips: [ClipCandidate] = []
    @Published var isWorking = false
    /// 0...1 progress for batch work (export/upload). `nil` = indeterminate.
    @Published var progress: Double?
    @Published var status = "Drop a video to start."
    @Published var log: [String] = []
    @Published var transcriptCount = 0

    let youtubeAuth = YouTubeAuthManager()

    private let fileManager = FileManager.default

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .video]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            loadVideo(url)
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }

    func loadVideo(_ url: URL) {
        sourceURL = url
        clips = []
        transcriptCount = 0
        status = "Ready: \(url.lastPathComponent)"
        log = ["Loaded \(url.path)"]
    }

    func analyze() {
        guard let sourceURL else { return }
        isWorking = true
        progress = nil
        clips = []
        transcriptCount = 0

        Task {
            do {
                appendLog("Checking local tools")
                guard let ffmpeg = await ToolLocator.find("ffmpeg") else { throw Clip4XError.missingTool("ffmpeg") }
                guard let ffprobe = await ToolLocator.find("ffprobe") else { throw Clip4XError.missingTool("ffprobe") }
                guard let whisper = await ToolLocator.find("whisper") else { throw Clip4XError.missingTool("whisper") }

                let mediaTools = MediaTools(ffmpegPath: ffmpeg, ffprobePath: ffprobe)
                let workDirectory = try makeWorkDirectory()
                let audioURL = workDirectory.appendingPathComponent("source.wav")
                let transcriptDirectory = workDirectory.appendingPathComponent("transcript")

                status = "Reading video"
                let duration = try await mediaTools.probeDuration(videoURL: sourceURL)

                status = "Extracting audio"
                try await mediaTools.extractAudio(videoURL: sourceURL, destinationURL: audioURL)

                status = "Transcribing with Whisper"
                let transcriber = WhisperTranscriber(whisperPath: whisper, model: "base")
                let segments = try await transcriber.transcribe(audioURL: audioURL, outputDirectory: transcriptDirectory)
                transcriptCount = segments.count

                status = "Finding clip moments"
                let detector = ClipMomentDetector()
                let fallbackClips = detector.detect(in: segments, sourceDuration: duration)

                if let codex = await ToolLocator.find("codex") {
                    do {
                        status = "Ranking moments with Codex CLI"
                        let ranker = CodexMomentRanker(codexPath: codex)
                        let codexClips = try await ranker.rank(
                            segments: segments,
                            sourceDuration: duration,
                            workDirectory: workDirectory.appendingPathComponent("codex")
                        )
                        clips = codexClips.isEmpty ? fallbackClips : codexClips
                        appendLog("Codex-ranked clips: \(clips.count)")
                    } catch {
                        clips = fallbackClips
                        appendLog("Codex ranking failed; used local heuristic: \(error.localizedDescription)")
                    }
                } else {
                    clips = fallbackClips
                    appendLog("Codex CLI missing; used local heuristic")
                }

                status = clips.isEmpty ? "No clips found" : "Found \(clips.count) clip candidates"
                appendLog("Transcript segments: \(segments.count)")
                appendLog("Clip candidates: \(clips.count)")
            } catch {
                status = error.localizedDescription
                appendLog(error.localizedDescription)
            }
            isWorking = false
        }
    }

    func exportSelected() {
        guard let sourceURL else { return }
        let selectedClips = clips.filter(\.isSelected)
        guard !selectedClips.isEmpty else {
            status = "Select at least one clip."
            return
        }

        isWorking = true
        progress = 0
        Task {
            do {
                guard let ffmpeg = await ToolLocator.find("ffmpeg") else { throw Clip4XError.missingTool("ffmpeg") }
                guard let ffprobe = await ToolLocator.find("ffprobe") else { throw Clip4XError.missingTool("ffprobe") }
                let mediaTools = MediaTools(ffmpegPath: ffmpeg, ffprobePath: ffprobe)
                let exportRoot = outputDirectory
                    .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
                    .appendingPathComponent(selectedRatio.label)
                try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)

                let tempDirectory = try makeWorkDirectory()
                let overlayRenderer = CaptionOverlayRenderer()

                for (index, clip) in selectedClips.enumerated() {
                    status = "Exporting \(clip.title) (\(index + 1) of \(selectedClips.count))"
                    let outputURL = try await exportClip(
                        clip,
                        sourceURL: sourceURL,
                        mediaTools: mediaTools,
                        overlayRenderer: overlayRenderer,
                        exportRoot: exportRoot,
                        tempDirectory: tempDirectory
                    )
                    progress = Double(index + 1) / Double(selectedClips.count)
                    appendLog("Exported \(outputURL.path)")
                }

                status = "Exported \(selectedClips.count) clip\(selectedClips.count == 1 ? "" : "s")"
                NSWorkspace.shared.open(exportRoot)
            } catch {
                status = error.localizedDescription
                appendLog(error.localizedDescription)
            }
            isWorking = false
            progress = nil
        }
    }

    /// Exports one clip with FFmpeg, records its URL, and returns it. Reuses the
    /// already-exported file when present (so upload can skip re-rendering).
    private func exportClip(
        _ clip: ClipCandidate,
        sourceURL: URL,
        mediaTools: MediaTools,
        overlayRenderer: CaptionOverlayRenderer,
        exportRoot: URL,
        tempDirectory: URL
    ) async throws -> URL {
        if let existing = clip.exportURL, fileManager.fileExists(atPath: existing.path) {
            return existing
        }
        let baseName = safeFileName("\(timecode(clip.start))-\(clip.title)")
        let outputURL = exportRoot.appendingPathComponent(baseName).appendingPathExtension("mp4")
        let overlays = try overlayRenderer.writeOverlays(
            clip: clip,
            ratio: selectedRatio,
            destinationDirectory: tempDirectory.appendingPathComponent(baseName)
        )
        try await mediaTools.exportComposedClip(
            videoURL: sourceURL,
            clip: clip,
            ratio: selectedRatio,
            overlays: overlays,
            destinationURL: outputURL
        )
        markExported(clipID: clip.id, url: outputURL)
        return outputURL
    }

    /// Returns a fully-composed clip (blur-fill, hook title, captions) for
    /// preview. Reuses the exported file if present, otherwise renders into a
    /// cached temp folder. The filename encodes the ratio so switching format
    /// re-renders rather than serving a stale preview.
    func composedPreviewURL(for clip: ClipCandidate) async -> URL? {
        guard let sourceURL else { return nil }
        if let existing = clip.exportURL, fileManager.fileExists(atPath: existing.path) {
            return existing
        }
        do {
            guard let ffmpeg = await ToolLocator.find("ffmpeg") else { throw Clip4XError.missingTool("ffmpeg") }
            guard let ffprobe = await ToolLocator.find("ffprobe") else { throw Clip4XError.missingTool("ffprobe") }
            let mediaTools = MediaTools(ffmpegPath: ffmpeg, ffprobePath: ffprobe)
            let previewDir = fileManager.temporaryDirectory.appendingPathComponent("clip4x-preview")
            try fileManager.createDirectory(at: previewDir, withIntermediateDirectories: true)

            let baseName = safeFileName("\(timecode(clip.start))-\(clip.title)-\(selectedRatio.label)")
            let outputURL = previewDir.appendingPathComponent(baseName).appendingPathExtension("mp4")
            if fileManager.fileExists(atPath: outputURL.path) {
                return outputURL
            }

            let overlayRenderer = CaptionOverlayRenderer()
            let overlays = try overlayRenderer.writeOverlays(
                clip: clip,
                ratio: selectedRatio,
                destinationDirectory: previewDir.appendingPathComponent(baseName + "-overlays")
            )
            try await mediaTools.exportComposedClip(
                videoURL: sourceURL,
                clip: clip,
                ratio: selectedRatio,
                overlays: overlays,
                destinationURL: outputURL
            )
            return outputURL
        } catch {
            appendLog("Preview render failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - YouTube

    func connectYouTube() {
        Task {
            await youtubeAuth.connect()
            if let error = youtubeAuth.lastError {
                appendLog("YouTube: \(error)")
            } else if youtubeAuth.isConnected {
                appendLog("Connected to YouTube")
            }
        }
    }

    func disconnectYouTube() {
        youtubeAuth.disconnect()
        appendLog("Disconnected from YouTube")
    }

    /// Exports (if needed) and uploads all selected clips as Shorts.
    /// When `schedule` is set, the videos publish privately at that time.
    func uploadSelected(schedule: Date? = nil) {
        guard let sourceURL else { return }
        guard youtubeAuth.isConnected else {
            status = "Connect YouTube first."
            return
        }
        let selectedClips = clips.filter(\.isSelected)
        guard !selectedClips.isEmpty else {
            status = "Select at least one clip."
            return
        }

        isWorking = true
        progress = 0
        Task {
            do {
                guard let ffmpeg = await ToolLocator.find("ffmpeg") else { throw Clip4XError.missingTool("ffmpeg") }
                guard let ffprobe = await ToolLocator.find("ffprobe") else { throw Clip4XError.missingTool("ffprobe") }
                let mediaTools = MediaTools(ffmpegPath: ffmpeg, ffprobePath: ffprobe)
                let exportRoot = outputDirectory
                    .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
                    .appendingPathComponent(selectedRatio.label)
                try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
                let tempDirectory = try makeWorkDirectory()
                let overlayRenderer = CaptionOverlayRenderer()
                let uploader = YouTubeUploader()
                let total = Double(selectedClips.count)

                for (index, clip) in selectedClips.enumerated() {
                    status = "Preparing \(clip.title) (\(index + 1) of \(selectedClips.count))"
                    let fileURL = try await exportClip(
                        clip,
                        sourceURL: sourceURL,
                        mediaTools: mediaTools,
                        overlayRenderer: overlayRenderer,
                        exportRoot: exportRoot,
                        tempDirectory: tempDirectory
                    )

                    let token = try await youtubeAuth.validToken()
                    status = "Uploading \(clip.title) (\(index + 1) of \(selectedClips.count))"
                    setUploadState(clipID: clip.id, .uploading(progress: 0))

                    let request = uploadRequest(for: clip, schedule: schedule)
                    let clipID = clip.id
                    let videoID = try await uploader.upload(
                        fileURL: fileURL,
                        request: request,
                        accessToken: token
                    ) { fraction in
                        Task { @MainActor [weak self] in
                            self?.setUploadState(clipID: clipID, .uploading(progress: fraction))
                            self?.progress = (Double(index) + fraction) / total
                        }
                    }

                    markUploaded(clipID: clip.id, videoID: videoID, schedule: schedule)
                    progress = Double(index + 1) / total
                    appendLog("Uploaded \(clip.title) → https://youtu.be/\(videoID)")
                }

                status = schedule == nil
                    ? "Uploaded \(selectedClips.count) clip\(selectedClips.count == 1 ? "" : "s")"
                    : "Scheduled \(selectedClips.count) clip\(selectedClips.count == 1 ? "" : "s")"
            } catch {
                status = error.localizedDescription
                appendLog(error.localizedDescription)
            }
            isWorking = false
            progress = nil
        }
    }

    private func uploadRequest(for clip: ClipCandidate, schedule: Date?) -> YouTubeUploadRequest {
        let title = String(clip.title.prefix(90))
        let description = "\(clip.reason)\n\n#Shorts"
        return YouTubeUploadRequest(
            title: "\(title) #Shorts",
            description: description,
            tags: ["Shorts", clip.theme],
            privacy: schedule == nil ? .public : .private,
            publishAt: schedule
        )
    }

    private func setUploadState(clipID: UUID, _ state: UploadState) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        clips[index].uploadState = state
    }

    private func markUploaded(clipID: UUID, videoID: String, schedule: Date?) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        clips[index].youtubeVideoID = videoID
        clips[index].uploadState = schedule.map(UploadState.scheduled) ?? .published
    }

    func toggleSelection(for clip: ClipCandidate) {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[index].isSelected.toggle()
    }

    func openExport(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func appendLog(_ message: String) {
        log.append(message)
    }

    private func markExported(clipID: UUID, url: URL) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        clips[index].exportURL = url
    }

    private func makeWorkDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent("clip4x-\(UUID().uuidString)")
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func safeFileName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(scalars).replacingOccurrences(of: "  ", with: " ")
        return String(cleaned.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func timecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d%02d", total / 60, total % 60)
    }
}
