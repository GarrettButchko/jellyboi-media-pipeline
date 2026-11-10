import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BaseColors
import LoggingKit

enum AppTab: String, CaseIterable, Identifiable {
    case remux = "Remuxing"
    case jellyfin = "Direct to Jellyfin"
    case logs = "Activity Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .remux: return "slider.horizontal.3"
        case .jellyfin: return "server.rack"
        case .logs: return "terminal"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var manager = PipelineManager()
    @State private var selectedTab: AppTab = .remux
    @State private var hoveredTab: AppTab? = nil

    private var visibleTabs: [AppTab] {
        AppTab.allCases.filter { $0 != .jellyfin || manager.jellyfinDirectAvailable }
    }

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(visibleTabs) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(selectedTab == tab ? Color.white : Color.mainOpp)

                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(selectedTab == tab ? Color.white : Color.mainOpp)

                            Spacer()

                            if tab == .remux && !manager.queue.isEmpty {
                                Text("\(manager.queue.count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.mainOpp.opacity(0.18), in: Capsule())
                                    .foregroundStyle(Color.white)
                            } else if tab == .jellyfin && !manager.jellyfinQueue.isEmpty {
                                Text("\(manager.jellyfinQueue.count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.mainOpp.opacity(0.18), in: Capsule())
                                    .foregroundStyle(Color.white)
                            } else if tab == .settings {
                                let missing = max(0, manager.toolRegistry.allToolsStatus.count - manager.toolRegistry.allToolsStatus.filter { $0.isAvailable }.count)
                                if missing > 0 {
                                    Text("\(missing)")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.9), in: Capsule())
                                        .foregroundStyle(Color.white)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTab == tab ? Color.accent.opacity(0.7) : (hoveredTab == tab ? Color.accent.opacity(0.2) : Color.clear))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        if isHovered {
                            hoveredTab = tab
                        } else if hoveredTab == tab {
                            hoveredTab = nil
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            Group {
                switch selectedTab {
                case .remux:
                    QueueView(manager: manager)
                case .jellyfin:
                    JellyfinDirectView(manager: manager)
                case .logs:
                    LogView(manager: manager)
                case .settings:
                    SettingsView(manager: manager)
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(selectedTab.rawValue)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    #if DEBUG
                    Menu {
                        Section("Remux Queue") {
                            Button("Populate Remux Queue") {
                                ScreenshotDemoHelper.populateRemuxQueue(manager: manager)
                                selectedTab = .remux
                            }
                        }

                        Section("Prompt Sheets") {
                            Button("Show Disc Rip Title Sheet") {
                                ScreenshotDemoHelper.triggerDiscRipTitlePrompt(manager: manager)
                            }
                            Button("Show Title Disambiguation Sheet") {
                                ScreenshotDemoHelper.triggerTitleDisambiguation(manager: manager)
                            }
                            Button("Show Subtitle Selection Sheet") {
                                ScreenshotDemoHelper.triggerSubtitleSelection(manager: manager)
                            }
                        }

                        Section("Direct to Jellyfin") {
                            Button("Populate Jellyfin Upload Queue") {
                                ScreenshotDemoHelper.populateJellyfinQueue(manager: manager)
                                selectedTab = .jellyfin
                            }
                        }

                        Section("Activity Logs") {
                            Button("Populate Activity Logs") {
                                ScreenshotDemoHelper.populateLogs(manager: manager)
                                selectedTab = .logs
                            }
                        }

                        Divider()

                        Button("Reset Demo Data", role: .destructive) {
                            ScreenshotDemoHelper.resetAllMockData(manager: manager)
                        }
                    } label: {
                        Label("Demo", systemImage: "sparkles")
                    }
                    .help("Populate demo data for README screenshots")
                    #endif

                    if selectedTab == .remux {
                        Button {
                            chooseRemuxFiles()
                        } label: {
                            Label("Add Files", systemImage: "plus")
                        }
                        .help("Add MKV files to remux queue")

                        if manager.isProcessing {
                            Button {
                                manager.stopProcessing()
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .tint(.red)
                            .help("Stop processing")
                        } else {
                            Button {
                                manager.startProcessing()
                            } label: {
                                Label("Start", systemImage: "play.fill")
                            }
                            .tint(.green)
                            .disabled(manager.queue.isEmpty)
                            .help("Start processing remux queue")
                        }

                        if manager.queue.contains(where: { $0.status == .completed }) {
                            Button {
                                manager.clearCompleted()
                            } label: {
                                Label("Clear Finished", systemImage: "trash")
                            }
                            .help("Clear finished items")
                        }
                    } else if selectedTab == .jellyfin {
                        Button {
                            chooseJellyfinFiles()
                        } label: {
                            Label("Add Files", systemImage: "plus")
                        }
                        .help("Add media files to Jellyfin queue")

                        if manager.isJellyfinUploading {
                            Button {
                                manager.stopJellyfinUploads()
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .tint(.red)
                            .help("Stop upload")
                        } else {
                            Button {
                                manager.startJellyfinUploads()
                            } label: {
                                Label("Start Upload", systemImage: "arrow.up.circle.fill")
                            }
                            .tint(.green)
                            .disabled(manager.jellyfinQueue.isEmpty)
                            .help("Start streaming files to Jellyfin server")
                        }

                        if manager.jellyfinQueue.contains(where: { $0.status == .completed }) {
                            Button {
                                manager.clearCompletedJellyfin()
                            } label: {
                                Label("Clear Finished", systemImage: "trash")
                            }
                            .help("Clear finished uploads")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .task {
            await manager.refreshJellyfinDetection()
        }
        .onChange(of: manager.jellyfinDirectAvailable) { _, isAvailable in
            if !isAvailable && selectedTab == .jellyfin {
                selectedTab = .remux
            }
        }
        .sheet(item: $manager.activeTitlePrompt) { req in
            DiscRipTitleSheet(request: req, manager: manager)
        }
        .sheet(item: $manager.activeTitleDisambiguation) { req in
            TitleDisambiguationSheet(request: req, manager: manager)
        }
        .sheet(item: $manager.activeSubtitlePrompt) { req in
            SubtitleSelectionSheet(request: req, manager: manager)
        }
    }

    private func chooseRemuxFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.movie]
        if panel.runModal() == .OK {
            manager.addFiles(urls: panel.urls)
        }
    }

    private func chooseJellyfinFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.movie]
        if panel.runModal() == .OK {
            manager.addJellyfinFiles(urls: panel.urls)
        }
    }
}

#Preview {
    ContentView()
}
