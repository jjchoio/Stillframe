//
//  OutputFolderStore.swift
//  Stillframe
//

import AppKit
import Foundation

/// Remembers where exports go, across launches, from inside the sandbox.
///
/// A dropped video grants **read** access to that file only, so output can't be written beside
/// it. The user picks a folder once through `NSOpenPanel`, and a security-scoped bookmark keeps
/// that grant alive for future launches. Resolving the bookmark is not enough on its own — the
/// access has to be claimed with `startAccessingSecurityScopedResource()` and held.
@MainActor
@Observable
final class OutputFolderStore {
    private(set) var folder: URL?

    /// The URL we currently hold a claim on, so it can be released before taking another.
    @ObservationIgnored private var claimedURL: URL?
    @ObservationIgnored private let defaults: UserDefaults

    private static let bookmarkKey = "outputFolderBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    deinit {
        claimedURL?.stopAccessingSecurityScopedResource()
    }

    /// Presents the folder picker. Returns the chosen folder, or nil if cancelled.
    @discardableResult
    func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where Stillframe should save exported images."
        panel.directoryURL = folder

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        adopt(url)
        persist(url)
        return url
    }

    // MARK: - Persistence

    private func persist(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil)
            defaults.set(data, forKey: Self.bookmarkKey)
        } catch {
            // The folder still works this session; it just won't survive a relaunch.
            print("Stillframe: couldn't bookmark output folder — \(error.localizedDescription)")
        }
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale)

            adopt(url)

            // A stale bookmark still resolves, but won't next time — refresh it now rather
            // than silently losing the folder on some later launch.
            if isStale { persist(url) }
        } catch {
            // Folder moved, was deleted, or the grant was revoked. Drop it and let the user
            // pick again rather than failing at export time.
            defaults.removeObject(forKey: Self.bookmarkKey)
            print("Stillframe: output folder bookmark unusable — \(error.localizedDescription)")
        }
    }

    /// Takes the security-scoped claim on `url`, releasing any previous one.
    private func adopt(_ url: URL) {
        if let claimedURL, claimedURL != url {
            claimedURL.stopAccessingSecurityScopedResource()
            self.claimedURL = nil
        }

        if url.startAccessingSecurityScopedResource() {
            claimedURL = url
        }
        folder = url
    }

    /// Whether the folder still exists and accepts writes. Checked before starting an export so
    /// a moved folder surfaces as a message instead of a pile of failed frames.
    var isWritable: Bool {
        guard let folder else { return false }
        return FileManager.default.isWritableFile(atPath: folder.path)
    }
}
