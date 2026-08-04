# Stillframe — Implementation Plan

Build order for the product defined in [`product.md`](product.md). Conventions and gotchas live in
[`CLAUDE.md`](CLAUDE.md).

**Principle:** every milestone leaves the app buildable and runnable. Milestone 3 is the first
end-to-end vertical slice — after it, the app already does the core job, and 4–7 make it good.

---

## Phase gate rule

**A phase is not complete until Joshua has opened the project in Xcode, run the app (⌘R), and
verified every exit criterion below it himself.**

- Claude implements a phase, builds it, and reports which exit criteria it believes are met and
  how it checked them.
- Claude then **stops** and hands over for verification. It does not begin the next phase.
- Joshua runs the app from Xcode and walks the exit criteria. Anything that fails goes back into
  the current phase — it is never carried forward as a known issue.
- Once every criterion passes, Joshua marks the phase **verified** in the status table and Claude
  starts the next one.

"Claude built it and the build succeeded" is **not** an exit criterion. Every criterion below is
written to be observable by a human driving the running app.

Each phase gets **3–5 criteria, no more** — the ones that catch the traps. A long checklist stops
being read.

### Standing criteria — apply to every phase

Re-checked at every gate, in addition to the phase's own list:

- [ ] Builds (⌘B) with **zero errors and zero warnings**, runs (⌘R) without a hang
- [ ] Xcode console free of exceptions and purple runtime issues
- [ ] No criterion verified in an earlier phase has regressed

---

## Status

| # | Milestone | Built | Verified in Xcode (Joshua) |
|---|---|---|---|
| 0 | Documentation | done | — |
| 1 | Shell — drop, queue, metadata | done | ☑ verified |
| 2 | Preview — player + geometry | done | ☑ verified |
| 3 | Export core — first working export | done | ☑ verified |
| 4 | Interval UI | done | ☑ verified |
| 5 | Crop | done | ☑ verified |
| 6 | Trim | done | ☑ verified |
| 7 | Batch & lifecycle | done | ☑ verified |

---

## Test assets — build these before milestone 1

`ffmpeg` is not installed. Generate deterministic clips with a small `AVAssetWriter` script, so
frame accuracy is verifiable by eye rather than by trust:

| Asset | Spec |
|---|---|
| `test_landscape.mp4` | 10.0 s, 1920×1080, 30 fps, timestamp burned into every frame |
| `test_portrait.mp4` | 10.0 s, 1080×1920 (rotated), 30 fps, timestamp burned in |
| `test_long.mp4` | 60 s, 1920×1080, for cancel testing |
| `test_broken.mp4` | a truncated/corrupt file, for failure-path testing |

Real footage for spot checks lives under
`~/Library/Mobile Documents/com~apple~CloudDocs/CafeAlamedaDigitalContent/@Ready@/`.

The burned-in timestamp is what makes "the frame at 3.0 s is actually the frame at 3.0 s" checkable
without instrumentation.

---

## Target file layout

```
CLAUDE.md
product.md
planning.md
README.md
Tools/MakeTestAssets.swift    — generates the deterministic test clips
TestAssets/                   — generated, gitignored
Stillframe.xcodeproj/
Stillframe/
  StillframeApp.swift
  ContentView.swift
  Stillframe.entitlements
  Model/
    VideoItem.swift          — one video: url, metadata, crop, trim, export status
    ExportStatus.swift       — where a video stands in a run
    ExportSettings.swift     — global interval / format / quality
    AppModel.swift           — queue, selection, export orchestration
  Services/
    VideoMetadata.swift      — async duration + rotation-corrected display size
    PlayerController.swift   — the single AVPlayer driving preview playback
    CropGeometry.swift       — normalized <-> screen <-> pixel conversions
    FrameExporter.swift      — actor; AVAssetImageGenerator -> cropped CGImages
    ImageWriter.swift        — CGImage -> JPG/PNG on disk
    OutputFolderStore.swift  — NSOpenPanel + security-scoped bookmark
  Views/
    DropZoneView.swift
    QueueSidebarView.swift
    VideoDetailView.swift
    VideoPreviewView.swift   — video rect geometry + transport bar
    PlayerLayerView.swift    — AVPlayerLayer in NSViewRepresentable
    CropOverlayView.swift    — draggable rectangle and handles
    CropControlsView.swift   — crop toggle, aspect lock, pixel readout
    TrimRangeSlider.swift    — playhead + two trim handles on one track
    SettingsBarView.swift    — interval, format, quality, output, Start/Cancel
```

`Stillframe/` is an Xcode 16 **file-system-synchronized group**, so new `.swift` files
placed anywhere inside it (including new subfolders) are compiled automatically — `project.pbxproj`
needs no edits. See `CLAUDE.md`.

---

## Milestone 1 — Shell

Get videos into the app and displayed.

**Files:** `Stillframe.entitlements`, `StillframeApp.swift`, `ContentView.swift`,
`Model/VideoItem.swift`, `Model/AppModel.swift`, `Services/VideoMetadata.swift`,
`Views/DropZoneView.swift`, `Views/QueueSidebarView.swift`

- Flip `com.apple.security.files.user-selected.read-only` →
  **`com.apple.security.files.user-selected.read-write`**. Sandbox stays on.
- Window: minimum size ~900×600, `.windowResizability(.contentMinSize)`.
- `ContentView` = `NavigationSplitView` (sidebar ≈220 pt + detail). When the queue is empty, the
  whole window is `DropZoneView` instead.
- `.dropDestination(for: URL.self)`, accepting only an **allowlist** of `UTType`s —
  `.mpeg4Movie`, `.quickTimeMovie`, `com.apple.m4v-video`. Not `.movie`: `.mkv`, `.avi` and
  `.webm` all conform to `public.movie` but AVFoundation can't open them, so a `.movie` check
  admits files that then fail on load.
  Border highlight on `isTargeted`. Also an "Add Videos…" `.fileImporter` for non-drag users.
- Call `startAccessingSecurityScopedResource()` defensively on each incoming URL.
- `VideoMetadata.load(url:)` fills in duration, rotation-corrected display size, and frame rate.

### Exit criteria

1. [ ] Dropping `test_landscape.mp4` and `test_portrait.mp4` adds two rows, each reading **10.0 s**;
   the landscape row reads **1920×1080** and the portrait row reads **1080×1920** — *not*
   1920×1080 ← the rotation trap
2. [ ] Dropping a `.mkv` or a `.pdf` is refused: no row added, no crash, no console error
3. [ ] Removing a row leaves the others intact; removing the last returns the full drop zone
4. [ ] The drop zone highlights while a video is dragged over it, and the window won't resize
   below ~900×600

**Risk:** `naturalSize` ignores rotation. Correcting it here, once, is what makes milestone 5 work.

---

## Milestone 2 — Preview

**Files:** `Views/PlayerLayerView.swift`, `Views/VideoDetailView.swift`

- `PlayerLayerView`: `NSViewRepresentable` wrapping an `NSView` that hosts an `AVPlayerLayer`
  with `videoGravity = .resizeAspect`.
- **Not** SwiftUI's `VideoPlayer` — its built-in transport controls would swallow the crop drag
  gestures added in milestone 5, and we need the exact letterboxed video rect.
- Compute that rect with `AVMakeRect(aspectRatio: item.displaySize, insideRect: geometryFrame)`,
  which is precisely what `.resizeAspect` does — so the overlay and the video agree by
  construction rather than by tuning.
- Own play/pause button and a playhead driven by `addPeriodicTimeObserver`.
- Detail pane shows filename, duration, resolution, frame rate.

### Exit criteria

1. [ ] Selecting a row plays that video; switching rows mid-playback swaps cleanly with no audio
   bleed-through
2. [ ] The detail pane shows filename, duration, resolution, and frame rate, all matching the file
3. [ ] **Geometry check** — with the computed video rect temporarily stroked in a bright colour, it
   sits exactly on the video's edges (no gap, no overhang) for **both** `test_landscape.mp4` and
   `test_portrait.mp4`, and stays aligned while the window is resized ← everything in milestone 5
   is built on this
4. [ ] The debug stroke lives behind **Debug ▸ Show Video Bounds (⇧⌘B)**, is off by default, and
   is compiled out of release builds — delete the `#if DEBUG` blocks once criterion 3 passes

---

## Milestone 3 — Export core *(first end-to-end slice)*

Full-frame, whole-video export at a hardcoded interval. No crop, no trim, no batch.

**Files:** `Services/FrameExporter.swift`, `Services/ImageWriter.swift`,
`Services/OutputFolderStore.swift`, `Model/ExportSettings.swift`

- **Frame-count helper** — the single source of truth for the half-open rule in `product.md`:
  ```swift
  // times: start, start+i, … while t < end   →   ceil((end - start) / interval)
  static func sampleTimes(start: Double, end: Double, interval: Double) -> [CMTime]
  ```
  Both the live estimate and the export read from this. Nothing else computes counts.
- `FrameExporter` is an `actor`. `AVAssetImageGenerator` with
  `appliesPreferredTrackTransform = true` and `requestedTimeToleranceBefore/After = .zero`.
  Iterate `for try await result in generator.images(for: times)`.
- Report progress via an `AsyncStream` or a `@MainActor` callback.
- Individual failed frames are logged and skipped; only asset/IO errors fail the whole item.
- `ImageWriter`: `CGImageDestinationCreateWithURL`, `UTType.jpeg` / `UTType.png`,
  `kCGImageDestinationLossyCompressionQuality` for JPG only.
- `OutputFolderStore`: `NSOpenPanel` (`canChooseDirectories = true`, `canChooseFiles = false`)
  → `bookmarkData(options: .withSecurityScope)` → `UserDefaults`. On launch, resolve with
  `.withSecurityScope`, `startAccessingSecurityScopedResource()`, hold for the app's lifetime,
  balance on quit or folder change. Re-prompt when the bookmark is stale.
- Folder/file naming per the output contract in `product.md`.

### Exit criteria

1. [ ] Exporting `test_landscape.mp4` at 0.5 s writes **exactly 20** files
   (`ls <folder> | wc -l`) named `test_landscape_0001.jpg … _0020.jpg` into
   `<chosen>/test_landscape_frames/`
2. [ ] Opened in order, the burned-in timestamps read **0.0, 0.5 … 9.5** — no duplicates, no skips,
   and **9.5 is the last**, not 10.0 ← the half-open rule
3. [ ] Exporting the same video again creates `test_landscape_frames 2/` and leaves the first
   folder untouched
4. [ ] **Relaunch test** — quit the app entirely, run again from Xcode, export without touching
   `Choose…`: the folder is remembered and writing still succeeds ← the sandbox trap
5. [ ] `test_broken.mp4` reports a visible failure without crashing the app

**Risks:** security-scoped bookmarks are the most common sandbox failure; the relaunch criterion
above exists specifically to catch it. Zero tolerance makes generation notably slower than tolerant
sampling — that's the accepted trade.

---

## Milestone 4 — Interval UI

**Files:** `Views/SettingsBarView.swift`, `Model/ExportSettings.swift`

- Segmented picker `0.25 / 0.5 / 1 / 2 s` + **Custom** revealing a validated number field
  (positive, sane upper bound, rejects zero/NaN).
- Format picker; quality slider visible only for JPG.
- Output folder path + `Choose…`.
- Live estimate — "→ 20 images from 10.0s" — computed by the milestone 3 helper.
- Settings persist in `UserDefaults`.

### Exit criteria

1. [ ] With `test_landscape.mp4` selected the estimate updates instantly and reads
   0.25 s → **40**, 0.5 s → **20**, 1 s → **10**, 2 s → **5**, custom 0.3 → **34**
2. [ ] **For each of those five values, the exported file count equals the estimate exactly**
3. [ ] A custom value of `0`, a negative number, or text is rejected without crashing, and Start
   stays disabled while it's invalid
4. [ ] PNG hides the quality slider and produces files that report as PNG in Get Info; JPG shows it
5. [ ] Quit and relaunch: interval, format, quality, and output folder are all still set

---

## Milestone 5 — Crop

**Files:** `Views/CropOverlayView.swift`, `Model/VideoItem.swift`

- Overlay drawn inside the *same* `GeometryReader` as the player, positioned by the `AVMakeRect`
  video rect from milestone 2.
- Stored as a **normalized** `CGRect` (0…1) in display space, per video. `nil` = full frame.
- Drag the body to move; eight corner/edge handles to resize; clamped to the video rect.
- Aspect lock (Free, 1:1, 16:9, 9:16, 4:5, 4:3) constrains the opposite dimension while dragging.
- Dim outside the selection; live readout in **source pixels** (`1080×1080 @ (420, 180)`);
  Reset to full frame; a Crop toggle that clears the rect when off.
- Export side: denormalize against the actual `CGImage` pixel size, `.integral`, clamp to the
  image bounds, then `cgImage.cropping(to:)`. Skip entirely when `nil`.

### Exit criteria

1. [ ] The rectangle moves by its body and resizes by all eight handles, clamped inside the video —
   it **cannot** be dragged into the letterbox bars
2. [ ] Aspect lock 1:1 keeps the readout square while dragging any handle, and the readout reports
   **source pixels**, not screen points
3. [ ] **Landscape export** — a 1:1 crop reading e.g. `1080×1080` produces files where
   `sips -g pixelWidth -g pixelHeight <folder>/*.jpg` reports 1080×1080 for **every** file, and the
   content is the region that was drawn
4. [ ] **Portrait export** — the same test on `test_portrait.mp4` lands on the drawn region with the
   expected dimensions ← the rotation trap, verified end to end
5. [ ] A crop set on one video doesn't appear on another, and resizing the window doesn't move it
   relative to the image

**Risks:** the two hard parts are (a) display-space vs. pixel-space conversion on rotated video and
(b) gesture conflicts between move-body and resize-handle drags — give handles priority and a
generous hit area.

---

## Milestone 6 — Trim

**Files:** `Views/TrimRangeSlider.swift`, `Model/VideoItem.swift`

- Dual-handle slider spanning the duration, per video; readout `3.0s – 12.0s`.
- Dragging a handle seeks the player to that time.
- Playhead marker rendered over the same track.
- Handles can't cross; enforce a minimum span of one interval.
- `trimStart` / `trimEnd` feed the frame-count helper — the estimate updates live.

### Exit criteria

1. [ ] Dragging either handle seeks the preview to that time — you can see where you're cutting —
   and the handles cannot cross
2. [ ] Setting 3.0 s – 8.0 s at 0.5 s changes the estimate to **10**
3. [ ] Exporting that range writes **exactly 10** files, the first showing timestamp **3.0** and the
   last **7.5** ← half-open rule again, on a trimmed range
4. [ ] A trim set on one video doesn't carry over to another, and the playhead marker stays visually
   distinct from the two trim handles

---

## Milestone 7 — Batch & lifecycle

**Files:** `Model/AppModel.swift`, `Views/QueueSidebarView.swift`, `Views/SettingsBarView.swift`

- `AppModel.startExport()` spawns one `Task` and processes items **sequentially** —
  `images(for:)` already parallelizes internally, and sequential keeps progress legible and
  memory flat.
- Per-item status: `.pending`, `.exporting(done:total:)`, `.finished(count:folder:)`,
  `.failed(String)`, `.cancelled(partial:)`. Row progress in the sidebar (`11/20`); overall
  determinate bar in the settings bar.
- Guard before starting: output folder set (else trigger the picker), queue non-empty.
- **Cancel** calls `exportTask?.cancel()`; the loop checks `Task.isCancelled` between frames,
  marks the item `.cancelled(partial:)`, leaves written files on disk, and stops the queue.
- A failed item is marked and the queue continues to the next video.
- Completion summary with **Reveal in Finder**
  (`NSWorkspace.shared.activateFileViewerSelecting`) and **Export another** (clears the queue).
- Primary button reads `Start` / `Start All (3)` and becomes `Cancel` while running.

### Exit criteria

1. [ ] **Start All (3)** exports sequentially with live per-row progress (`11/20`) and an overall
   bar; the UI stays responsive and selecting another row mid-export doesn't disturb it
2. [ ] **Independence** — three clips with three different crops and trims produce three subfolders,
   each matching that clip's own settings
3. [ ] **Cancel** during `test_long.mp4` stops within about a second, reports a partial count, keeps
   the already-written files openable on disk, and a fresh export can start immediately after
4. [ ] A queue containing `test_broken.mp4` fails **only** that row, with a readable message, and
   continues through the remaining videos
5. [ ] **Reveal in Finder** opens Finder with the output folder selected; **Export another** clears
   the queue back to the drop zone

---

## Risks

1. **Rotated-video crop math** — `naturalSize` doesn't account for rotation, and
   `appliesPreferredTrackTransform` returns display-oriented images. Mixing the two spaces puts
   crops in the wrong place on portrait clips only, so it survives casual testing. Mitigation:
   `VideoMetadata` defines display space once (milestone 1) and everything downstream uses it;
   a portrait clip is an exit criterion for milestones 1, 2, and 5.
2. **Security-scoped bookmark staleness** — works in the same session, fails after relaunch or
   when the folder moves. Mitigation: the relaunch test is a milestone 3 exit criterion, not an
   afterthought; handle `isStale` by re-prompting rather than failing silently.
3. **Crop overlay gesture conflicts** — move-body vs. resize-handle drags competing, and the
   reason `VideoPlayer` was rejected in milestone 2. Mitigation: handles take gesture priority
   with a hit area larger than their visual size; drags clamp rather than reject.

---

## Final regression pass — **not yet run**

All seven milestones are individually verified, but the end-to-end pass below hasn't been done in
one sitting. Worth doing before calling v1 shipped, since the milestones were verified as they
landed and later ones could have disturbed earlier behaviour.

Run the whole product in one sitting, in Xcode:

1. **Build** — ⌘B, zero errors, zero warnings.
2. **Core flow** — drop `test_landscape.mp4`, interval 0.5 s, estimate reads 20, export,
   20 files, timestamps 0.0 … 9.5.
3. **Crop** — 1:1 crop, export, `sips -g pixelWidth -g pixelHeight` matches the readout everywhere.
4. **Trim** — 3 s – 8 s at 0.5 s ⇒ 10 images starting at 3.0.
5. **Rotation** — `test_portrait.mp4` exports portrait images; crop lands where drawn.
6. **Batch** — three clips, different crops/trims, Start All, three correct subfolders.
7. **Cancel** — cancel `test_long.mp4` mid-run; partial count reported, files kept.
8. **Persistence** — quit, relaunch, export; no folder re-prompt, writing succeeds.
9. **PNG** — quality slider hides, files are valid PNGs.
10. **Success criteria** — all nine in `product.md` demonstrably met.
