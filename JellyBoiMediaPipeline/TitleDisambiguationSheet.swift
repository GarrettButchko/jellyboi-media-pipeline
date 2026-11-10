import SwiftUI
import BaseColors

struct TitleDisambiguationSheet: View {
    let request: TitleDisambiguationRequest
    @Bindable var manager: PipelineManager
    @AppStorage("promptForAmbiguousTitles") private var promptForAmbiguousTitles = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Matching Title for \(request.originalQuery)")
                        .font(.headline)
                        .foregroundStyle(Color.mainOpp)

                    Text("Multiple matches found. Choose the correct title or verify on IMDb:")
                        .font(.caption)
                        .foregroundStyle(Color.mainOpp.opacity(0.7))
                }
            }

            // Media file label
            Text(request.fileURL.lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(Color.mainOpp.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sub, in: RoundedRectangle(cornerRadius: 6))

            // Title candidates list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(request.candidates.enumerated()), id: \.element.imdbId) { index, candidate in
                        TitleCandidateRow(index: index + 1, candidate: candidate) {
                            manager.resolveTitleDisambiguation(request: request, candidate: candidate)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 320)

            Divider()

            // Footer controls
            HStack {
                Toggle("Prompt for ambiguous titles", isOn: $promptForAmbiguousTitles)
                    .font(.caption)
                    .foregroundStyle(Color.mainOpp.opacity(0.7))
                    .onChange(of: promptForAmbiguousTitles) { _, newValue in
                        manager.config.promptForAmbiguousTitles = newValue
                        manager.config.saveToUserDefaults()
                    }

                Spacer()

                Button("Skip") {
                    manager.resolveTitleDisambiguation(request: request, candidate: nil)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 620)
        .background(Color.bg)
    }
}

private struct TitleCandidateRow: View {
    let index: Int
    let candidate: OMDbClient.Candidate
    let onChoose: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    // Candidate title
                    Text(candidate.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("(\(candidate.year))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))

                    if candidate.votes > 0 {
                        Text("\(candidate.votes.formatted()) votes")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }
                }

                // Attributes and badges
                HStack(spacing: 6) {
                    badge(text: candidate.type.capitalized, color: .accentColor)

                    if let rt = candidate.runtimeMinutes, rt > 0 {
                        badge(text: "\(rt) min", color: .purple)
                    }

                    if let url = URL(string: "https://www.imdb.com/title/\(candidate.imdbId)/") {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text(candidate.imdbId)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Open '\(candidate.title)' on IMDb in browser")
                    } else {
                        badge(text: candidate.imdbId, color: .accentColor)
                    }
                }
            }

            Spacer()

            Button("Choose") {
                onChoose()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.sub, in: RoundedRectangle(cornerRadius: 8))
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
