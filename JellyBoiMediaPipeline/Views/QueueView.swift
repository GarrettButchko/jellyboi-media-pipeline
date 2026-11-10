import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BaseColors
import LoggingKit

struct QueueView: View {
    @Bindable var manager: PipelineManager
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Color.bg
                .ignoresSafeArea()

            if manager.queue.isEmpty {
                emptyDropZone
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(manager.queue) { item in
                            QueueRowView(item: item, manager: manager)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))
                                ))
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private var emptyDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.mainOpp.opacity(0.15),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.04) : Color.sub.opacity(0.4))
                )
                .padding(20)

            EmptyStateView(
                icon: isTargeted ? "arrow.down.circle.fill" : "slider.horizontal.3",
                title: isTargeted ? "Drop to Add MKV Files" : "Drag & Drop MKV Disc Rips",
                message: "Rip Pipeline will automatically inspect streams, match IMDb titles, detect video crop, fetch subtitles, and organize into your library."
            )
        }
        .animation(.smooth(duration: 0.2), value: isTargeted)
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

// MARK: - Queue Item Row (Flat, No Shadows)

struct QueueRowView: View {
    let item: QueueItem
    @Bindable var manager: PipelineManager


    private var displayDetail: String {
        if item.status == .completed {
            if item.statusDetail.hasPrefix("Remuxing") || item.statusDetail.hasPrefix("Moving") || item.statusDetail.contains("Jellyfin") || item.statusDetail.contains("Streaming") || item.statusDetail.isEmpty {
                return "Successfully organized to library"
            }
        }
        return item.statusDetail
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Stage / Media icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.status.color.gradient)
                    .frame(width: 38, height: 38)

                Image(systemName: item.stage.systemImageName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .contentTransition(.symbolEffect(.replace))
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.fileName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)
                    
                    Text(item.fileSizeString)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.5))

                    Spacer()
                }

                Text(displayDetail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(item.status == .failed ? Color.red : Color.mainOpp.opacity(0.6))
                    .lineLimit(1)

                if item.status == .running {
                    GlassProgressBar(
                        progress: item.progressFraction,
                        barHeight: 4,
                        label: "\(Int(item.progressFraction * 100))%",
                        tintColor: Color.accentColor
                    )
                    .padding(.top, 2)
                } else if item.status == .completed {
                    GlassProgressBar(
                        progress: 1.0,
                        barHeight: 4,
                        label: "100%",
                        tintColor: .green
                    )
                    .padding(.top, 2)
                }
            }

            // Action buttons
            HStack(spacing: 6) {
                if item.status == .failed || item.status == .cancelled {
                    JellyIconButton(systemImage: "arrow.clockwise", tintColor: Color.accentColor) {
                        manager.retryQueueItem(id: item.id)
                    }
                    .help("Retry processing")
                }

                if item.status == .completed && manager.jellyfinDirectAvailable {
                    let dest = item.completedURL ?? item.fileURL
                    let alreadyQueued = manager.jellyfinQueue.contains(where: { $0.fileURL.path == dest.path })
                    JellyIconButton(
                        systemImage: alreadyQueued ? "arrow.up.circle.fill" : "arrow.up.circle",
                        tintColor: Color.accentColor
                    ) {
                        manager.sendToJellyfin(queueItem: item)
                    }
                    .help(alreadyQueued ? "Already in Direct to Jellyfin queue" : "Send to Direct to Jellyfin")
                    .disabled(alreadyQueued)
                }

                if let completedURL = item.completedURL {
                    JellyIconButton(systemImage: "folder", tintColor: Color.accentColor) {
                        NSWorkspace.shared.activateFileViewerSelecting([completedURL])
                    }
                    .help("Show in Finder")
                }

                if item.status != .running {
                    JellyIconButton(systemImage: "xmark", tintColor: Color.mainOpp.opacity(0.45)) {
                        manager.removeItem(id: item.id)
                    }
                    .help("Remove item")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .jellyCard(cornerRadius: 12)
        .animation(.smooth(duration: 0.3), value: item.status)
        .animation(.smooth(duration: 0.3), value: item.stage)
    }
}
