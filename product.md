# Stillframe — Product Definition

## What it is

A small, single-purpose macOS app that turns video files into a set of still images. You drop
videos in, preview each one, optionally restrict **where** in the frame (crop) and **when** in the
timeline (trim) the images come from, choose how often to sample, and export numbered JPG or PNG
files into a folder you pick.

**Who it's for:** anyone who needs frames out of a video without opening a video editor —
building reference sheets, pulling stills for design work, assembling image datasets, or grabbing
a specific moment from a clip. The app assumes no video-editing knowledge and has no timeline,
no tracks, and no rendering pipeline.

**The whole product in one sentence:** drag a video in, say "one image every half second," get a
folder of images.

---

## User flow

The original brief, extended with the crop and trim steps:

1. App launches — the window is a single large drop zone.
2. User drags and drops one or more videos (`.mp4`, `.mov`, `.m4v`).
3. Each video appears in a queue sidebar; selecting one shows a **preview** with its info
   (duration, resolution, frame rate).
4. *(Optional)* User drags a **crop rectangle** directly on the preview to target a region.
5. *(Optional)* User sets a **trim range** with the dual-handle slider under the preview to limit
   which part of the video is sampled.
6. User selects an interval — e.g. **one image per 0.5 second** — and sees a live count estimate.
7. User clicks **Start**.
8. A progress indicator runs, per-video and overall, with a **Cancel** button.
9. The images are written to a subfolder of the chosen output folder, and the app offers
   **Reveal in Finder**.

Steps 4 and 5 are per-video. Step 6 and the output settings are global across the queue.

---

## Decisions

| Area | Decision | Rationale | Rejected |
|---|---|---|---|
| **Interval** | Segmented picker `0.25 / 0.5 / 1 / 2 s` plus a **Custom** field, with a live "→ N images" estimate | The common cases are one click; anything else is still reachable. The estimate is the feedback loop that makes the setting comprehensible — you see "20 images" before committing. | *Free number field only* — more typing for the 90% case. *Multiple modes (interval / fps / total count)* — three ways to express one idea, more UI and more to test, for a need that hasn't appeared yet. |
| **Crop** | Draggable rectangle **on the preview** with resize handles, aspect lock (Free, 1:1, 16:9, 9:16, 4:5, 4:3), and Reset to full frame | Framing is a visual judgement — you target a region by looking at it, not by computing pixel offsets. Aspect lock exists because most downstream uses (thumbnails, social, datasets) need a fixed ratio. | *Numeric fields only* — precise but you can't tell what you selected without exporting. *Drag + synced numeric fields* — better, but the extra surface isn't earning its cost in v1; the live pixel readout covers the "what did I actually select" need. |
| **Trim** | Dual-handle in/out range slider under the preview; dragging a handle seeks the preview to that time | The temporal counterpart to crop. Seek-on-drag is what makes it usable — otherwise you're setting boundaries blind. | Exporting the whole video and deleting unwanted images afterwards. |
| **Output folder** | User picks a folder via the system panel; **remembered across launches** with a security-scoped bookmark. One subfolder per video. | Keeps the app **fully sandboxed** and App Store–shippable. Remembering the folder means the choice is made once, not every run. | *Auto-create next to the source video* — zero clicks, but requires disabling the sandbox entirely, since a dropped file grants read access only, not write access to its parent folder. *Prompt per new location* — keeps the sandbox but adds a dialog every time you work from a new folder. |
| **Format** | JPG/PNG picker; JPEG quality slider (default 90%), hidden when PNG is selected. Images export at native resolution — or crop resolution when crop is on. | Covers photographic output (JPG) and lossless/transparency (PNG). Quality is the one knob people actually reach for. | Adding a resize/long-edge field — real need, but it's a separate concern from *extraction* and can be added later without disturbing anything. |
| **Batch** | Multiple videos queued and exported sequentially. **Crop and trim are per-video**; interval, format, quality, and output folder are global. | Clips in a batch routinely differ in resolution, aspect ratio, and length — a single shared crop rectangle would land in the wrong place and a shared trim range would be meaningless. Sampling and encoding settings, by contrast, are genuinely uniform intent. | *Global crop/trim stored as percentages* — fewer clicks when clips are identical, silently wrong when they aren't. *Disabling crop/trim in batch mode* — simplest, but you lose the targeting that motivated the feature. |
| **Cancel** | Cancel button during export; stops between frames, reports how many were written, keeps already-written files | Long videos at fine intervals produce thousands of frames. Being unable to stop is a trap; discarding partial work is worse. | — |
| **Completion** | Summary with **Reveal in Finder** and **Export another** | The images are the deliverable and they live in Finder. Ending the flow inside the app without a route to them is a dead end. | — |

The app is **sandboxed**. That constraint drove the output-folder decision above and is treated as
non-negotiable.

---

## Product rule: how many images?

Sampling uses a **half-open range**. Times are `start, start + interval, start + 2·interval, …`
for as long as `t < end`. The end boundary is never sampled.

```
count = ceil((end - start) / interval)
```

**Worked example, from the original brief:** a 10.0 second video at one image per 0.5 second
produces frames at `0.0, 0.5, 1.0, … 9.5` — **20 images**.

Sampling the closing boundary too would give 21, and the final frame of a video is frequently
black or a duplicate. 20 is both the intuitive answer and the useful one.

Two consequences that must hold everywhere in the app:

- The live estimate shown before export and the number of files actually written are computed by
  **the same code**. They can never disagree.
- With a trim range set, `start` and `end` are the trim boundaries, not the video's.
  3.0 s – 8.0 s at 0.5 s ⇒ 10 images, beginning at 3.0 s.

Frames are extracted at **exact** timestamps (zero tolerance). "One image per 0.5 second" is the
entire premise of the app; approximate timestamps would quietly violate it.

---

## Output contract

For each video, a subfolder is created inside the chosen output folder:

```
<output folder>/
  clip_frames/
    clip_0001.jpg
    clip_0002.jpg
    …
    clip_0020.jpg
```

- **Subfolder:** `<video basename>_frames`. If that name is taken, ` 2`, ` 3`, … is appended.
  A re-run never silently overwrites a previous export.
- **Files:** `<video basename>_<index>.<ext>`, index starting at `0001`, zero-padded to at least
  four digits and widened if the count needs more.
- **Order:** index order is timeline order. `_0001` is the earliest frame.
- **Extension:** `.jpg` or `.png`, matching the selected format.

---

## Non-goals

Explicitly out of scope for v1:

- Resizing or downscaling on export
- Contact sheets, GIFs, or any composite output
- Per-video interval, format, or quality overrides
- Video formats AVFoundation can't open natively. `.mkv`, `.avi` and `.webm` are rejected at the
  drop — note they *do* conform to `public.movie`, so acceptance is an explicit allowlist of
  `.mp4` / `.mov` / `.m4v` rather than a conformance check
- Drag-reordering the queue
- Editing, encoding, or writing video of any kind

---

## Success criteria — "v1 done"

1. Dropping a 10-second video and clicking Start with default settings produces exactly **20**
   images, at 0.0 s through 9.5 s, in the chosen folder.
2. The count shown before export always matches the number of files written.
3. A crop drawn on the preview produces images whose pixel dimensions match the on-screen
   readout, and whose content is the region that was drawn.
4. Crop lands correctly on **rotated (portrait) video** — the classic failure mode.
5. A trim range of 3 s – 8 s at 0.5 s produces 10 images beginning at 3.0 s.
6. Three videos with three different crops and trims export to three independent subfolders.
7. Cancelling mid-export stops promptly, keeps completed files, and reports the partial count.
8. Quitting and relaunching preserves the output folder — no re-prompt, and writing still
   succeeds under the sandbox.
9. PNG export produces valid PNGs and hides the quality slider.

Each criterion maps to a verification step in `planning.md`.
