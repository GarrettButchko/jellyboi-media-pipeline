import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct QueueView: View {
    @Bindable var manager: PipelineManager
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if manager.queue.isEmpty {
                emptyDropZone
            } else {
                List {
                    ForEach(manager.queue) { item in
                        QueueRowView(item: item, manager: manager)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            manager.queue.remove(at: idx)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private var emptyDropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 56))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            Text("Drag & Drop MKV Disc Rips or Folders Here")
                .font(.title2)
                .bold()

            Text("Rip Pipeline will automatically inspect media streams, match IMDb titles, detect video crop, fetch subtitles, and organize into your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            HStack(spacing: 12) {
                Button("Choose Files…") {
                    chooseFiles()
                }
                .buttonStyle(.borderedProminent)

                Button("Choose Folder…") {
                    chooseFolder()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(24)
        )
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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        manager.addFiles(urls: [url])
                    }
                }
            }
        }
        return true
    }
}

struct QueueRowView: View {
    let item: QueueItem
    @Bindable var manager: PipelineManager

    private var iconName: String {
        if item.status == .completed {
            return "checkmark.circle.fill"
        }
        return item.stage.systemImageName
    }

    private var displayDetail: String {
        if item.status == .completed {
            if item.statusDetail.hasPrefix("Remuxing") || item.statusDetail.hasPrefix("Moving") || item.statusDetail.isEmpty {
                return "Completed"
            }
        }
        return item.statusDetail
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(item.status.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.fileName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(item.fileSizeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(item.status.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.status.color.opacity(0.15))
                        .foregroundStyle(item.status.color)
                        .clipShape(Capsule())
                }

                Text(displayDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if item.status == .running {
                    ProgressView(value: item.progressFraction)
                        .progressViewStyle(.linear)
                } else if item.status == .completed {
                    ProgressView(value: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.green)
                }
            }

            if item.status == .awaitingTitle {
                Button("Enter Title…") {
                    if manager.activeTitleRequest == nil {
                        let check = DiscRipRecognizer.analyze(fileURL: item.fileURL)
                        Task {
                            _ = await manager.promptForTitle(
                                fileURL: item.fileURL,
                                suggestedTitle: check.suggestedTitle,
                                reason: check.reason ?? .genericMakeMKV
                            )
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
            }

            if let completedURL = item.completedURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([completedURL])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }

            if item.status != .running && item.status != .awaitingTitle {
                Button {
                    manager.removeItem(id: item.id)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
