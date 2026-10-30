import SwiftUI
import AppKit

struct ToolsView: View {
    @Bindable var manager: PipelineManager

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("External Media Tool Status")
                        .font(.headline)
                    Text("Rip Pipeline requires command-line tools for probing, crop detection, and track remuxing. These are typically installed via Homebrew or custom paths.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Detected Tools") {
                ForEach(manager.toolRegistry.allToolsStatus) { tool in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: tool.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(tool.isAvailable ? .green : .orange)
                            .imageScale(.large)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(tool.name)
                                    .font(.headline)
                                Spacer()
                                Text(tool.isAvailable ? "Ready" : "Not Found")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(tool.isAvailable ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                    .foregroundColor(tool.isAvailable ? .green : .orange)
                                    .clipShape(Capsule())
                            }

                            Text(tool.purpose)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let path = tool.path {
                                Text(path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text("Install with: brew install \(suggestedBrewPackage(for: tool.name))")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.inset)
    }

    private func suggestedBrewPackage(for tool: String) -> String {
        switch tool {
        case "ffprobe", "ffmpeg": return "ffmpeg"
        case "HandBrakeCLI": return "handbrake"
        case "mkvmerge", "mkvpropedit", "mkvextract": return "mkvtoolnix"
        case "ffsubsync": return "pipx install ffsubsync"
        case "alass-cli", "alass": return "brew install alass"
        default: return tool
        }
    }
}
