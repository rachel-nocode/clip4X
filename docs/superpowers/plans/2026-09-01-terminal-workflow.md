# Terminal Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native `clip4x` terminal workflow matching the reference repository: ingest, word-timed transcription, moment selection, restrained vertical rendering, project artifacts/QC, metadata, and safe Zernio daily scheduling.

**Architecture:** Keep parsing and reusable workflow logic in `Clip4XCore`; keep terminal I/O and command dispatch in `Clip4XCLI`. Extend the existing Swift pipeline instead of shipping source-tree-dependent Python helpers. Preserve the macOS app and current `analyze`, `frame`, `export`, and `run` behavior while adding artifact-oriented `workflow` and dry-run-first `schedule` commands.

**Tech Stack:** Swift 6, Swift Testing, Foundation URLSession, AppKit/Vision, FFmpeg/ffprobe, Whisper CLI, yt-dlp, Codex/Claude CLI.

---

### Task 1: Preserve merged app features and generalize ranker selection

**Files:**
- Modify: `Sources/Clip4XCore/ClipPipeline.swift`
- Modify: `Sources/Clip4X/AppModel.swift`
- Modify: `Sources/Clip4X/ContentView.swift`
- Test: `Tests/Clip4XCoreTests/LocalAIMomentRankerTests.swift`
- Test: `Tests/Clip4XCoreTests/YouTubeImportTests.swift`

- [ ] **Step 1: Write failing pipeline-provider test**

```swift
@Test func pipelineCarriesSelectedRankerAndReportsItsName() {
    let pipeline = ClipPipeline(
        mediaTools: MediaTools(ffmpegPath: "/bin/ffmpeg", ffprobePath: "/bin/ffprobe"),
        whisperPath: "/bin/whisper",
        rankerProvider: .claude(path: "/bin/claude")
    )
    #expect(pipeline.rankerProvider?.name == "Claude")
}
```

- [ ] **Step 2: Run test and verify compile failure**

Run: `swift test --filter pipelineCarriesSelectedRankerAndReportsItsName`
Expected: FAIL because `rankerProvider` and `rankerName` do not exist.

- [ ] **Step 3: Replace Codex-only pipeline state with provider state**

```swift
public var rankerProvider: MomentRankerProvider?
public var rankerName: String?
public var usedCodex: Bool { rankerName == "Codex" }
```

- [ ] **Step 4: Resolve app UI conflicts by retaining both framing and ranker controls**

```swift
@Published var selectedLayout: ExportLayout = .auto
@Published var rankerPreference: MomentRankerPreference = .auto
```

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter pipelineCarriesSelectedRankerAndReportsItsName && swift test`
Expected: PASS.

### Task 2: Parse artifact workflow and scheduling commands

**Files:**
- Modify: `Sources/Clip4XCore/ClipCommand.swift`
- Test: `Tests/Clip4XCoreTests/ClipCommandTests.swift`

- [ ] **Step 1: Add failing parser tests**

```swift
@Test func parsesWorkflowAndScheduleOptions() throws {
    let workflow = try ClipCommand.parse(["workflow", "https://youtu.be/abc", "--project", "/tmp/job", "--ranker", "claude"])
    #expect(workflow.verb == .workflow)
    #expect(workflow.projectPath == "/tmp/job")
    #expect(workflow.rankerPreference == .claude)

    let schedule = try ClipCommand.parse(["schedule", "/tmp/job/renders", "--start-date", "2026-09-02", "--time", "08:00"])
    #expect(schedule.verb == .schedule)
    #expect(!schedule.execute)
}
```

- [ ] **Step 2: Run parser test and verify failure**

Run: `swift test --filter parsesWorkflowAndScheduleOptions`
Expected: FAIL because verbs/options are missing.

- [ ] **Step 3: Add command state and validation**

```swift
case workflow
case schedule

public var projectPath: String?
public var rankerPreference: MomentRankerPreference = .auto
public var startDate: String?
public var clockTime: String?
public var timezone: String = "America/Los_Angeles"
public var execute = false
```

- [ ] **Step 4: Update help text and valueless flags**

```text
clip4x workflow INPUT [--project PATH] [--ranker auto|codex|claude]
clip4x schedule RENDERS --start-date YYYY-MM-DD --time HH:MM [--execute]
```

- [ ] **Step 5: Run parser tests**

Run: `swift test --filter ClipCommand`
Expected: PASS.

### Task 3: Create isolated project workspace and deterministic artifacts

**Files:**
- Create: `Sources/Clip4XCore/WorkflowProject.swift`
- Create: `Tests/Clip4XCoreTests/WorkflowProjectTests.swift`

- [ ] **Step 1: Write failing workspace tests**

```swift
@Test func workflowProjectCreatesExpectedFoldersAndVersionsRenders() throws {
    let project = try WorkflowProject.create(root: root)
    #expect(project.sourceDirectory.lastPathComponent == "source")
    #expect(project.analysisDirectory.lastPathComponent == "analysis")
    #expect(project.previewsDirectory.lastPathComponent == "previews")
    #expect(project.rendersDirectory.lastPathComponent == "renders")
    #expect(project.uniqueRenderURL(stem: "01-hook").lastPathComponent == "01-hook.mp4")
}
```

- [ ] **Step 2: Run and verify missing-type failure**

Run: `swift test --filter workflowProjectCreatesExpectedFoldersAndVersionsRenders`
Expected: FAIL because `WorkflowProject` is missing.

- [ ] **Step 3: Implement workspace creation and versioning**

```swift
public struct WorkflowProject: Sendable {
    public let root: URL
    public var sourceDirectory: URL { root.appendingPathComponent("source") }
    public var analysisDirectory: URL { root.appendingPathComponent("analysis") }
    public var previewsDirectory: URL { root.appendingPathComponent("previews") }
    public var rendersDirectory: URL { root.appendingPathComponent("renders") }
}
```

- [ ] **Step 4: Add artifact writers for `candidates.md`, `layouts.json`, `metadata.json`, and `qc.md`**

```swift
try project.writeCandidates(clips)
try project.writeLayouts(layouts)
try project.writeMetadata(metadata)
try project.writeQC(results)
```

- [ ] **Step 5: Run workspace tests**

Run: `swift test --filter WorkflowProject`
Expected: PASS.

### Task 4: Add word-level Whisper timing and restrained caption grouping

**Files:**
- Modify: `Sources/Clip4XCore/Models.swift`
- Modify: `Sources/Clip4XCore/WhisperTranscriber.swift`
- Modify: `Sources/Clip4XCore/CaptionOverlayRenderer.swift`
- Create: `Tests/Clip4XCoreTests/WordCaptionTests.swift`

- [ ] **Step 1: Write failing word decode/group tests**

```swift
@Test func whisperWordsBecomeClipLocalCaptionCards() throws {
    let words = [TranscriptWord(word: "Strong", start: 10, end: 10.4), TranscriptWord(word: "hook.", start: 10.4, end: 11)]
    let cards = CaptionTimeline.cards(words: words, clipStart: 10, clipEnd: 20, maxWords: 6, maxCharacters: 28)
    #expect(cards == [CaptionCard(start: 0, end: 1.08, text: "Strong hook.")])
}
```

- [ ] **Step 2: Run and verify missing types**

Run: `swift test --filter whisperWordsBecomeClipLocalCaptionCards`
Expected: FAIL.

- [ ] **Step 3: Add `TranscriptWord`, optional segment words, and Whisper word timestamps**

```swift
"--word_timestamps", "True"

public struct TranscriptWord: Codable, Hashable, Sendable {
    public var word: String
    public var start: Double
    public var end: Double
}
```

- [ ] **Step 4: Implement punctuation-aware grouping with overlap clamping**

```swift
public enum CaptionTimeline {
    public static func cards(words: [TranscriptWord], clipStart: Double, clipEnd: Double, maxWords: Int = 6, maxCharacters: Int = 28) -> [CaptionCard]
}
```

- [ ] **Step 5: Prefer word cards in overlay renderer, retain segment fallback**

Run: `swift test --filter WordCaption`
Expected: PASS.

### Task 5: Resolve local files and YouTube URLs into project source

**Files:**
- Create: `Sources/Clip4XCore/WorkflowSource.swift`
- Test: `Tests/Clip4XCoreTests/WorkflowSourceTests.swift`

- [ ] **Step 1: Write failing source classification tests**

```swift
@Test func classifiesYouTubeAndLocalInputs() {
    #expect(WorkflowInput.parse("https://youtu.be/abc") == .youtube(URL(string: "https://youtu.be/abc")!))
    #expect(WorkflowInput.parse("/tmp/talk.mov") == .file(URL(fileURLWithPath: "/tmp/talk.mov")))
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter classifiesYouTubeAndLocalInputs`
Expected: FAIL.

- [ ] **Step 3: Implement local copy and yt-dlp download**

```swift
public func resolve(_ input: WorkflowInput, into project: WorkflowProject) async throws -> URL
```

Use `yt-dlp --no-playlist -f bv*+ba/b --merge-output-format mp4` for URLs and reject unreadable outputs.

- [ ] **Step 4: Probe required video/audio streams**

Run: `swift test --filter WorkflowSource`
Expected: PASS.

### Task 6: Orchestrate render, metadata, preview, and QC artifacts

**Files:**
- Create: `Sources/Clip4XCore/WorkflowRunner.swift`
- Modify: `Sources/Clip4XCore/MediaTools.swift`
- Modify: `Sources/Clip4XCLI/main.swift`
- Create: `Tests/Clip4XCoreTests/WorkflowRunnerTests.swift`

- [ ] **Step 1: Write failing workflow planning/QC tests**

```swift
@Test func qcRejectsNonVerticalOrMissingAudio() {
    #expect(WorkflowQC.validate(.init(width: 1920, height: 1080, duration: 30, videoCodec: "h264", audioCodec: "aac")).isFailure)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter WorkflowQC`
Expected: FAIL.

- [ ] **Step 3: Implement runner**

```swift
public func run(input: String, project: WorkflowProject, options: WorkflowOptions, onStatus: @Sendable (String) -> Void) async throws -> WorkflowResult
```

Runner resolves source, analyzes once, writes transcript/candidates/layouts, renders unique 1080x1920 clips, writes metadata, probes each output, extracts start/middle/end preview frames, and writes QC.

- [ ] **Step 4: Wire `workflow` CLI dispatch and JSON/text output**

Run: `swift run clip4x workflow --help`
Expected: help includes project artifacts and output locations.

- [ ] **Step 5: Run unit and synthetic-media integration tests**

Run: `swift test --filter WorkflowRunner`
Expected: PASS.

### Task 7: Implement dry-run-first Zernio scheduling

**Files:**
- Create: `Sources/Clip4XCore/ZernioScheduler.swift`
- Create: `Tests/Clip4XCoreTests/ZernioSchedulerTests.swift`
- Modify: `Sources/Clip4XCLI/main.swift`

- [ ] **Step 1: Write failing schedule tests**

```swift
@Test func scheduleUsesCalendarDaysAcrossDSTAndBothPlatforms() throws {
    let plan = try ZernioSchedule.plan(files: files, startDate: "2026-10-31", time: "08:00", timezone: "America/Los_Angeles", now: now)
    #expect(plan.items.map(\.localHour) == [8, 8])
    #expect(plan.platforms == [.youtube, .tiktok])
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter ZernioSchedule`
Expected: FAIL.

- [ ] **Step 3: Implement natural sort, media validation, calendar-day schedule, and seven-day horizon**

```swift
public static func plan(directory: URL, startDate: String, time: String, timezone: String, now: Date = .now) async throws -> ZernioSchedule
```

- [ ] **Step 4: Implement execute client with one upload per clip, shared URL, persistent request UUID, manifest, and GET verification**

```swift
public func execute(_ plan: ZernioSchedule, credentials: ZernioCredentials) async throws -> [VerifiedZernioPost]
```

Require both YouTube and TikTok account IDs; never emit secrets, account IDs, upload URLs, or public media URLs.

- [ ] **Step 5: Wire `schedule` command; default remains dry run**

Run: `swift test --filter ZernioScheduler`
Expected: PASS.

### Task 8: Documentation, install path, and final verification

**Files:**
- Modify: `README.md`
- Modify: `Package.swift` only if new resources are required

- [ ] **Step 1: Document install and exact commands**

```sh
swift build -c release
install .build/release/clip4x /usr/local/bin/clip4x
clip4x workflow VIDEO_OR_YOUTUBE_URL --project ~/Movies/Clip4X/job
clip4x schedule ~/Movies/Clip4X/job/renders --start-date 2026-09-02 --time 08:00
```

- [ ] **Step 2: Run formatting and conflict scans**

Run: `git diff --check && ! rg -n '<<<<<<<|=======|>>>>>>>' README.md Sources Tests`
Expected: PASS.

- [ ] **Step 3: Run complete suite**

Run: `swift test`
Expected: all tests PASS with no warnings introduced by this work.

- [ ] **Step 4: Build release CLI and inspect help**

Run: `swift build -c release --product clip4x && .build/release/clip4x help`
Expected: release build PASS; help lists `workflow` and `schedule`.

- [ ] **Step 5: Review working tree without committing user changes**

Run: `git status --short && git diff --stat`
Expected: only intended implementation plus preserved pre-existing user edits.
