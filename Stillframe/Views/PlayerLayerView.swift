//
//  PlayerLayerView.swift
//  Stillframe
//

import AVFoundation
import AVKit
import SwiftUI

/// A bare `AVPlayerLayer` in a SwiftUI wrapper.
///
/// Deliberately not SwiftUI's `VideoPlayer`: its built-in transport controls sit on top of the
/// video and would swallow the crop drag gestures added in milestone 5. This view draws the
/// frames and nothing else — transport lives in `VideoPreviewView`.
///
/// The view is sized by its caller to exactly the video's aspect rect, so `.resizeAspect` has
/// no letterboxing left to do and the layer fills these bounds precisely.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerBackingView {
        let view = PlayerBackingView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerBackingView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
    }
}

/// An `NSView` whose backing layer *is* the player layer, so it tracks bounds automatically.
final class PlayerBackingView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        playerLayer.videoGravity = .resizeAspect
        // Assigning `layer` before setting `wantsLayer` makes this a layer-hosting view;
        // AppKit then keeps the layer's frame in sync with bounds for us.
        layer = playerLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
