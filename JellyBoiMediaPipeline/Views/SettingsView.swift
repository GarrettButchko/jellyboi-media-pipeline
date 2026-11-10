import SwiftUI
import AppKit
import BaseColors
import LoggingKit

struct SettingsView: View {
    @Bindable var manager: PipelineManager
    @Environment(\.openURL) private var openURL

    // System-persisted storage for configuration fields
    @KeychainStorage("omdbKey") private var omdbKey: String = ""
    @KeychainStorage("openSubtitlesKey") private var openSubtitlesKey: String = ""
    @AppStorage("openSubtitlesUsername") private var openSubtitlesUsername: String = ""
    @KeychainStorage("openSubtitlesPassword") private var openSubtitlesPassword: String = ""

    @AppStorage("watchDir") private var watchPath: String = ""
    @AppStorage("libraryDir") private var libraryPath: String = ""
    @AppStorage("tvLibraryDir") private var tvLibraryPath: String = ""

    // Subtitle retention & formats
    @AppStorage("subtitleRetentionMode") private var subtitleRetentionMode: String = "eng"
    @AppStorage("customSubtitleLanguages") private var customSubtitleLanguages: String = "eng"
    @AppStorage("keepSubRip") private var keepSubRip: Bool = true
    @AppStorage("keepAssSsa") private var keepAssSsa: Bool = true
    @AppStorage("keepBitmapSubs") private var keepBitmapSubs: Bool = false
    @AppStorage("preferEmbeddedSubs") private var preferEmbeddedSubs: Bool = true
    @AppStorage("normalizeEmbeddedAllCaps") private var normalizeEmbeddedAllCaps: Bool = true
    @AppStorage("clearDefaultSubtitleFlags") private var clearDefaultSubtitleFlags: Bool = true

    // OpenSubtitles quality restrictions
    @AppStorage("excludeHDTV") private var excludeHDTV: Bool = true
    @AppStorage("excludeHearingImpaired") private var excludeHearingImpaired: Bool = true
    @AppStorage("excludeCommentary") private var excludeCommentary: Bool = true
    @AppStorage("preferExtendedCuts") private var preferExtendedCuts: Bool = true
    @AppStorage("matchVideoFPS") private var matchVideoFPS: Bool = true
    @AppStorage("enforceDurationCheck") private var enforceDurationCheck: Bool = true
    @AppStorage("enforceContentCheck") private var enforceContentCheck: Bool = true
    @AppStorage("enforceStructuralAlignmentCheck") private var enforceStructuralAlignmentCheck: Bool = true

    // Subtitle processing
    @AppStorage("stripSubtitleAds") private var stripSubtitleAds: Bool = true
    @AppStorage("stripSubtitleFormatting") private var stripSubtitleFormatting: Bool = true
    @AppStorage("normalizeSubtitleCase") private var normalizeSubtitleCase: Bool = true
    @AppStorage("syncSubtitlesAudio") private var syncSubtitlesAudio: Bool = true

    // Interactive disambiguation
    @AppStorage("promptForSubtitleFallback") private var promptForSubtitleFallback: Bool = true
    @AppStorage("promptForAmbiguousTitles") private var promptForAmbiguousTitles: Bool = true

    // Jellyfin Direct Upload & Plugin State
    @AppStorage("jellyfinServerURL") private var jellyfinServerURL: String = ""
    @KeychainStorage("jellyfinApiKey") private var jellyfinApiKey: String = ""
    @AppStorage("jellyfinMovieLibraryId") private var jellyfinMovieLibraryId: String = ""
    @AppStorage("jellyfinTvLibraryId") private var jellyfinTvLibraryId: String = ""
    @AppStorage("jellyfinMovieServerPath") private var jellyfinMovieServerPath: String = ""
    @AppStorage("jellyfinTvServerPath") private var jellyfinTvServerPath: String = ""
    @AppStorage("isCustomMovieServerPath") private var isCustomMovieServerPath: Bool = false
    @AppStorage("isCustomTvServerPath") private var isCustomTvServerPath: Bool = false

    @State private var isFetchingLibraries: Bool = false
    @State private var jellyfinStatus: JellyfinDetectionState = .idle
    @State private var detectedLibraries: [JellyfinLibrary] = []

    // Diagnostics CLI Tools Dropdown State
    @State private var isToolsDropdownExpanded: Bool = false
    @State private var copiedToolName: String? = nil

    // Subtitles & Audio Dropdown States
    @State private var isSubtitleRetentionExpanded: Bool = false
    @State private var isOpenSubtitlesRestrictionsExpanded: Bool = false
    @State private var isSubtitleProcessingExpanded: Bool = false

    private var subtitleRetentionEnabledCount: Int {
        [keepSubRip, keepAssSsa, keepBitmapSubs, preferEmbeddedSubs, normalizeEmbeddedAllCaps, clearDefaultSubtitleFlags]
            .filter { $0 }
            .count
    }

    private var openSubtitlesRestrictionsEnabledCount: Int {
        [excludeHDTV, excludeHearingImpaired, excludeCommentary, preferExtendedCuts, matchVideoFPS, enforceDurationCheck, enforceContentCheck, enforceStructuralAlignmentCheck]
            .filter { $0 }
            .count
    }

    private var subtitleProcessingEnabledCount: Int {
        [stripSubtitleAds, stripSubtitleFormatting, normalizeSubtitleCase, syncSubtitlesAudio]
            .filter { $0 }
            .count
    }

    private var allToolsAvailable: Bool {
        let statuses = manager.toolRegistry.allToolsStatus
        return !statuses.isEmpty && statuses.allSatisfy { $0.isAvailable }
    }

    private var readyToolCount: Int {
        manager.toolRegistry.allToolsStatus.filter { $0.isAvailable }.count
    }

    private var totalToolCount: Int {
        manager.toolRegistry.allToolsStatus.count
    }

    var body: some View {
        ZStack {
            Color.bg
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    diagnosticsSection
                    storageDirectoriesSection
                    omdbSection
                    openSubtitlesSection
                    subtitleRetentionSection
                    openSubtitlesRestrictionsSection
                    subtitleProcessingSection
                    promptsAndDisambiguationSection
                    jellyfinSection
                    jellyfinStatusRow
                }
                .padding(16)
            }
        }
        .buttonStyle(SettingsButtonStyle())
        .onAppear {
            loadSettings()

            // Hidden by default if all are confirmed to be available; expanded if any are missing
            isToolsDropdownExpanded = !allToolsAvailable

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
        .onChange(of: allToolsAvailable) { _, available in
            isToolsDropdownExpanded = !available
        }
        .onChange(of: omdbKey) { _, _ in syncToConfig() }
        .onChange(of: openSubtitlesKey) { _, _ in syncToConfig() }
        .onChange(of: openSubtitlesUsername) { _, _ in syncToConfig() }
        .onChange(of: openSubtitlesPassword) { _, _ in syncToConfig() }
        .onChange(of: watchPath) { _, _ in syncToConfig() }
        .onChange(of: libraryPath) { _, _ in syncToConfig() }
        .onChange(of: tvLibraryPath) { _, _ in syncToConfig() }
        .onChange(of: subtitleRetentionMode) { _, _ in syncToConfig() }
        .onChange(of: customSubtitleLanguages) { _, _ in syncToConfig() }
        .onChange(of: keepSubRip) { _, _ in syncToConfig() }
        .onChange(of: keepAssSsa) { _, _ in syncToConfig() }
        .onChange(of: keepBitmapSubs) { _, _ in syncToConfig() }
        .onChange(of: preferEmbeddedSubs) { _, _ in syncToConfig() }
        .onChange(of: normalizeEmbeddedAllCaps) { _, _ in syncToConfig() }
        .onChange(of: clearDefaultSubtitleFlags) { _, _ in syncToConfig() }
        .onChange(of: excludeHDTV) { _, _ in syncToConfig() }
        .onChange(of: excludeHearingImpaired) { _, _ in syncToConfig() }
        .onChange(of: excludeCommentary) { _, _ in syncToConfig() }
        .onChange(of: preferExtendedCuts) { _, _ in syncToConfig() }
        .onChange(of: matchVideoFPS) { _, _ in syncToConfig() }
        .onChange(of: enforceDurationCheck) { _, _ in syncToConfig() }
        .onChange(of: enforceContentCheck) { _, _ in syncToConfig() }
        .onChange(of: enforceStructuralAlignmentCheck) { _, _ in syncToConfig() }
        .onChange(of: stripSubtitleAds) { _, _ in syncToConfig() }
        .onChange(of: stripSubtitleFormatting) { _, _ in syncToConfig() }
        .onChange(of: normalizeSubtitleCase) { _, _ in syncToConfig() }
        .onChange(of: syncSubtitlesAudio) { _, _ in syncToConfig() }
        .onChange(of: promptForSubtitleFallback) { _, _ in syncToConfig() }
        .onChange(of: promptForAmbiguousTitles) { _, _ in syncToConfig() }
        .onChange(of: jellyfinServerURL) { _, _ in
            syncToConfig()
            jellyfinStatus = .idle
            detectedLibraries = []
        }
        .onChange(of: jellyfinApiKey) { _, _ in syncToConfig() }
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

            Divider()

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

            Divider()

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

            Divider()

            HStack(alignment: .center) {
                Text("Password")
                Spacer()
                RevealingSecureField(placeholder: "Optional", text: $openSubtitlesPassword)
            }
        }
    }

    // MARK: - Section 4: Subtitles & Track Retention

    @ViewBuilder
    private var subtitleRetentionSection: some View {
        settingsSection() {
            HStack(alignment: .center) {
                Text("Subtitle Retention Language")
                Spacer()
                Picker("", selection: $subtitleRetentionMode) {
                    Text("English Only").tag("eng")
                    Text("Keep All").tag("all")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
            }
            if subtitleRetentionMode == "custom" {
                HStack(alignment: .center) {
                    Text("Custom Language Codes")
                    Spacer()
                    TextField("", text: $customSubtitleLanguages, prompt: Text("e.g. eng, spa, fre"))
                        .textFieldStyle(SettingsTextFieldStyle())
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 220, maxWidth: 300)
                }
            }

            Divider()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSubtitleRetentionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "captions.bubble.fill")
                        .foregroundStyle(Color.accentColor)

                    Text("Format & Retention Options")
                        .font(.system(size: 13, weight: .medium, design: .rounded))

                    Spacer()

                    Text("\(subtitleRetentionEnabledCount) of 6 enabled")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isSubtitleRetentionExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSubtitleRetentionExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Allowed Subtitle Formats")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.mainOpp.opacity(0.7))

                    Toggle("Keep SubRip / Text Subtitles (.srt)", isOn: $keepSubRip)
                    Toggle("Keep Advanced SubStation Alpha (.ass / .ssa)", isOn: $keepAssSsa)
                    Toggle("Keep Bitmap Subtitles (PGS / VobSub)", isOn: $keepBitmapSubs)

                    Divider()

                    Text("Embedded Subtitles Handling")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.mainOpp.opacity(0.7))

                    Toggle("Prefer Embedded Subtitles (Skip OpenSubtitles download if found)", isOn: $preferEmbeddedSubs)
                    Toggle("Normalize ALL-CAPS Embedded Subtitles to Sentence Case", isOn: $normalizeEmbeddedAllCaps)
                    Toggle("Clear Default Subtitle Flags (Prevent auto-display in media players)", isOn: $clearDefaultSubtitleFlags)
                }
                .padding(.top, 4)
                .clipped()
                .transition(.opacity)
            }
        }
    }

    // MARK: - Section 5: OpenSubtitles Quality & Restrictions

    @ViewBuilder
    private var openSubtitlesRestrictionsSection: some View {
        settingsSection() {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOpenSubtitlesRestrictionsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(Color.accentColor)

                    Text("Quality & Restriction Options")
                        .font(.system(size: 13, weight: .medium, design: .rounded))

                    Spacer()

                    Text("\(openSubtitlesRestrictionsEnabledCount) of 8 enabled")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpenSubtitlesRestrictionsExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpenSubtitlesRestrictionsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Exclude HDTV Releases", isOn: $excludeHDTV)
                    Toggle("Exclude Hearing Impaired / SDH Releases", isOn: $excludeHearingImpaired)
                    Toggle("Exclude Commentary & Description Tracks", isOn: $excludeCommentary)
                    Toggle("Prefer Extended & Director's Cuts", isOn: $preferExtendedCuts)

                    Divider()

                    Toggle("Strict Framerate (FPS) Match", isOn: $matchVideoFPS)
                    Toggle("Enforce Subtitle Duration Match (±180s tolerance)", isOn: $enforceDurationCheck)
                    Toggle("Verify Content Dialogue Structure (Reject truncated tracks)", isOn: $enforceContentCheck)
                    Toggle("Verify Audio Sync Shift Limits (alass structural shift checks)", isOn: $enforceStructuralAlignmentCheck)
                }
                .padding(.top, 4)
                .clipped()
                .transition(.opacity)
            }
        }
    }

    // MARK: - Section 6: Subtitle Processing

    @ViewBuilder
    private var subtitleProcessingSection: some View {
        settingsSection() {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSubtitleProcessingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.accentColor)

                    Text("Processing & Audio Alignment Options")
                        .font(.system(size: 13, weight: .medium, design: .rounded))

                    Spacer()

                    Text("\(subtitleProcessingEnabledCount) of 4 enabled")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isSubtitleProcessingExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSubtitleProcessingExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Strip Subtitle Advertisements & Promotional Links", isOn: $stripSubtitleAds)
                    Toggle("Strip Formatting Tags (HTML / ASS / SSA style markup)", isOn: $stripSubtitleFormatting)
                    Toggle("Normalize SHOUTING / ALL-CAPS Subtitles to Sentence Case", isOn: $normalizeSubtitleCase)
                    Toggle("Synchronize Timing to Audio Streams (ffsubsync / alass)", isOn: $syncSubtitlesAudio)
                }
                .padding(.top, 4)
                .clipped()
                .transition(.opacity)
            }
        }
    }

    // MARK: - Section 7: Interactive Prompts & Disambiguation

    @ViewBuilder
    private var promptsAndDisambiguationSection: some View {
        settingsSection("Interactive Prompts & Fallback Popups") {
            Toggle("Prompt with Ranked Releases when No Subtitles Pass Restrictions", isOn: $promptForSubtitleFallback)
            Toggle("Prompt with Ranked IMDb Matches for Ambiguous Titles", isOn: $promptForAmbiguousTitles)
        }
    }

    // MARK: - Section 8: Storage Directories

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

            Divider()

            directoryRow(
                title: "Movies Output",
                path: $libraryPath
            ) {
                chooseFolder { url in
                    libraryPath = url.path
                    syncToConfig()
                }
            }

            Divider()

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

    // MARK: - Section 9: Diagnostics

    @ViewBuilder
    private var diagnosticsSection: some View {
        settingsSection("Diagnostics") {
            // CLI Tools dropdown row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isToolsDropdownExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: allToolsAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(allToolsAvailable ? Color.green : Color.orange)

                    Text("CLI Tools & Dependencies")
                        .font(.system(size: 13, weight: .medium, design: .rounded))

                    Spacer()

                    Text("\(readyToolCount) of \(totalToolCount) available")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isToolsDropdownExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isToolsDropdownExpanded {
                VStack(spacing: 8) {
                    ForEach(manager.toolRegistry.allToolsStatus) { tool in
                        toolCard(for: tool)
                    }
                }
                .padding(.top, 4)
                .clipped()
                .transition(.opacity)
            }

            Divider()

            LabeledContent("Remux Queue Items") {
                Text("\(manager.queue.count)")
                    .foregroundStyle(.secondary)
            }

            Divider()

            if manager.jellyfinDirectAvailable {
                LabeledContent("Direct to Jellyfin Queue") {
                    Text("\(manager.jellyfinQueue.count)")
                        .foregroundStyle(.secondary)
                }

                Divider()
            }

            LabeledContent("Logging") {
                Text("\(manager.logs.count) entries recorded")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toolCard(for tool: ToolStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tool.isAvailable ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                    .frame(width: 32, height: 32)

                Image(systemName: tool.isAvailable ? "checkmark" : "exclamationmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tool.isAvailable ? Color.green : Color.orange)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.mainOpp)

                Text(tool.purpose)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.6))

                if let path = tool.path {
                    HStack(spacing: 6) {
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.mainOpp.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                            copiedToolName = tool.name
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                if copiedToolName == tool.name {
                                    copiedToolName = nil
                                }
                            }
                        } label: {
                            Image(systemName: copiedToolName == tool.name ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.mainOpp.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Copy path")
                    }
                    .padding(.top, 1)
                } else {
                    let cmd = "brew install \(suggestedBrewPackage(for: tool.name))"
                    HStack(spacing: 6) {
                        Text(cmd)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.orange)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cmd, forType: .string)
                            copiedToolName = tool.name
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                if copiedToolName == tool.name {
                                    copiedToolName = nil
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copiedToolName == tool.name ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9, weight: .bold))
                                Text(copiedToolName == tool.name ? "Copied" : "Copy")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(Color.orange).interactive(), in: Capsule())
                        .foregroundStyle(Color.white)
                    }
                    .padding(.top, 1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.subTwo)
        )
    }

    private func suggestedBrewPackage(for tool: String) -> String {
        switch tool {
        case "ffprobe", "ffmpeg": return "ffmpeg"
        case "HandBrakeCLI": return "handbrake"
        case "mkvmerge", "mkvpropedit", "mkvextract": return "mkvtoolnix"
        case "ffsubsync": return "pipx install ffsubsync"
        case "alass-cli", "alass": return "alass"
        default: return tool
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
                    Text("Testing connection & detecting Jellyboi File Upload plugin…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

            case .detected(let version, let serverName):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Jellyboi File Upload Plugin Active (v\(version))\(serverName.map { " on '\($0)'" } ?? "")")
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

                Divider()

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
                    Divider()
                    HStack(alignment: .center) {
                        Text("Movies Server Path")
                        Spacer()
                        TextField("", text: $jellyfinMovieServerPath, prompt: Text("e.g. /mnt/media/movies"))
                            .textFieldStyle(SettingsTextFieldStyle())
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 220, maxWidth: 300)
                    }
                }

                Divider()

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
                    Divider()
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
                            Text("Jellyfin Server Found\(serverName != nil ? " ('\(serverName!)')" : ""), but Jellyboi File Upload Plugin Is Missing.")
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                            Text("Install the Jellyboi File Upload plugin (Jellyfin.Plugin.JellyboiFileUpload.dll) inside your Jellyfin plugins directory and restart the server to enable direct streaming uploads.")
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
        _ title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.55))
                    .padding(.horizontal, 4)
            }

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

        subtitleRetentionMode = config.subtitleRetentionMode
        customSubtitleLanguages = config.customSubtitleLanguages
        keepSubRip = config.keepSubRip
        keepAssSsa = config.keepAssSsa
        keepBitmapSubs = config.keepBitmapSubs
        preferEmbeddedSubs = config.preferEmbeddedSubs
        normalizeEmbeddedAllCaps = config.normalizeEmbeddedAllCaps
        clearDefaultSubtitleFlags = config.clearDefaultSubtitleFlags

        excludeHDTV = config.excludeHDTV
        excludeHearingImpaired = config.excludeHearingImpaired
        excludeCommentary = config.excludeCommentary
        preferExtendedCuts = config.preferExtendedCuts
        matchVideoFPS = config.matchVideoFPS
        enforceDurationCheck = config.enforceDurationCheck
        enforceContentCheck = config.enforceContentCheck
        enforceStructuralAlignmentCheck = config.enforceStructuralAlignmentCheck

        stripSubtitleAds = config.stripSubtitleAds
        stripSubtitleFormatting = config.stripSubtitleFormatting
        normalizeSubtitleCase = config.normalizeSubtitleCase
        syncSubtitlesAudio = config.syncSubtitlesAudio

        promptForSubtitleFallback = config.promptForSubtitleFallback
        promptForAmbiguousTitles = config.promptForAmbiguousTitles

        if jellyfinServerURL.isEmpty && !config.jellyfinServerURL.isEmpty { jellyfinServerURL = config.jellyfinServerURL }
        if jellyfinApiKey.isEmpty && !config.jellyfinApiKey.isEmpty { jellyfinApiKey = config.jellyfinApiKey }
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

        manager.config.subtitleRetentionMode = subtitleRetentionMode
        manager.config.customSubtitleLanguages = customSubtitleLanguages
        manager.config.keepSubRip = keepSubRip
        manager.config.keepAssSsa = keepAssSsa
        manager.config.keepBitmapSubs = keepBitmapSubs
        manager.config.preferEmbeddedSubs = preferEmbeddedSubs
        manager.config.normalizeEmbeddedAllCaps = normalizeEmbeddedAllCaps
        manager.config.clearDefaultSubtitleFlags = clearDefaultSubtitleFlags

        manager.config.excludeHDTV = excludeHDTV
        manager.config.excludeHearingImpaired = excludeHearingImpaired
        manager.config.excludeCommentary = excludeCommentary
        manager.config.preferExtendedCuts = preferExtendedCuts
        manager.config.matchVideoFPS = matchVideoFPS
        manager.config.enforceDurationCheck = enforceDurationCheck
        manager.config.enforceContentCheck = enforceContentCheck
        manager.config.enforceStructuralAlignmentCheck = enforceStructuralAlignmentCheck

        manager.config.stripSubtitleAds = stripSubtitleAds
        manager.config.stripSubtitleFormatting = stripSubtitleFormatting
        manager.config.normalizeSubtitleCase = normalizeSubtitleCase
        manager.config.syncSubtitlesAudio = syncSubtitlesAudio

        manager.config.promptForSubtitleFallback = promptForSubtitleFallback
        manager.config.promptForAmbiguousTitles = promptForAmbiguousTitles

        manager.config.jellyfinServerURL = jellyfinServerURL
        manager.config.jellyfinApiKey = jellyfinApiKey
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
