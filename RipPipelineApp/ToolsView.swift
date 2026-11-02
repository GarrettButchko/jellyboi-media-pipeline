import SwiftUI
import AppKit
import BaseColors
import LoggingKit

struct ToolsView: View {
    @Bindable var manager: PipelineManager
    @State private var copiedToolName: String? = nil

    private var readyCount: Int {
        manager.toolRegistry.allToolsStatus.filter { $0.isAvailable }.count
    }

    private var totalCount: Int {
        manager.toolRegistry.allToolsStatus.count
    }

    var body: some View {
        ZStack {
            Color.bg
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Status subtitle banner
                    HStack(spacing: 8) {
                        Image(systemName: readyCount == totalCount ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(readyCount == totalCount ? Color.green : Color.orange)

                        Text("\(readyCount) of \(totalCount) tools installed and ready")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.mainOpp.opacity(0.75))

                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                    // Tools list
                    LazyVStack(spacing: 10) {
                        ForEach(manager.toolRegistry.allToolsStatus) { tool in
                            toolCard(for: tool)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Tool Card (Flat, No Shadows)

    private func toolCard(for tool: ToolStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tool.isAvailable ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                    .frame(width: 38, height: 38)

                Image(systemName: tool.isAvailable ? "checkmark" : "exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tool.isAvailable ? Color.green : Color.orange)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.mainOpp)

                Text(tool.purpose)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.6))

                if let path = tool.path {
                    HStack(spacing: 6) {
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .jellyCard(cornerRadius: 12)
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
}
