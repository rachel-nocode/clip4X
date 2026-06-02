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
    @Published var status = "Drop a video to start."
    @Published var log: [String] = []
    @Published var transcriptCount = 0

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

                for clip in selectedClips {
                    status = "Exporting \(clip.title)"
                    let baseName = safeFileName("\(timecode(clip.start))-\(clip.title)")
                    let outputURL = exportRoot.appendingPathComponent(baseName).appendingPathExtension("mp4")
                    let overlayDirectory = tempDirectory.appendingPathComponent(baseName)
                    let overlays = try overlayRenderer.writeOverlays(
                        clip: clip,
                        ratio: selectedRatio,
                        destinationDirectory: overlayDirectory
                    )

                    try await mediaTools.exportComposedClip(
                        videoURL: sourceURL,
                        clip: clip,
                        ratio: selectedRatio,
                        overlays: overlays,
                        destinationURL: outputURL
                    )

                    markExported(clipID: clip.id, url: outputURL)
                    appendLog("Exported \(outputURL.path)")
                }

                status = "Exported \(selectedClips.count) clip\(selectedClips.count == 1 ? "" : "s")"
                NSWorkspace.shared.open(exportRoot)
            } catch {
                status = error.localizedDescription
                appendLog(error.localizedDescription)
            }
            isWorking = false
        }
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
