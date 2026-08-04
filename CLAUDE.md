# CLAUDE.md

Working instructions for this repository.

- **What we're building and why:** [`product.md`](product.md)
- **Build order and current status:** [`planning.md`](planning.md)

Read `product.md` before changing behaviour, and update the status table in `planning.md` as
milestones complete.

---

## Working rule: phases are gated by a human Xcode test

**Implement one phase. Stop. Do not start the next phase until Joshua has run the app in Xcode and
verified that phase's exit criteria himself.**

At the end of a phase:

1. Build it and confirm it compiles with zero warnings.
2. Report each exit criterion from `planning.md` with what you did or didn't verify — be explicit
   about which ones only a human driving the UI can confirm (drag behaviour, visual alignment,
   playback, Finder integration). Do not claim those as passing.
3. Hand over and wait. Do not begin the next milestone, and do not fold the next milestone's work
   into "finishing" the current one.

A failing criterion goes back into the *current* phase. Nothing is carried forward as a known
issue. "The build succeeded" is not evidence a phase is done — the criteria are written to be
observed in the running app.

---

## Project

**Stillframe** — a sandboxed SwiftUI macOS app that extracts still images from video files
at a chosen time interval, with optional per-video crop and trim.

| | |
|---|---|
| Platform | macOS 15.4+ |
| Language | Swift 5 |
| Toolchain | Xcode 16.3 |
| UI | SwiftUI + AppKit interop (`NSViewRepresentable`) |
| Media | AVFoundation, Core Graphics, Image I/O |
| Dependencies | **None.** Apple frameworks only — do not add packages. |
| Sandbox | **Enabled**, and stays that way |

---

## Build & run

```bash
# Build
xcodebuild -project Stillframe.xcodeproj \
           -scheme Stillframe \
           -destination 'platform=macOS' build

# Build and launch
xcodebuild -project Stillframe.xcodeproj \
           -scheme Stillframe \
           -destination 'platform=macOS' \
           -configuration Debug build
open "$(xcodebuild -project Stillframe.xcodeproj -scheme Stillframe \
        -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}')/Stillframe.app"
```

There is no test target. Verification is manual and scripted — see the Verification section of
`planning.md`.

**Adding files:** `Stillframe/` is an Xcode 16 **file-system-synchronized root group**
(`PBXFileSystemSynchronizedRootGroup`). Any `.swift` file written into it — including into new
subfolders like `Model/` or `Services/` — is added to the target automatically. **Do not hand-edit
`project.pbxproj`** to register sources; it isn't needed and risks corrupting the project.

---

## Architecture

```
Stillframe/
  Model/      state and settings — no AVFoundation work, no view code
  Services/   the actual media work — no SwiftUI imports
  Views/      presentation — no CGImage manipulation, no file I/O
```

- **`Model/`** — `VideoItem` (one dropped video: URL, metadata, crop, trim, status),
  `ExportSettings` (global interval / format / quality / output folder),
  `AppModel` (queue, selection, export orchestration). Plain state; delegates work to services.
- **`Services/`** — `VideoMetadata`, `FrameExporter`, `ImageWriter`, `OutputFolderStore`.
  Testable in isolation, no view dependencies.
- **`Views/`** — SwiftUI views plus `PlayerLayerView`, the one `NSViewRepresentable`.
  Views read model state and call into `AppModel`; they never touch pixels or the filesystem.

---

## Conventions

- **`@Observable`**, not `ObservableObject` / `@Published`. Deployment target supports it.
- **`async`/`await`** throughout. No completion handlers, no semaphores, no `DispatchQueue`
  hopping. Use `@MainActor` for UI-facing state.
- **`actor`** for `FrameExporter` — frame generation and encoding stay off the main thread.
- **Cancellation** via structured concurrency: `Task.cancel()` plus `Task.isCancelled` checks
  between frames. Never leave a partially-written run unreported.
- **Errors** surface as per-item status (`.failed(String)`), not `fatalError` or silent `try?`.
  One bad video must not kill a batch.
- SwiftUI views stay small; extract a subview before a `body` grows past roughly 60 lines.
- No third-party dependencies.

---

## Gotchas specific to this repo

### 1. Crop math is always in *display space*

`videoTrack.naturalSize` **ignores rotation** — a portrait iPhone clip reports 1920×1080.
`AVAssetImageGenerator` with `appliesPreferredTrackTransform = true` returns *display-oriented*
images (1080×1920). Mixing the two spaces produces crops that are correct on landscape footage and
wrong on portrait footage, which is exactly the bug that survives casual testing.

`VideoMetadata.load(url:)` defines display space once:

```swift
let size = naturalSize.applying(preferredTransform)   // then abs(width), abs(height)
```

Everything downstream — preview geometry, crop overlay, export cropping — uses that size and
nothing else. Crop rects are stored **normalized (0…1)** so they survive window resizing, and are
denormalized against the *actual `CGImage` pixel dimensions* at export time, made `.integral`, and
clamped to the image bounds before `cgImage.cropping(to:)`.

**Always test crop changes against a portrait clip.**

### 2. The frame-count rule lives in exactly one helper

Sampling is **half-open**: `start, start + interval, …` while `t < end`.
A 10 s video at 0.5 s ⇒ frames at 0.0 … 9.5 ⇒ **20 images**, not 21.

```swift
FrameExporter.sampleTimes(start:end:interval:)   // the only place this is computed
```

The live "→ N images" estimate and the export loop both call it. Never recompute a count inline —
if the estimate and the file count can disagree, eventually they will. Rationale in `product.md`.

### 3. Frames are extracted at exact timestamps

`requestedTimeToleranceBefore` and `requestedTimeToleranceAfter` are both `.zero`. This is slower
than tolerant sampling, and that is a deliberate trade: "one image per 0.5 second" is the entire
premise of the app. Do not loosen tolerance to make exports faster.

### 4. The sandbox shapes the file handling

- Dropped files grant **read** access only — you cannot write next to the source video.
  Output always goes to a folder the user picked through `NSOpenPanel`.
- That folder is persisted as a **security-scoped bookmark**
  (`bookmarkData(options: .withSecurityScope)`), resolved on launch with `.withSecurityScope`,
  wrapped in `startAccessingSecurityScopedResource()` and balanced with `stopAccessing…`.
  Handle `isStale` by re-prompting, not by failing silently.
- Entitlement required: `com.apple.security.files.user-selected.read-write`.
- **Test the relaunch path**, not just the same-session path — that's where bookmark bugs appear.

### 5. `UTType.movie` is too permissive for the drop filter

`.mkv`, `.avi` and `.webm` all conform to `public.movie`, but AVFoundation cannot open them.
Filtering on `.movie` therefore lets files into the queue that fail the moment metadata loads.
`AppModel.acceptedTypes` is an explicit allowlist — `.mpeg4Movie`, `.quickTimeMovie`,
`com.apple.m4v-video` — and any new format must be added there deliberately.

### 6. Don't use SwiftUI's `VideoPlayer`

Use `PlayerLayerView` (`AVPlayerLayer`, `videoGravity = .resizeAspect`). `VideoPlayer`'s built-in
transport controls swallow the crop drag gestures, and we need the exact letterboxed video rect,
which comes from `AVMakeRect(aspectRatio:insideRect:)` — the same computation `.resizeAspect`
performs, so the crop overlay aligns by construction rather than by tuning.

---

## Test assets

`ffmpeg` is not installed. Generate deterministic clips with a small `AVAssetWriter` script in the
scratchpad — 10 s, 30 fps, with the timestamp burned into each frame so frame accuracy is
verifiable by eye. Make both a 1920×1080 landscape and a 1080×1920 portrait variant.

Real footage for spot checks:
`~/Library/Mobile Documents/com~apple~CloudDocs/CafeAlamedaDigitalContent/@Ready@/`

Checking exported dimensions:

```bash
sips -g pixelWidth -g pixelHeight <folder>/*.jpg
```
