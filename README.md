<div align="center">

<img src="Assets/AppIcon/clip4x-icon.png" width="120" alt="Clip4X icon" />

# Clip4X

**Local-first macOS clipper — app or terminal — that turns long videos into captioned Shorts.**

Drop a video (or pass it to `clip4x`) → Whisper transcribes → Codex or Claude ranks the
strongest moments → FFmpeg exports vertical `9:16` or square `1:1` clips.

**Talking-head + demo framing:** `stack` keeps your face in the lower ~66% and floats the
window you are showing as a rounded card on top. Use `clip4x frame` to tune the crop
before you encode.

Clipping runs entirely on your machine. Uploading is optional through YouTube or Zernio.

</div>

---

## Features

- **Drag-and-drop** any FFmpeg-readable video (MP4, MOV, …).
- **Import your own YouTube video** — paste a URL after connecting your channel.
- **Local transcription** with [`openai-whisper`](https://github.com/openai/whisper) — timestamped segments.
- **Moment ranking** via the Codex CLI or Claude Code CLI to surface cohesive, viral-friendly clips.
- **One-click or one-command export** to `9:16` (vertical) or `1:1` (square).
- **Framing modes:** `auto`, `stack` (face + rounded demo window), `face`, `fit`.
- **Terminal CLI** (`clip4x`) — ingest, analyze, preview, render, QC, and schedule.
- **Blurred-fill background**, sticky hook + caption overlays.
- **Dark mode UI** built in SwiftUI.
- **Post to YouTube Shorts** directly — connect your account via OAuth, upload now or schedule.
- Exports land in `~/Desktop/Clip4X Exports` by default (configurable in-app).

## Post to YouTube (optional)

Clip4X can upload exported clips straight to YouTube as Shorts, immediately or on a
schedule. Because Clip4X is open source, it ships **no shared Google credentials** —
you create your own OAuth client once (free, ~5 minutes) so your uploads run under
your own account and quota. No keys are typed into the app: you set one environment
variable, then click **Connect**.

1. Follow [`youtube-setup.html`](youtube-setup.html) to create a Google Cloud
   "Desktop app" OAuth client and add yourself as a test user.
2. Export your Client ID before launching:

   ```sh
   export CLIP4X_YT_CLIENT_ID="xxxx.apps.googleusercontent.com"
   export CLIP4X_YT_CLIENT_SECRET="GOCSPX-..."
   ```

   > Google Desktop OAuth clients issue **both** a Client ID and a Client secret,
   > and Google's token endpoint requires the secret — set both.

3. In the app: **Connect YouTube** → authorize in the browser → **Upload as Shorts**
   or **Schedule…**. Paste a URL to one of *your* videos to import and clip it.

The OAuth refresh token is stored in the macOS Keychain (`audio.witch.clip4x.youtube`).
Scheduled uploads use YouTube's native `publishAt` — the app does not need to be
running at publish time.

Clip4X requests `youtube.upload` (publish Shorts) and `youtube.readonly` (confirm
the pasted URL is on your channel). Tokens saved before this change need
**Disconnect** then **Connect** once. Import only accepts videos on the connected
channel. Private videos may fail to download — grab those from YouTube Studio and
drop the file instead.

> **Limits (per-user, Testing-mode project):** ~6 uploads/day (`videos.insert` costs
> 1600 of 10,000 daily quota units), and the OAuth consent may need re-approving every
> 7 days. A clip is treated as a Short by being vertical/square, ≤ 3 min, with
> `#Shorts` in the title/description — Clip4X adds that automatically.

## Requirements

macOS 14 (Sonoma) or later, plus these tools on your `PATH`:

```sh
brew install ffmpeg openai-whisper yt-dlp
```

| Tool       | Used for                                              |
|------------|-------------------------------------------------------|
| `ffmpeg`   | Rendering clips (blurred fill, overlays, captions)    |
| `ffprobe`  | Reading source media metadata                         |
| `whisper`  | Local timestamped transcription                       |
| `yt-dlp`   | Downloading your own YouTube videos for import        |
| `codex` or `claude` | Ranking transcript segments into clip candidates |

## Precise talking-head + demo crop

Letterboxing a landscape recording into 9:16 makes both you and the product tiny.
A face-only crop keeps you, but cuts the window you are demoing.

Record landscape with your face large in the **lower half** and the UI visible
**above you or beside you**. Then:

```sh
# 1. Preview one frame (PNG). Prints detected face/demo as x,y,w,h (0...1, top-left).
swift run clip4x -- frame talk.mov --layout stack --at 8 --json --out /tmp/preview.png

# 2. If the window or face is off, pin the regions and re-preview.
swift run clip4x -- frame talk.mov --layout stack --at 8 \
  --face 0.22,0.46,0.56,0.50 \
  --demo 0.16,0.04,0.68,0.36 \
  --out /tmp/preview.png

# 3. Export clips once the still looks right.
swift run clip4x -- run talk.mov --layout stack --out ~/Desktop/Clip4X\ Exports
```

| Layout | What it does |
|--------|----------------|
| `auto` | Stack when a demo window is found, else face crop, else fit |
| `stack` | Face on the bottom, rounded demo card on top (Shorts look) |
| `face` | Tight crop around the speaker |
| `fit` | Full frame, letterboxed on a blur fill |

`--face` / `--demo` are normalized `x,y,w,h` in **0...1**, origin **top-left**.
`--face-band` (default `0.66`) is how much of the 9:16 frame the face occupies.

## Terminal

```sh
swift run clip4x -- help
swift run clip4x -- analyze talk.mov --json
swift run clip4x -- export talk.mov --start 12 --end 48 --layout stack --title "The hook"
swift run clip4x -- frame talk.mov --layout stack --out /tmp/preview.png
```

A video path with no verb runs the full pipeline (`analyze` + `export`).

### Full artifact workflow

`workflow` follows the advanced clipping flow: local/YouTube ingest, word-timed
Whisper transcription, Codex or Claude moment selection, face + screen analysis,
unique 1080×1920 renders, three-point preview frames, metadata, and stream-level QC.

```sh
swift run clip4x -- workflow talk.mov \
  --project ~/Movies/Clip4X/talk \
  --layout stack \
  --ranker auto

swift run clip4x -- workflow https://youtu.be/VIDEO_ID \
  --project ~/Movies/Clip4X/youtube-talk
```

Each project contains `source/`, `analysis/`, `previews/`, and `renders/`.
Analysis writes `transcript.json`, `candidates.md`, `layouts.json`, and `qc.md`;
renders writes uniquely versioned MP4s plus `metadata.json`.

### Zernio daily Shorts

Scheduling always previews first, targets YouTube + TikTok together, preserves the
local clock across DST, uploads each asset once, and verifies every created post.
Temporary Zernio media limits each batch to a seven-day publishing horizon.

```sh
export ZERNIO_API_KEY="..."
export ZERNIO_YOUTUBE_ACCOUNT_ID="..."  # optional; resolved when omitted
export ZERNIO_TIKTOK_ACCOUNT_ID="..."   # optional; resolved when omitted

# Dry run: no network writes
swift run clip4x -- schedule ~/Movies/Clip4X/talk/renders \
  --start-date 2026-09-02 --time 08:00 \
  --timezone America/Los_Angeles

# Execute only after checking preview
swift run clip4x -- schedule ~/Movies/Clip4X/talk/renders \
  --start-date 2026-09-02 --time 08:00 \
  --timezone America/Los_Angeles --execute
```

Use `--env-file /protected/path/zernio.env` instead of exported variables when
preferred. Credentials, account IDs, and media URLs are never printed.

### Install the release CLI

```sh
swift build -c release --product clip4x
install .build/release/clip4x /usr/local/bin/clip4x
```

## Run the app from source

```sh
swift run Clip4X
```

## Project layout

```
Sources/
  Clip4X/          SwiftUI app (UI, AppModel)
  Clip4XCLI/       Terminal entry point (`clip4x`)
  Clip4XCore/      Pipeline: transcription, ranking, FFmpeg, captions, framing
Assets/AppIcon/    App icon (.icns + iconset)
```

## License

MIT License. © 2026 Rachel Larralde. See [LICENSE](LICENSE).
