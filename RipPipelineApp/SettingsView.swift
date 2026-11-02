import SwiftUI
import AppKit
import BaseColors
import LoggingKit

struct SettingsView: View {
    @Bindable var manager: PipelineManager
    @Environment(\.openURL) private var openURL

    // System-persisted storage for all configuration fields (ensures refresh or reload never deletes user inputs)
    @AppStorage("omdbKey") private var omdbKey: String = ""
    @AppStorage("openSubtitlesKey") private var openSubtitlesKey: String = ""
    @AppStorage("openSubtitlesUsername") private var openSubtitlesUsername: String = ""
    @AppStorage("openSubtitlesPassword") private var openSubtitlesPassword: String = ""

    @AppStorage("watchDir") private var watchPath: String = ""
    @AppStorage("libraryDir") private var libraryPath: String = ""
    @AppStorage("tvLibraryDir") private var tvLibraryPath: String = ""

    // Jellyfin Direct Upload & Plugin State
    @AppStorage("jellyfinServerURL") private var jellyfinServerURL: String = ""
    @AppStorage("jellyfinApiKey") private var jellyfinApiKey: String = ""
    @AppStorage("jellyfinUploadEnabled") private var jellyfinUploadEnabled: Bool = false
    @AppStorage("jellyfinMovieLibraryId") private var jellyfinMovieLibraryId: String = ""
    @AppStorage("jellyfinTvLibraryId") private var jellyfinTvLibraryId: String = ""
    @AppStorage("jellyfinMovieServerPath") private var jellyfinMovieServerPath: String = ""
    @AppStorage("jellyfinTvServerPath") private var jellyfinTvServerPath: String = ""
    @AppStorage("isCustomMovieServerPath") private var isCustomMovieServerPath: Bool = false
    @AppStorage("isCustomTvServerPath") private var isCustomTvServerPath: Bool = false

    @State private var isFetchingLibraries: Bool = false
    @State private var jellyfinStatus: JellyfinDetectionState = .idle
    @State private var detectedLibraries: [JellyfinLibrary] = []

    var body: some View {
        ZStack {
            Color.bg
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    jellyfinSection
                    jellyfinStatusRow
                    omdbSection
                    openSubtitlesSection
                    storageDirectoriesSection
                    diagnosticsSection
                }
                .padding(16)
            }
        }
        .buttonStyle(SettingsButtonStyle())
        .onAppear {
            loadSettings()

            // Reuse the cached/shared detection result so simply opening Settings
            // does not re-probe the server every time.
            let trimmedURL = jellyfinServerURL.trimmingCharacters(in: .whitespaces)
            if manager.jellyfinDetectedServerURL == trimmedURL, manager.jellyfinDetectionState != .idle {
                jellyfinStatus = manager.jellyfinDetectionState
                if case .detected = jellyfinStatus, detectedLibraries.isEmpty {
                    fetchLibrariesNow()
                }
            } else {
                jellyfinStatus = .idle
                if !trimmedURL.isEmpty {
                    testJellyfinConnection()
                }
            }
        }
        .onChange(of: omdbKey) { _, _ in syncToConfig() }
        .onChange(of: openSubtitlesKey) { _, _ in syncToConfig() }
        .onChange(of: openSubtitlesUsername) { _, _ in syncToConfig() }
        .onChange(of: openSubtitlesPassword) { _, _ in syncToConfig() }
        .onChange(of: watchPath) { _, _ in syncToConfig() }
        .onChange(of: libraryPath) { _, _ in syncToConfig() }
        .onChange(of: tvLibraryPath) { _, _ in syncToConfig() }
        .onChange(of: jellyfinServerURL) { _, _ in
            syncToConfig()
            jellyfinStatus = .idle
            detectedLibraries = []
        }
        .onChange(of: jellyfinApiKey) { _, _ in syncToConfig() }
        .onChange(of: jellyfinUploadEnabled) { _, _ in syncToConfig() }
        .onChange(of: jellyfinMovieLibraryId) { _, _ in syncToConfig() }
        .onChange(of: jellyfinTvLibraryId) { _, _ in syncToConfig() }
        .onChange(of: jellyfinMovieServerPath) { _, _ in syncToConfig() }
        .onChange(of: jellyfinTvServerPath) { _, _ in syncToConfig() }
        .onChange(of: isCustomMovieServerPath) { _, _ in syncToConfig() }
        .onChange(of: isCustomTvServerPath) { _, _ in syncToConfig() }
    }

    // MARK: - Section 1: Jellyfin Server & Plugin Integration

    @ViewBuilder
    private var jellyfinSection: some View {
        settingsSection("Jellyfin Server") {
            HStack(alignment: .center) {
                Text("Server Address")
                Spacer()
                HStack(spacing: 8) {
                    TextField("", text: $jellyfinServerURL, prompt: Text("e.g. 192.168.1.100:8096"))
                        .textFieldStyle(SettingsTextFieldStyle())
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 220, maxWidth: 300)
                        .opacity(jellyfinServerURL.isEmpty ? 0.6 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: jellyfinServerURL.isEmpty)

                    Button("Test & Detect") {
                        testJellyfinConnection(force: true)
                    }
                    .buttonStyle(SettingsButtonStyle())
                    .foregroundStyle(Color.mainOpp)
                }
            }

            HStack(alignment: .center) {
                Text("API Key / Token")
                Spacer()
                HStack(spacing: 8) {
                    RevealingSecureField(placeholder: "Jellyfin Admin Token", text: $jellyfinApiKey)
                    if let normURL = JellyfinClient.normalizeURL(jellyfinServerURL) {
                        Button("Open Dashboard") {
                            if let dashboardURL = URL(string: normURL.absoluteString + "/web/#/dashboard") {
                                openURL(dashboardURL)
                            }
                        }
                        .buttonStyle(SettingsButtonStyle())
                        .foregroundStyle(Color.mainOpp)
                    }
                }
            }
        }
    }

    // MARK: - Section 2: OMDb

    @ViewBuilder
    private var omdbSection: some View {
        settingsSection("OMDb") {
            HStack(alignment: .center) {
                Text("API Key")
                Spacer()
                HStack(spacing: 8) {
                    RevealingSecureField(placeholder: "OMDb API Key", text: $omdbKey)
                    Button("Get Key") {
                        openURL(URL(string: "https://www.omdbapi.com/apikey.aspx")!)
                    }
                    .buttonStyle(SettingsButtonStyle())
                    .foregroundStyle(Color.mainOpp)
                }
            }
        }
    }

    // MARK: - Section 3: OpenSubtitles

    @ViewBuilder
    private var openSubtitlesSection: some View {
        settingsSection("OpenSubtitles") {
            HStack(alignment: .center) {
                Text("API Key")
                Spacer()
                HStack(spacing: 8) {
                    RevealingSecureField(placeholder: "OpenSubtitles API Key", text: $openSubtitlesKey)
                    Button("Get Key") {
                        openURL(URL(string: "https://www.opensubtitles.com/en/consumers")!)
                    }
                    .buttonStyle(SettingsButtonStyle())
                    .foregroundStyle(Color.mainOpp)
                }
            }

            HStack(alignment: .center) {
                Text("Username")
                Spacer()
                TextField("", text: $openSubtitlesUsername, prompt: Text("Optional"))
                    .textFieldStyle(SettingsTextFieldStyle())
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 220, maxWidth: 300)
                    .opacity(openSubtitlesUsername.isEmpty ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: openSubtitlesUsername.isEmpty)
            }

            HStack(alignment: .center) {
                Text("Password")
                Spacer()
                RevealingSecureField(placeholder: "Optional", text: $openSubtitlesPassword)
            }
        }
    }

    // MARK: - Section 4: Storage Directories

    @ViewBuilder
    private var storageDirectoriesSection: some View {
        settingsSection("Local Storage Directories") {
            directoryRow(
                title: "Watch Folder",
                path: $watchPath
            ) {
                chooseFolder { url in
                    watchPath = url.path
                    syncToConfig()
                }
            }

            directoryRow(
                title: "Movies Output",
                path: $libraryPath
            ) {
                chooseFolder { url in
                    libraryPath = url.path
                    syncToConfig()
                }
            }

            directoryRow(
                title: "TV Shows Output",
                path: $tvLibraryPath
            ) {
                chooseFolder { url in
                    tvLibraryPath = url.path
                    syncToConfig()
                }
            }
        }
    }

    // MARK: - Section 5: Diagnostics

    @ViewBuilder
    private var diagnosticsSection: some View {
        settingsSection("Diagnostics") {
            LabeledContent("CLI Tools") {
                Text("\(manager.toolRegistry.allToolsStatus.filter { $0.isAvailable }.count) of \(manager.toolRegistry.allToolsStatus.count) available")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Remux Queue Items") {
                Text("\(manager.queue.count)")
                    .foregroundStyle(.secondary)
            }

            if manager.jellyfinDirectAvailable {
                LabeledContent("Direct to Jellyfin Queue") {
                    Text("\(manager.jellyfinQueue.count)")
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Logging") {
                Text("\(manager.logs.count) entries recorded")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Jellyfin Status & Destination Controls

    @ViewBuilder
    private var jellyfinStatusRow: some View {
        settingsSection("Direct Download") {
            switch jellyfinStatus {
            case .idle:
                Label("Enter your Jellyfin server address and API key, then click 'Test & Detect' to verify plugin connection.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
            case .checking:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Testing connection & detecting FileToRemux plugin…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                
            case .detected(let version, let serverName):
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("FileToRemux Plugin Active (v\(version))\(serverName.map { " on '\($0)'" } ?? "")")
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        fetchLibrariesNow()
                    } label: {
                        HStack(spacing: 4) {
                            if isFetchingLibraries {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(SettingsButtonStyle())
                    .foregroundStyle(Color.mainOpp)
                    .controlSize(.small)
                    .disabled(isFetchingLibraries)
                }
                
                HStack(alignment: .center) {
                    Text("Server Path - Movies")
                    Spacer()
                    ServerPathPicker(
                        options: movieServerPathOptions,
                        selectedTag: isCustomMovieServerPath ? "__custom__" : jellyfinMovieLibraryId,
                        onSelect: { onMovieSelectionChanged(newSelection: $0) }
                    )
                }
                
                if isCustomMovieServerPath {
                    HStack(alignment: .center) {
                        Text("Movies Server Path")
                        Spacer()
                        TextField("", text: $jellyfinMovieServerPath, prompt: Text("e.g. /mnt/media/movies"))
                            .textFieldStyle(SettingsTextFieldStyle())
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 220, maxWidth: 300)
                    }
                }
                
                HStack(alignment: .center) {
                    Text("Server Path - TV Shows")
                    Spacer()
                    ServerPathPicker(
                        options: tvServerPathOptions,
                        selectedTag: isCustomTvServerPath ? "__custom__" : jellyfinTvLibraryId,
                        onSelect: { onTvSelectionChanged(newSelection: $0) }
                    )
                }
                
                if isCustomTvServerPath {
                    HStack(alignment: .center) {
                        Text("TV Shows Server Path")
                        Spacer()
                        TextField("", text: $jellyfinTvServerPath, prompt: Text("e.g. /mnt/media/tv"))
                            .textFieldStyle(SettingsTextFieldStyle())
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 220, maxWidth: 300)
                    }
                }
                
                
                
            case .pluginMissing(let serverName):
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Jellyfin Server Found\(serverName != nil ? " ('\(serverName!)')" : ""), but FileToRemux Plugin Is Missing.")
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                            Text("Install the FileToRemux.dll plugin inside your Jellyfin plugins directory and restart the server to enable direct streaming uploads.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                
            case .unauthorized:
                Label("Connection refused: The API Key / Token is invalid or does not have sufficient admin privileges.", systemImage: "lock.slash.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                
            case .unreachable(let message):
                Label("Cannot reach Jellyfin: \(message)", systemImage: "wifi.slash")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }
        
        private func onMovieSelectionChanged(newSelection: String) {
            if newSelection == "__custom__" {
                isCustomMovieServerPath = true
            } else {
                isCustomMovieServerPath = false
                if newSelection.contains("::") {
                    let parts = newSelection.components(separatedBy: "::")
                    jellyfinMovieLibraryId = parts[0]
                    jellyfinMovieServerPath = parts[1]
                } else if !newSelection.isEmpty {
                    jellyfinMovieLibraryId = newSelection
                    if let lib = detectedLibraries.first(where: { $0.id == newSelection }) {
                        jellyfinMovieServerPath = lib.effectivePath ?? ""
                    }
                } else {
                    jellyfinMovieLibraryId = ""
                    jellyfinMovieServerPath = ""
                }
            }
            syncToConfig()
        }
        
        private func onTvSelectionChanged(newSelection: String) {
            if newSelection == "__custom__" {
                isCustomTvServerPath = true
            } else {
                isCustomTvServerPath = false
                if newSelection.contains("::") {
                    let parts = newSelection.components(separatedBy: "::")
                    jellyfinTvLibraryId = parts[0]
                    jellyfinTvServerPath = parts[1]
                } else if !newSelection.isEmpty {
                    jellyfinTvLibraryId = newSelection
                    if let lib = detectedLibraries.first(where: { $0.id == newSelection }) {
                        jellyfinTvServerPath = lib.effectivePath ?? ""
                    }
                } else {
                    jellyfinTvLibraryId = ""
                    jellyfinTvServerPath = ""
                }
            }
            syncToConfig()
        }
        
        private func testJellyfinConnection(force: Bool = false) {
            guard !jellyfinServerURL.trimmingCharacters(in: .whitespaces).isEmpty else {
                jellyfinStatus = .idle
                Task { await manager.refreshJellyfinDetection(force: force) }
                return
            }
            
            jellyfinStatus = .checking
            Task {
                await manager.refreshJellyfinDetection(apiKey: jellyfinApiKey, force: force)
                await MainActor.run {
                    self.jellyfinStatus = manager.jellyfinDetectionState
                    if case .detected = self.jellyfinStatus {
                        fetchLibrariesNow()
                    }
                }
            }
        }
        
        private func fetchLibrariesNow() {
            guard !jellyfinServerURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            isFetchingLibraries = true
            Task {
                let client = JellyfinClient()
                do {
                    let libs = try await client.fetchLibraries(serverURL: jellyfinServerURL, apiKey: jellyfinApiKey)
                    await MainActor.run {
                        self.detectedLibraries = libs
                        self.isFetchingLibraries = false
                    }
                } catch {
                    await MainActor.run {
                        self.isFetchingLibraries = false
                    }
                }
            }
        }
        
        // MARK: - Server Path Picker Options

        private var movieServerPathOptions: [ServerPathOption] {
            var options: [ServerPathOption] = [
                ServerPathOption(tag: "", title: "User's Movies Folder")
            ]
            if !detectedLibraries.isEmpty {
                for lib in detectedLibraries {
                    if lib.locations.count > 1 {
                        for loc in lib.locations {
                            options.append(ServerPathOption(tag: "\(lib.id)::\(loc)", title: "\(loc)"))
                        }
                    } else if let p = lib.effectivePath, !p.isEmpty {
                        options.append(ServerPathOption(tag: lib.id, title: p))
                    }
                }
            }
            options.append(ServerPathOption(tag: "__custom__", title: "Custom…"))
            return options
        }

        private var tvServerPathOptions: [ServerPathOption] {
            var options: [ServerPathOption] = [
                ServerPathOption(tag: "", title: "User's TV Shows Folder")
            ]
            if !detectedLibraries.isEmpty {
                for lib in detectedLibraries {
                    if lib.locations.count > 1 {
                        for loc in lib.locations {
                            options.append(ServerPathOption(tag: "\(lib.id)::\(loc)", title: "\(loc)"))
                        }
                    } else if let p = lib.effectivePath, !p.isEmpty {
                        options.append(ServerPathOption(tag: lib.id, title: p))
                    }
                }
            }
            options.append(ServerPathOption(tag: "__custom__", title: "Custom…"))
            return options
        }

        // MARK: - Subviews & Helpers
        
        @ViewBuilder
        private func settingsSection<Content: View>(
            _ title: String,
            @ViewBuilder content: () -> Content
        ) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.55))
                    .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.mainOpp)
                .jellyCard(cornerRadius: 12)
            }
        }
        
        @ViewBuilder
        private func directoryRow(title: String, path: Binding<String>, onBrowse: @escaping () -> Void) -> some View {
            LabeledContent(title) {
                HStack(spacing: 8) {
                    Spacer(minLength: 12)
                    TextField("", text: path, prompt: Text("Path not configured"))
                        .textFieldStyle(SettingsTextFieldStyle())
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 220, maxWidth: 300)
                        .truncationMode(.middle)
                        .opacity(path.wrappedValue.isEmpty ? 0.6 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: path.wrappedValue.isEmpty)
                    Button("Browse…", action: onBrowse)
                        .buttonStyle(SettingsButtonStyle())
                        .foregroundStyle(Color.mainOpp)
                }
            }
        }
        
        private func loadSettings() {
            let config = manager.config
            if omdbKey.isEmpty && !config.omdbKey.isEmpty { omdbKey = config.omdbKey }
            if openSubtitlesKey.isEmpty && !config.openSubtitlesKey.isEmpty { openSubtitlesKey = config.openSubtitlesKey }
            if openSubtitlesUsername.isEmpty && !config.openSubtitlesUsername.isEmpty { openSubtitlesUsername = config.openSubtitlesUsername }
            if openSubtitlesPassword.isEmpty && !config.openSubtitlesPassword.isEmpty { openSubtitlesPassword = config.openSubtitlesPassword }
            
            if watchPath.isEmpty && !config.watchDir.path.isEmpty { watchPath = config.watchDir.path }
            if libraryPath.isEmpty && !config.libraryDir.path.isEmpty { libraryPath = config.libraryDir.path }
            if tvLibraryPath.isEmpty && !config.tvLibraryDir.path.isEmpty { tvLibraryPath = config.tvLibraryDir.path }
            
            if jellyfinServerURL.isEmpty && !config.jellyfinServerURL.isEmpty { jellyfinServerURL = config.jellyfinServerURL }
            if jellyfinApiKey.isEmpty && !config.jellyfinApiKey.isEmpty { jellyfinApiKey = config.jellyfinApiKey }
            if !jellyfinUploadEnabled && config.jellyfinUploadEnabled { jellyfinUploadEnabled = config.jellyfinUploadEnabled }
            if jellyfinMovieLibraryId.isEmpty && !config.jellyfinMovieLibraryId.isEmpty { jellyfinMovieLibraryId = config.jellyfinMovieLibraryId }
            if jellyfinTvLibraryId.isEmpty && !config.jellyfinTvLibraryId.isEmpty { jellyfinTvLibraryId = config.jellyfinTvLibraryId }
            if jellyfinMovieServerPath.isEmpty && !config.jellyfinMovieServerPath.isEmpty { jellyfinMovieServerPath = config.jellyfinMovieServerPath }
            if jellyfinTvServerPath.isEmpty && !config.jellyfinTvServerPath.isEmpty { jellyfinTvServerPath = config.jellyfinTvServerPath }
            
            if !jellyfinMovieServerPath.isEmpty && jellyfinMovieLibraryId.isEmpty {
                isCustomMovieServerPath = true
            }
            if !jellyfinTvServerPath.isEmpty && jellyfinTvLibraryId.isEmpty {
                isCustomTvServerPath = true
            }
            
            syncToConfig()
        }
        
        private func syncToConfig() {
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
            
            manager.config.jellyfinServerURL = jellyfinServerURL
            manager.config.jellyfinApiKey = jellyfinApiKey
            manager.config.jellyfinUploadEnabled = jellyfinUploadEnabled
            manager.config.jellyfinMovieLibraryId = jellyfinMovieLibraryId
            manager.config.jellyfinTvLibraryId = jellyfinTvLibraryId
            manager.config.jellyfinMovieServerPath = jellyfinMovieServerPath
            manager.config.jellyfinTvServerPath = jellyfinTvServerPath
            
            manager.config.saveToUserDefaults()
            UserDefaults.standard.synchronize()
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

// MARK: - Server Path Picker

private struct ServerPathOption: Identifiable {
    let tag: String
    let title: String

    var id: String { tag }
}

private struct ServerPathPicker: View {
    let options: [ServerPathOption]
    let selectedTag: String
    let onSelect: (String) -> Void

    @State private var isOpen: Bool = false

    private var selectedTitle: String {
        options.first { $0.tag == selectedTag }?.title ?? "User's Movies Folder"
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack {
                Text(selectedTitle)
                Image(systemName: "chevron.down")
            }
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(Color.mainOpp)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.subTwo))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options) { option in
                    ServerPathOptionRow(
                        tag: option.tag,
                        title: option.title,
                        isSelected: option.tag == selectedTag
                    ) {
                        onSelect(option.tag)
                        isOpen = false
                    }
                }
            }
            .padding(4)
            .frame(minWidth: 180)
            .background(Color.sub.opacity(0.5))
        }
    }
}

private struct ServerPathOptionRow: View {
    let tag: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.mainOpp : Color.mainOpp.opacity(0.75))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.mainOpp)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isHovered ? Color.mainOpp.opacity(0.1) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Revealing Secure Field

private struct RevealingSecureField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isRevealed: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if isRevealed {
                TextField("", text: $text, prompt: Text(placeholder))
                    .textFieldStyle(SettingsTextFieldStyle())
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 220, maxWidth: 300)
                    .opacity(text.isEmpty ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
            } else {
                SecureField("", text: $text, prompt: Text(placeholder))
                    .textFieldStyle(SettingsTextFieldStyle())
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 220, maxWidth: 300)
                    .opacity(text.isEmpty ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
            }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(SettingsButtonStyle())
            .foregroundStyle(Color.mainOpp)
            .help(isRevealed ? "Hide" : "Show")
        }
    }
}

// MARK: - Settings Text Field Style

private struct SettingsTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .foregroundStyle(Color.mainOpp)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.subTwo)
            )
    }
}

// MARK: - Settings Button Style

private struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.mainOpp)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.subTwo)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1.0)
    }
}

#Preview {
    SettingsView(manager: PipelineManager())
        .frame(width: 600, height: 700)
}

