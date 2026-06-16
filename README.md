<div align="center">

<img src="Assets/AppIcon/clip4x-icon.png" width="120" alt="Clip4X icon" />

# Clip4X

**Local-first macOS app that turns long videos into clean, captioned short clips.**

Drop a video → Whisper transcribes → Codex ranks the strongest moments → FFmpeg exports
vertical `9:16` or square `1:1` clips with blurred-fill backgrounds and burned-in captions.

Runs entirely on your machine. No uploads, no cloud, no accounts.

</div>

---

## Features

- **Drag-and-drop** any FFmpeg-readable video (MP4, MOV, …).
- **Local transcription** with [`openai-whisper`](https://github.com/openai/whisper) — timestamped segments.
- **Moment ranking** via the Codex CLI to surface cohesive, viral-friendly clips.
- **One-click export** to `9:16` (vertical) or `1:1` (square).
- **Blurred-fill background** with the source centered, plus sticky hook + caption overlays.
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
   or **Schedule…**.

The OAuth refresh token is stored in the macOS Keychain (`audio.witch.clip4x.youtube`).
Scheduled uploads use YouTube's native `publishAt` — the app does not need to be
running at publish time.

> **Limits (per-user, Testing-mode project):** ~6 uploads/day (`videos.insert` costs
> 1600 of 10,000 daily quota units), and the OAuth consent may need re-approving every
> 7 days. A clip is treated as a Short by being vertical/square, ≤ 3 min, with
> `#Shorts` in the title/description — Clip4X adds that automatically.

## Requirements

macOS 14 (Sonoma) or later, plus these tools on your `PATH`:

```sh
brew install ffmpeg openai-whisper
```

| Tool       | Used for                                              |
|------------|-------------------------------------------------------|
| `ffmpeg`   | Rendering clips (blurred fill, overlays, captions)    |
| `ffprobe`  | Reading source media metadata                         |
| `whisper`  | Local timestamped transcription                       |
| `codex`    | Ranking transcript segments into clip candidates      |

## Run from source

```sh
swift run Clip4X
```

## Project layout

```
Sources/
  Clip4X/          SwiftUI app (UI, AppModel)
  Clip4XCore/      Pipeline: transcription, ranking, FFmpeg, captions
Assets/AppIcon/    App icon (.icns + iconset)
```

## License

MIT License. © 2026 Rachel Larralde. See [LICENSE](LICENSE).
