import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BaseColors
import LoggingKit

struct JellyfinDirectView: View {
    @Bindable var manager: PipelineManager
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Color.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if manager.jellyfinQueue.isEmpty {
                    emptyDropZone
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(manager.jellyfinQueue) { item in
                                JellyfinQueueRowView(item: item, manager: manager)
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
                icon: isTargeted ? "arrow.down.circle.fill" : "server.rack",
                title: isTargeted ? "Drop Files to Upload to Jellyfin" : "Direct Download / Upload to Jellyfin",
                message: "Drop finished MKV remuxes or video files here to stream directly to your Jellyfin server. Uploads are processed separately from the remuxing queue."
            )
        }
        .animation(.smooth(duration: 0.2), value: isTargeted)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        manager.addJellyfinFiles(urls: [url])
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Jellyfin Queue Row View

struct JellyfinQueueRowView: View {
    let item: JellyfinUploadItem
    @Bindable var manager: PipelineManager

    private var iconName: String {
        switch item.mediaType {
        case .movie:
            return "film"
        case .tvEpisode:
            return "tv"
        }
    }

   
        
    

    private var destinationLabel: String {
        if item.mediaType == .movie {
            let path = item.targetServerPath ?? manager.config.jellyfinMovieServerPath
            return path.isEmpty ? "Movie Library" : "Movies: \(path)"
        } else {
            let path = item.targetServerPath ?? manager.config.jellyfinTvServerPath
            return path.isEmpty ? "TV Shows" : "TV: \(path)"
        }
    }

    private var detailText: String {
        if item.statusDetail.isEmpty {
            return destinationLabel
        }
        return "\(item.statusDetail) • \(destinationLabel)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Media Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.status.color.gradient)
                    .frame(width: 38, height: 38)

                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .contentTransition(.symbolEffect(.replace))
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.fileURL.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)

                    Text(item.fileSizeString)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.5))

                    Spacer()
                }

                Text(detailText)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(item.status == .failed ? Color.red : Color.mainOpp.opacity(0.6))
                    .lineLimit(1)

                if item.status == .uploading {
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

            // Action Buttons
            HStack(spacing: 6) {
                if item.status == .failed || item.status == .cancelled {
                    JellyIconButton(systemImage: "arrow.clockwise", tintColor: Color.accentColor) {
                        manager.retryJellyfinItem(id: item.id)
                    }
                    .help("Retry upload")
                }

                JellyIconButton(systemImage: "folder", tintColor: Color.accentColor) {
                    NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                }
                .help("Show in Finder")

                if item.status != .uploading {
                    JellyIconButton(systemImage: "xmark", tintColor: Color.mainOpp.opacity(0.45)) {
                        manager.removeJellyfinItem(id: item.id)
                    }
                    .help("Remove item")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .jellyCard(cornerRadius: 12)
        .animation(.smooth(duration: 0.3), value: item.status)
    }
}
