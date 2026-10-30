import SwiftUI
import AppKit

struct LogView: View {
    @Bindable var manager: PipelineManager
    @State private var filterLevel: LogLevel? = nil
    @State private var searchText: String = ""

    var filteredLogs: [AppLogMessage] {
        manager.logs.filter { log in
            if let level = filterLevel, log.level < level {
                return false
            }
            if !searchText.isEmpty && !log.message.localizedCaseInsensitiveContains(searchText) {
                return false
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search logs…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                Picker("Min Level", selection: $filterLevel) {
                    Text("All").tag(LogLevel?.none)
                    Text("Info").tag(LogLevel?.some(.info))
                    Text("Warning").tag(LogLevel?.some(.warning))
                    Text("Error").tag(LogLevel?.some(.error))
                }
                .frame(width: 120)

                Spacer()

                Button("Copy All") {
                    let text = manager.logs.map { $0.message }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }

                Button("Clear") {
                    manager.logs.removeAll()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(filteredLogs) { log in
                            Text(log.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(log.levelColor)
                                .textSelection(.enabled)
                                .id(log.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: manager.logs.count) { _, _ in
                    if let last = manager.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}
