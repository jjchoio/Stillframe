//
//  StillframeApp.swift
//  Stillframe
//

import SwiftUI

@main
struct StillframeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1100, height: 720)
        // .contentMinSize keeps the window from shrinking past ContentView's minimum,
        // so the sidebar/detail split never collapses into an unusable width.
        .windowResizability(.contentMinSize)
    }
}
