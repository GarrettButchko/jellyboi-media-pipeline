import SwiftUI
import AppKit
import BaseColors
import LoggingKit

// MARK: - View Model

@Observable
@MainActor
public final class LogViewModel {
    public var filterLevel: LogLevel? = nil
    public var searchText: String = ""
    public var isLevelMenuOpen: Bool = false
    public var hoveredLevelIndex: Int? = nil

    public init(filterLevel: LogLevel? = nil, searchText: String = "") {
        self.filterLevel = filterLevel
        self.searchText = searchText
    }

    public var levelTitle: String {
        filterLevel?.title ?? "All Levels"
    }

    public func filteredLogs(from logs: [AppLogMessage]) -> [AppLogMessage] {
        logs.filter { log in
            if let level = filterLevel, log.level < level {
                return false
            }
            if !searchText.isEmpty && !log.message.localizedCaseInsensitiveContains(searchText) {
                return false
            }
            return true
        }
    }
}

struct LogView: View {
    @Bindable var manager: PipelineManager
    @State private var viewModel = LogViewModel()

    private var filteredLogs: [AppLogMessage] {
        viewModel.filteredLogs(from: manager.logs)
    }

    private func levelRow(
        index: Int,
        title: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            viewModel.isLevelMenuOpen = false
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(color)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(viewModel.hoveredLevelIndex == index ? Color.mainOpp.opacity(0.1) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                viewModel.hoveredLevelIndex = index
            } else if viewModel.hoveredLevelIndex == index {
                viewModel.hoveredLevelIndex = nil
            }
        }
    }

    var body: some View {
        ZStack {
            Color.bg
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // Top control bar
                HStack(spacing: 10) {
                    // Search bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mainOpp.opacity(0.45))

                        TextField("Filter logs…", text: $viewModel.searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.mainOpp)

                        if !viewModel.searchText.isEmpty {
                            Button {
                                viewModel.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mainOpp.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.sub, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.mainOpp.opacity(0.08), lineWidth: 0.8))
                    .frame(maxWidth: 240)

                    // Level picker
                    Button {
                        viewModel.isLevelMenuOpen.toggle()
                    } label: {
                        HStack{
                            Text(viewModel.levelTitle)
                            Image(systemName: "chevron.down")
                        }
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.mainOpp)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.sub)
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .popover(isPresented: $viewModel.isLevelMenuOpen) {
                        VStack(alignment: .leading, spacing: 2) {
                            levelRow(index: 0, title: "All Levels", color: Color.mainOpp, isSelected: viewModel.filterLevel == nil) {
                                viewModel.filterLevel = nil
                            }
                            levelRow(index: 1, title: LogLevel.success.title, color: LogLevel.success.badgeColor, isSelected: viewModel.filterLevel == .success) {
                                viewModel.filterLevel = .success
                            }
                            levelRow(index: 2, title: LogLevel.warning.title, color: LogLevel.warning.badgeColor, isSelected: viewModel.filterLevel == .warning) {
                                viewModel.filterLevel = .warning
                            }
                            levelRow(index: 3, title: LogLevel.error.title, color: LogLevel.error.badgeColor, isSelected: viewModel.filterLevel == .error) {
                                viewModel.filterLevel = .error
                            }
                        }
                        .padding(4)
                        .frame(minWidth: 140)
                        .background(Color.sub.opacity(0.5))
                    }

                    Spacer()

                    // Action buttons
                    Button {
                        let text = manager.logs.map { $0.message }.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                            Text("Copy All")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .foregroundStyle(Color.mainOpp)
                    .disabled(manager.logs.isEmpty)
                    .opacity(manager.logs.isEmpty ? 0.45 : 1.0)

                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            manager.logs.removeAll()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Clear")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .foregroundStyle(Color.mainOpp.opacity(0.75))
                    .disabled(manager.logs.isEmpty)
                    .opacity(manager.logs.isEmpty ? 0.45 : 1.0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Log console container (Flat, No Shadows)
                VStack(spacing: 0) {
                    if filteredLogs.isEmpty {
                        EmptyStateView(
                            icon: "doc.text.magnifyingglass",
                            title: viewModel.searchText.isEmpty && viewModel.filterLevel == nil ? "No Logs Recorded" : "No Matching Logs",
                            message: viewModel.searchText.isEmpty && viewModel.filterLevel == nil ? "Pipeline logs, track demux details, and external tool outputs will stream here." : "Try adjusting your search query or minimum log level filter."
                        )
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(filteredLogs) { log in
                                        LogEntryRow(log: log)
                                            .id(log.id)
                                    }
                                }
                                .padding(12)
                            }
                            .onChange(of: manager.logs.count) { _, _ in
                                if let last = manager.logs.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.sub)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.mainOpp.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let log: AppLogMessage

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: log.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.mainOpp.opacity(0.35))
                .padding(.top, 1)

            Text(log.level.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(log.level.badgeColor.opacity(0.15))
                .foregroundStyle(log.level.badgeColor)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(log.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(log.levelColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
