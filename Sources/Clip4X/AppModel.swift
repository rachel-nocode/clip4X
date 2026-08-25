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
    @Published var selectedLayout: ExportLayout = .auto
    @Published var clips: [ClipCandidate] = []
    @Published var isWorking = false
    /// 0...1 progress for batch work (export/upload). `nil` = indeterminate.
    @Published var progress: Double?
    @Published var status = "Drop a video to start."
    @Published var log: [String] = []
    @Published var transcriptCount = 0

    let youtubeAuth = YouTubeAuthManager()

    private let fileManager = FileManager.default
    private var cancellables = Set<AnyCancellable>()

    init() {
        youtubeAuth.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

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
        guard sourceURL != nil, !isWorking else { return }
        isWorking = true
        progress = nil
        clips = []
        transcriptCount = 0

        Task {
            do {
                try await runAnalysis()
            } catch {
                status = error.localizedDescription
                appendLog(error.localizedDescription)
            }
            isWorking = false
        }
    }

    /// Paste a YouTube URL, verify it belongs to the connected channel, download,
    /// then run Find Clips.
    func importYouTubeVideo(_ urlString: String) {
        guard !isWorking else { return }
        guard youtubeAuth.isConnected else {
            status = "Connect YouTube first."
            return
        }
        guard youtubeAuth.canImportOwnVideos else {
            status = YouTubeImportError.reconnectRequired.localizedDescription ?? "Reconnect YouTube."
            youtubeAuth.markError("Reconnect YouTube — import needs an extra permission.")
            return
        }

        isWorking = true
        progress = nil
        Task {
            do {
                guard let videoID = YouTubeVideoID.parse(urlString) else {
                    throw YouTubeImportError.invalidURL
                }

                status = "Checking ownership…"
                appendLog("Checking ownership for \(videoID)")
                let token = try await youtubeAuth.validToken()
                let video = try await YouTubeLibrary().verifyOwnership(videoID: videoID, accessToken: token)

                guard let ytdlp = await ToolLocator.find("yt-dlp") else {
                    throw Clip4XError.missingTool("yt-dlp")
                }
                status = "Downloading \(video.title)…"
                appendLog("Downloading \(video.title)")
                let fileURL = try await YouTubeDownloader().download(videoID: videoID, ytDlpPath: ytdlp)

                loadVideo(fileURL)
                appendLog("Imported YouTube video \(videoID)")
                try await runAnalysis()
            } catch {
                status = error.localizedDescription
                appendLog(error.localizedDescription)
                if case YouTubeImportError.reconnectRequired = error {
                    youtubeAuth.markError("Reconnect YouTube — import needs an extra permission.")
                }
            }
            isWorking = false
        }
    }

    private func runAnalysis() async throws {
        guard let sourceURL else { return }

        let pipeline = try await ClipPipeline.make()
        let workDirectory = try makeWorkDirectory()
        status = "Analyzing"
        appendLog("Checking local tools")
        let result = try await pipeline.analyze(videoURL: sourceURL, workDirectory: workDirectory)
        transcriptCount = result.segments.count
        clips = result.clips
        if result.usedCodex {
            appendLog("Codex-ranked clips: \(clips.count)")
        } else {
            appendLog("Used local heuristic for clip ranking")
        }
        status = clips.isEmpty ? "No clips found" : "Found \(clips.count) clip candidates"
        appendLog("Transcript segments: \(result.segments.count)")
        appendLog("Clip candidates: \(clips.count)")
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
                let exportRoot = exportRoot(for: sourceURL)
                try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)

                let tempDirectory = try makeWorkDirectory()

                for (index, clip) in selectedClips.enumerated() {
                    status = "Exporting \(clip.title) (\(index + 1) of \(selectedClips.count))"
                    let outputURL = try await exportClip(
                        clip,
                        sourceURL: sourceURL,
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
        exportRoot: URL,
        tempDirectory: URL
    ) async throws -> URL {
        if let existing = reusableExportURL(for: clip) {
            return existing
        }
        let pipeline = try await ClipPipeline.make()
        let sourceSize = try await pipeline.mediaTools.probeVideoSize(videoURL: sourceURL)
        let baseName = ClipFileName.clipFile(title: clip.title, start: clip.start)
        let outputURL = exportRoot.appendingPathComponent(baseName).appendingPathExtension("mp4")
        try await pipeline.exportClip(
            videoURL: sourceURL,
            clip: clip,
            sourceSize: sourceSize,
            options: ExportOptions(ratio: selectedRatio, layout: selectedLayout),
            destinationURL: outputURL,
            workDirectory: tempDirectory
        )
        markExported(clipID: clip.id, url: outputURL)
        return outputURL
    }

    /// Returns a fully-composed clip (blur-fill, hook title, captions) for
    /// preview. Reuses the exported file if it matches the current framing,
    /// otherwise renders into a cached temp folder. The filename encodes ratio
    /// and layout so switching format re-renders rather than serving a stale preview.
    func composedPreviewURL(for clip: ClipCandidate) async -> URL? {
        guard let sourceURL else { return nil }
        if let existing = reusableExportURL(for: clip) {
            return existing
        }
        do {
            let pipeline = try await ClipPipeline.make()
            let sourceSize = try await pipeline.mediaTools.probeVideoSize(videoURL: sourceURL)
            let previewDir = fileManager.temporaryDirectory.appendingPathComponent("clip4x-preview")
            try fileManager.createDirectory(at: previewDir, withIntermediateDirectories: true)

            let baseName = ClipFileName.safe(
                "\(ClipFileName.timecode(clip.start))-\(clip.title)-\(ClipFileName.layoutFolder(ratio: selectedRatio, layout: selectedLayout))"
            )
            let outputURL = previewDir.appendingPathComponent(baseName).appendingPathExtension("mp4")
            if fileManager.fileExists(atPath: outputURL.path) {
                return outputURL
            }

            try await pipeline.exportClip(
                videoURL: sourceURL,
                clip: clip,
                sourceSize: sourceSize,
                options: ExportOptions(ratio: selectedRatio, layout: selectedLayout),
                destinationURL: outputURL,
                workDirectory: previewDir.appendingPathComponent(baseName + "-work")
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
                let exportRoot = exportRoot(for: sourceURL)
                try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
                let tempDirectory = try makeWorkDirectory()
                let uploader = YouTubeUploader()
                let total = Double(selectedClips.count)

                for (index, clip) in selectedClips.enumerated() {
                    status = "Preparing \(clip.title) (\(index + 1) of \(selectedClips.count))"
                    let fileURL = try await exportClip(
                        clip,
                        sourceURL: sourceURL,
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

    private func exportRoot(for sourceURL: URL) -> URL {
        outputDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathComponent(ClipFileName.layoutFolder(ratio: selectedRatio, layout: selectedLayout))
    }

    private func reusableExportURL(for clip: ClipCandidate) -> URL? {
        guard let existing = clip.exportURL,
              fileManager.fileExists(atPath: existing.path),
              ClipFileName.matchesLayoutFolder(existing, ratio: selectedRatio, layout: selectedLayout)
        else { return nil }
        return existing
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

}
