import AppKit
import AVKit
import Clip4XCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var previewClip: ClipCandidate?

    var body: some View {
        ZStack {
            MDColor.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                appBar

                if model.isWorking {
                    WorkProgressBar(value: model.progress)
                }

                HStack(spacing: 0) {
                    workflowPanel
                        .frame(width: 360)

                    Rectangle()
                        .fill(MDColor.outline)
                        .frame(width: 1)

                    clipsSurface
                }
            }
        }
        .tint(MDColor.primary)
        .sheet(item: $previewClip) { clip in
            ClipPreviewSheet(clip: clip)
                .environmentObject(model)
        }
    }

    private var appBar: some View {
        HStack(spacing: 14) {
            AppIconBadge(size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Clip4X")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MDColor.onSurface)
                Text("Find, review, and export clean clips")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MDColor.muted)
            }

            Spacer()

            StatusPill(
                icon: model.isWorking ? "progress.indicator" : "checkmark.circle.fill",
                text: model.isWorking ? "Working" : "Ready",
                color: model.isWorking ? MDColor.primary : MDColor.success
            )
        }
        .padding(.horizontal, 24)
        .frame(height: 72)
        .background(MDColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MDColor.outline)
                .frame(height: 1)
        }
    }

    private var workflowPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dropZone
                formatSection
                actionSection
                YouTubeSection(auth: model.youtubeAuth)
                    .environmentObject(model)
                statusPanel
            }
            .padding(24)
        }
        .background(MDColor.canvas)
    }

    private var dropZone: some View {
        Button {
            model.chooseVideo()
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(MDColor.primaryContainer)
                            .frame(width: 52, height: 52)
                        Image(systemName: model.sourceURL == nil ? "arrow.down.doc.fill" : "film.stack.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(MDColor.primary)
                    }

                    Spacer()

                    Image(systemName: "add")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(MDColor.primary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.sourceURL?.lastPathComponent ?? "Drop a video")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(MDColor.onSurface)
                        .lineLimit(2)

                    Text(model.sourceURL?.path(percentEncoded: false) ?? "MP4, MOV, or any FFmpeg-readable video")
                        .font(.system(size: 13))
                        .foregroundStyle(MDColor.muted)
                        .lineLimit(3)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 196, alignment: .leading)
            .background(MDColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .foregroundStyle(MDColor.primary.opacity(0.42))
            )
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.loadVideo(url)
            return true
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Format")

            HStack(spacing: 8) {
                ForEach(ExportRatio.allCases) { ratio in
                    Button {
                        model.selectedRatio = ratio
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: ratio == .vertical ? "rectangle.portrait" : "square")
                                .font(.system(size: 13, weight: .semibold))
                            Text(ratio.label)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ChipButtonStyle(selected: model.selectedRatio == ratio))
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            Button {
                model.analyze()
            } label: {
                Label("Find Clips", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledButtonStyle())
            .disabled(model.sourceURL == nil || model.isWorking)

            Button {
                model.exportSelected()
            } label: {
                Label("Export Selected", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TonalButtonStyle())
            .disabled(model.clips.filter(\.isSelected).isEmpty || model.isWorking)

            Button {
                model.chooseOutputDirectory()
            } label: {
                Label("Output Folder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlineButtonStyle())
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Status")

            HStack(alignment: .top, spacing: 10) {
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 1)
                } else {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundStyle(MDColor.primary)
                }

                Text(model.status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MDColor.onSurface)
                    .lineLimit(4)
            }

            if model.transcriptCount > 0 {
                MetadataPill(icon: "text.bubble", text: "\(model.transcriptCount) transcript segments")
            }

            if !model.log.isEmpty {
                Divider()
                    .overlay(MDColor.outline)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(model.log.suffix(6).enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MDColor.muted)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MDColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MDColor.outline, lineWidth: 1)
        )
    }

    private var clipsSurface: some View {
        VStack(spacing: 0) {
            clipsHeader

            if model.clips.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.clips) { clip in
                            ClipCard(clip: clip, onPreview: { previewClip = $0 })
                                .environmentObject(model)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(MDColor.canvas)
    }

    private var clipsHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Clip candidates")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(MDColor.onSurface)
                Text("Whisper transcribes. Codex ranks. FFmpeg exports blurred-background clips with captions.")
                    .font(.system(size: 13))
                    .foregroundStyle(MDColor.muted)
            }

            Spacer()

            MetadataPill(icon: "rectangle.on.rectangle", text: model.selectedRatio.label)
            MetadataPill(icon: "checkmark.circle", text: "\(model.clips.filter(\.isSelected).count) selected")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(MDColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MDColor.outline)
                .frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MDColor.primaryContainer)
                    .frame(width: 76, height: 76)
                Image(systemName: "rectangle.stack.badge.play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(MDColor.primary)
            }

            Text("No clips yet")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(MDColor.onSurface)
            Text("Drop a video, run Find Clips, then pick the strongest moments.")
                .font(.system(size: 14))
                .foregroundStyle(MDColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipCard: View {
    @EnvironmentObject private var model: AppModel
    var clip: ClipCandidate
    var onPreview: (ClipCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Toggle("", isOn: Binding(
                    get: { clip.isSelected },
                    set: { _ in model.toggleSelection(for: clip) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text(clip.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(MDColor.onSurface)
                        .lineLimit(2)

                    Text(clip.reason)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MDColor.muted)
                        .lineLimit(2)
                }

                Spacer()

                ScoreBadge(score: clip.score)
            }

            Text(clip.transcript.map(\.text).joined(separator: " "))
                .font(.system(size: 14))
                .foregroundStyle(MDColor.onSurface)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                MetadataPill(icon: "clock", text: DurationFormatter.short(clip.start))
                MetadataPill(icon: "timer", text: clip.displayDuration)
                MetadataPill(icon: "tag", text: clip.theme)

                UploadStatePill(state: clip.uploadState)

                Spacer()

                Button {
                    onPreview(clip)
                } label: {
                    Label("Preview", systemImage: "play.circle")
                }
                .buttonStyle(OutlineButtonStyle(compact: true))

                if let youtubeURL = clip.youtubeURL {
                    Button {
                        model.openExport(youtubeURL)
                    } label: {
                        Label("YouTube", systemImage: "play.tv")
                    }
                    .buttonStyle(OutlineButtonStyle(compact: true))
                }

                if let exportURL = clip.exportURL {
                    Button {
                        model.openExport(exportURL)
                    } label: {
                        Label("Open", systemImage: "play.rectangle")
                    }
                    .buttonStyle(OutlineButtonStyle(compact: true))
                }
            }
        }
        .padding(16)
        .background(MDColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(clip.isSelected ? MDColor.primary : MDColor.outline, lineWidth: clip.isSelected ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 8, y: 2)
    }
}

private struct AppIconBadge: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let image = appIcon {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(MDColor.primary)
                    .background(MDColor.primaryContainer)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
    }

    private var appIcon: NSImage? {
        NSImage(named: "Clip4X")
            ?? Bundle.main.url(forResource: "Clip4X", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(contentsOfFile: "/Users/witchaudio/Developer/clip4X/Assets/AppIcon/Clip4X.icns")
    }
}

private struct SectionLabel: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(MDColor.muted)
    }
}

private struct MetadataPill: View {
    var icon: String
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(MDColor.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(MDColor.surfaceMuted)
        .clipShape(Capsule())
    }
}

private struct StatusPill: View {
    var icon: String
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.11))
        .clipShape(Capsule())
    }
}

private struct ScoreBadge: View {
    var score: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("score")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(MDColor.primary)
        .frame(width: 58, height: 52)
        .background(MDColor.primaryContainer)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(isEnabled ? MDColor.onPrimary : MDColor.muted)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(isEnabled ? (configuration.isPressed ? MDColor.primaryHover : MDColor.primary) : MDColor.outlineStrong)
            .clipShape(Capsule())
    }
}

private struct TonalButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(isEnabled ? MDColor.primary : MDColor.muted)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(isEnabled ? MDColor.primaryContainer.opacity(configuration.isPressed ? 0.72 : 1) : MDColor.surfaceMuted)
            .clipShape(Capsule())
    }
}

private struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 14, weight: .bold))
            .foregroundStyle(isEnabled ? MDColor.primary : MDColor.muted)
            .padding(.horizontal, compact ? 10 : 16)
            .frame(height: compact ? 32 : 42)
            .background(MDColor.surface.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isEnabled ? MDColor.outlineStrong : MDColor.outline, lineWidth: 1)
            )
    }
}

private struct ChipButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? MDColor.primary : MDColor.onSurface)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(selected ? MDColor.primaryContainer : MDColor.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selected ? MDColor.primary : MDColor.outline, lineWidth: selected ? 1.5 : 1)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct YouTubeSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var auth: YouTubeAuthManager
    @State private var showSchedule = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("YouTube")

            if !auth.isConfigured {
                notConfigured
            } else if !auth.isConnected {
                Button {
                    model.connectYouTube()
                } label: {
                    Label("Connect YouTube", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TonalButtonStyle())
                .disabled(model.isWorking)
            } else {
                connected
            }

            if let error = auth.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(MDColor.muted)
                    .lineLimit(2)
            }
        }
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set the \(YouTubeConfig.clientIDKey) environment variable to upload Shorts directly.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MDColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openSetupGuide()
            } label: {
                Label("Setup guide", systemImage: "book")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlineButtonStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MDColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(MDColor.outline, lineWidth: 1)
        )
    }

    private var connected: some View {
        VStack(spacing: 10) {
            HStack {
                StatusPill(icon: "checkmark.seal.fill", text: "Connected", color: MDColor.success)
                Spacer()
                Button("Disconnect") { model.disconnectYouTube() }
                    .buttonStyle(OutlineButtonStyle(compact: true))
            }

            Button {
                model.uploadSelected()
            } label: {
                Label("Upload as Shorts", systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledButtonStyle())
            .disabled(uploadDisabled)

            Button {
                showSchedule = true
            } label: {
                Label("Schedule…", systemImage: "calendar.badge.clock")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TonalButtonStyle())
            .disabled(uploadDisabled)
            .popover(isPresented: $showSchedule) {
                schedulePopover
            }
        }
    }

    private var schedulePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Schedule publish")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MDColor.onSurface)
            Text("Uploaded privately, auto-published by YouTube at this time.")
                .font(.system(size: 12))
                .foregroundStyle(MDColor.muted)

            DatePicker("", selection: $scheduleDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()

            Button {
                showSchedule = false
                model.uploadSelected(schedule: scheduleDate)
            } label: {
                Label("Schedule upload", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledButtonStyle())
        }
        .padding(18)
        .frame(width: 300)
        .background(MDColor.surface)
    }

    private var uploadDisabled: Bool {
        model.isWorking || model.clips.filter(\.isSelected).isEmpty
    }

    private func openSetupGuide() {
        // Prefer a copy bundled with the packaged app; when running unbundled
        // (swift run), fall back to the file in the working directory; finally
        // the GitHub-hosted guide.
        if let bundled = Bundle.main.url(forResource: "youtube-setup", withExtension: "html") {
            NSWorkspace.shared.open(bundled)
            return
        }
        let local = URL(fileURLWithPath: "youtube-setup.html")
        if FileManager.default.fileExists(atPath: local.path) {
            NSWorkspace.shared.open(local)
            return
        }
        if let remote = URL(string: "https://github.com/rachel-nocode/clip4X/blob/main/youtube-setup.html") {
            NSWorkspace.shared.open(remote)
        }
    }
}

private struct UploadStatePill: View {
    var state: UploadState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case let .uploading(progress):
            pill(icon: "arrow.up.circle", text: "\(Int(progress * 100))%", color: MDColor.primary)
        case let .scheduled(date):
            pill(icon: "calendar.badge.clock", text: shortDate(date), color: MDColor.primary)
        case .published:
            pill(icon: "checkmark.circle.fill", text: "Published", color: MDColor.success)
        case let .failed(message):
            pill(icon: "exclamationmark.triangle.fill", text: message, color: Color(hex: 0xF28B82))
        }
    }

    private func pill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d h:mma"
        return formatter.string(from: date)
    }
}

private struct WorkProgressBar: View {
    /// `nil` renders an indeterminate (animated) bar.
    var value: Double?

    var body: some View {
        Group {
            if let value {
                ProgressView(value: min(max(value, 0), 1))
            } else {
                ProgressView()
            }
        }
        .progressViewStyle(.linear)
        .tint(MDColor.primary)
        .frame(height: 2)
        .background(MDColor.surface)
    }
}

/// AppKit AVPlayerView wrapper. Avoids AVKit's SwiftUI `VideoPlayer`, whose
/// generic metadata fails to initialize in an unbundled SwiftPM executable.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

private struct ClipPreviewSheet: View {
    @EnvironmentObject private var model: AppModel
    let clip: ClipCandidate
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var rendering = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MDColor.onSurface)
                        .lineLimit(1)
                    Text("\(DurationFormatter.short(clip.start)) – \(DurationFormatter.short(clip.end)) · \(clip.displayDuration) · \(model.selectedRatio.label)")
                        .font(.system(size: 12))
                        .foregroundStyle(MDColor.muted)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(OutlineButtonStyle(compact: true))
            }
            .padding(16)

            if let player {
                PlayerView(player: player)
                    .frame(minWidth: 360, minHeight: 480)
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(rendering ? "Rendering preview with captions…" : "Preview unavailable")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MDColor.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 480)
            }
        }
        .frame(width: 440, height: 640)
        .background(MDColor.canvas)
        .task { await load() }
        .onDisappear { player?.pause(); player = nil }
    }

    private func load() async {
        rendering = true
        let url = await model.composedPreviewURL(for: clip)
        rendering = false
        guard let url else { return }
        let player = AVPlayer(url: url)
        self.player = player
        player.play()
    }
}

private enum MDColor {
    // Dark mode palette (Material dark + Google dark-blue accent)
    static let primary = Color(hex: 0x8AB4F8)
    static let primaryHover = Color(hex: 0xAECBFA)
    static let primaryContainer = Color(hex: 0x28354B)
    static let canvas = Color(hex: 0x121316)
    static let surface = Color(hex: 0x1E1F22)
    static let surfaceMuted = Color(hex: 0x2A2B2F)
    static let onSurface = Color(hex: 0xE8EAED)
    static let muted = Color(hex: 0x9AA0A6)
    static let outline = Color(hex: 0x3C4043)
    static let outlineStrong = Color(hex: 0x5F6368)
    static let success = Color(hex: 0x81C995)
    static let onPrimary = Color(hex: 0x0B1320)
}

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
