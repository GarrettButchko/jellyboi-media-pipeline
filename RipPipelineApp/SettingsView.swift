import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var manager: PipelineManager

    @State private var omdbKey: String = ""
    @State private var openSubtitlesKey: String = ""
    @State private var openSubtitlesUsername: String = ""
    @State private var openSubtitlesPassword: String = ""

    @State private var watchPath: String = ""
    @State private var libraryPath: String = ""
    @State private var tvLibraryPath: String = ""

    var body: some View {
        Form {
            Section(header: Text("API Credentials").font(.headline)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OMDb API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        SecureField("OMDb API Key", text: $omdbKey)
                            .textFieldStyle(.roundedBorder)
                        Link("Get Key", destination: URL(string: "https://www.omdbapi.com/apikey.aspx")!)
                            .buttonStyle(.link)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenSubtitles.com API Key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        SecureField("OpenSubtitles API Key", text: $openSubtitlesKey)
                            .textFieldStyle(.roundedBorder)
                        Link("Get Key", destination: URL(string: "https://www.opensubtitles.com/en/consumers")!)
                            .buttonStyle(.link)
                    }
                }

                HStack {
                    TextField("Username (optional)", text: $openSubtitlesUsername)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password (optional)", text: $openSubtitlesPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section(header: Text("Storage Directories").font(.headline)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watch / MakeMKV Input Directory")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Watch Directory", text: $watchPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") {
                            chooseFolder { url in
                                watchPath = url.path
                                saveSettings()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Movie Library Output")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Movies Library", text: $libraryPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") {
                            chooseFolder { url in
                                libraryPath = url.path
                                saveSettings()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("TV Show Library Output")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("TV Shows Library", text: $tvLibraryPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") {
                            chooseFolder { url in
                                tvLibraryPath = url.path
                                saveSettings()
                            }
                        }
                    }
                }
            }

            Section(header: Text("Diagnostics & Logs").font(.headline)) {
                HStack {
                    Text("Log Directory:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reveal Logs in Finder") {
                        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
                            .appendingPathComponent("Logs/RipPipeline")
                        if let logs = logs {
                            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([logs])
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadSettings()
        }
        .onChange(of: omdbKey) { _, _ in saveSettings() }
        .onChange(of: openSubtitlesKey) { _, _ in saveSettings() }
        .onChange(of: openSubtitlesUsername) { _, _ in saveSettings() }
        .onChange(of: openSubtitlesPassword) { _, _ in saveSettings() }
    }

    private func loadSettings() {
        omdbKey = manager.config.omdbKey
        openSubtitlesKey = manager.config.openSubtitlesKey
        openSubtitlesUsername = manager.config.openSubtitlesUsername
        openSubtitlesPassword = manager.config.openSubtitlesPassword
        watchPath = manager.config.watchDir.path
        libraryPath = manager.config.libraryDir.path
        tvLibraryPath = manager.config.tvLibraryDir.path
    }

    private func saveSettings() {
        manager.config.omdbKey = omdbKey
        manager.config.openSubtitlesKey = openSubtitlesKey
        manager.config.openSubtitlesUsername = openSubtitlesUsername
        manager.config.openSubtitlesPassword = openSubtitlesPassword
        if !watchPath.isEmpty {
            manager.config.watchDir = URL(fileURLWithPath: (watchPath as NSString).expandingTildeInPath)
        }
        if !libraryPath.isEmpty {
            manager.config.libraryDir = URL(fileURLWithPath: (libraryPath as NSString).expandingTildeInPath)
        }
        if !tvLibraryPath.isEmpty {
            manager.config.tvLibraryDir = URL(fileURLWithPath: (tvLibraryPath as NSString).expandingTildeInPath)
        }
        manager.config.saveToUserDefaults()
    }

    private func chooseFolder(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}
