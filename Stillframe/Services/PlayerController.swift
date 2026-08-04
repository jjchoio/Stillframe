//
//  PlayerController.swift
//  Stillframe
//

import AVFoundation
import Foundation

/// Drives preview playback.
///
/// Exactly one `AVPlayer` exists for the whole app and its item is swapped when the selection
/// changes. That is deliberate: two players would each hold their own audio, so switching rows
/// mid-playback could leave the previous clip audible.
@MainActor
@Observable
final class PlayerController {
    let player = AVPlayer()

    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var loadedItemID: VideoItem.ID?

    /// Preview audio is a scrubbing aid, not content — people leave it off and expect it to
    /// stay off, so the choice outlives the launch.
    private(set) var isMuted: Bool {
        didSet {
            player.isMuted = isMuted
            UserDefaults.standard.set(isMuted, forKey: Self.mutedKey)
        }
    }

    private static let mutedKey = "previewMuted"

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.mutedKey)
        player.isMuted = isMuted

        // 1/30 s keeps the readout smooth without flooding the main actor.
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                self.isPlaying = self.player.rate != 0
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    // MARK: - Loading

    /// Points the player at `item`, replacing whatever was playing.
    func load(_ item: VideoItem) {
        guard loadedItemID != item.id else { return }

        // Stop before swapping so the outgoing clip can't be heard over the incoming one.
        player.pause()
        isPlaying = false

        player.replaceCurrentItem(with: AVPlayerItem(url: item.url))
        loadedItemID = item.id
        currentTime = 0
        duration = item.metadata?.seconds ?? 0
        player.seek(to: .zero)
    }

    /// Called when metadata arrives after the item was already loaded.
    func updateDuration(_ seconds: Double) {
        duration = seconds
    }

    func unload() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        loadedItemID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    // MARK: - Transport

    func togglePlayPause() {
        if player.rate != 0 {
            pause()
        } else {
            // Restart from the top if we're parked at the end, so the button always does
            // something visible.
            if duration > 0, currentTime >= duration - 0.05 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), duration > 0 ? duration : seconds)
        currentTime = clamped
        // Scrubbing wants responsiveness, not frame accuracy — the exporter is the component
        // that must be exact.
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

// MARK: - Formatting

extension Double {
    /// `12.4` → `"0:12.4"`, for transport readouts.
    var playbackTimeText: String {
        guard isFinite, self >= 0 else { return "0:00.0" }
        let minutes = Int(self) / 60
        let seconds = self - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }
}
