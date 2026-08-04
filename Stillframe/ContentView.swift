//
//  ContentView.swift
//  Stillframe
//

import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()
    // One player for the whole app, owned above the detail pane so switching selection swaps
    // its item rather than spinning up a second player that keeps playing audio.
    @State private var player = PlayerController()
    @State private var isTargeted = false
    @State private var isShowingImporter = false

    var body: some View {
        Group {
            if model.items.isEmpty {
                DropZoneView(isTargeted: isTargeted) { isShowingImporter = true }
                    // Removing the last video must also silence it.
                    .onAppear { player.unload() }
            } else {
                NavigationSplitView {
                    QueueSidebarView(model: model) { isShowingImporter = true }
                        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                } detail: {
                    VStack(spacing: 0) {
                        if let item = model.selectedItem {
                            VideoDetailView(
                                item: item,
                                player: player,
                                minimumTrimSpan: model.settings.interval ?? 0.5)
                        } else {
                            ContentUnavailableView(
                                "No Video Selected",
                                systemImage: "sidebar.left",
                                description: Text("Choose a video from the queue."))
                                .onAppear { player.unload() }
                        }

                        SettingsBarView(model: model)
                    }
                }
                // A new selection shouldn't keep showing the previous export's result.
                .onChange(of: model.selection) { model.clearExportStatus() }
                // A thin accent border is enough feedback once the queue is populated —
                // the drop zone itself is no longer on screen to light up.
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(2)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isTargeted)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls: urls)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: AppModel.importerTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.add(urls: urls)
            }
        }
    }
}

#Preview {
    ContentView()
}
