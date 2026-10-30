import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable, Identifiable {
    case queue = "Queue"
    case logs = "Activity Logs"
    case tools = "Diagnostics"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .queue: return "list.bullet.rectangle"
        case .logs: return "terminal"
        case .tools: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var manager = PipelineManager()
    @State private var selectedTab: AppTab = .queue

    var body: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label {
                        HStack {
                            Text(tab.rawValue)
                            Spacer()
                            if tab == .queue && !manager.queue.isEmpty {
                                Text("\(manager.queue.count)")
                                    .font(.caption2)
                                    .bold()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                    } icon: {
                        Image(systemName: tab.icon)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selectedTab {
                case .queue:
                    QueueView(manager: manager)
                case .logs:
                    LogView(manager: manager)
                case .tools:
                    ToolsView(manager: manager)
                case .settings:
                    SettingsView(manager: manager)
                }
            }
            .navigationTitle(selectedTab.rawValue)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if selectedTab == .queue {
                        Button {
                            chooseFiles()
                        } label: {
                            Label("Add Files", systemImage: "plus")
                        }

                        Button {
                            chooseFolder()
                        } label: {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                        }

                        if manager.isProcessing {
                            Button {
                                manager.stopProcessing()
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .tint(.red)
                        } else {
                            Button {
                                manager.startProcessing()
                            } label: {
                                Label("Start", systemImage: "play.fill")
                            }
                            .tint(.green)
                            .disabled(manager.queue.isEmpty)
                        }

                        Button {
                            manager.clearCompleted()
                        } label: {
                            Label("Clear Finished", systemImage: "trash")
                        }
                        .disabled(!manager.queue.contains(where: { $0.status == .completed }))
                    }
                }
            }
        }
        .frame(minWidth: 750, minHeight: 480)
        .sheet(item: $manager.activeTitleRequest) { request in
            TitlePromptSheet(request: request, manager: manager)
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.movie]
        if panel.runModal() == .OK {
            manager.addFiles(urls: panel.urls)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            manager.addDirectory(url: url)
        }
    }
}

#Preview {
    ContentView()
}
