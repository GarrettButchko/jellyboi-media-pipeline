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
                    Text("Select Matching Title")
                        .font(.headline)
                        .foregroundStyle(Color.mainOpp)

                    Text("Multiple matches found for \"\(request.originalQuery)\". Choose the correct title or verify on IMDb:")
                        .font(.caption)
                        .foregroundStyle(Color.mainOpp.opacity(0.7))
                }
            }

            // Source filename hint
            Text(request.fileURL.lastPathComponent)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.mainOpp.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sub.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            // Candidates list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(request.candidates.enumerated()), id: \.element.imdbId) { index, candidate in
                        candidateRow(index: index + 1, candidate: candidate)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 280)

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
        .frame(width: 560)
        .background(Color.bg)
    }

    private func candidateRow(index: Int, candidate: OMDbClient.Candidate) -> some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("#\(index)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.mainOpp.opacity(0.6))
                .frame(width: 24, alignment: .leading)

            // Title & metadata
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(candidate.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.mainOpp)

                    Text("(\(candidate.year))")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))

                    Text(candidate.type.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }

                HStack(spacing: 10) {
                    if candidate.votes > 0 {
                        Text("\(candidate.votes.formatted()) votes")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }

                    if let rt = candidate.runtimeMinutes, rt > 0 {
                        Text("\(rt) min")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                    }

                    Text(candidate.imdbId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.mainOpp.opacity(0.45))
                }
            }

            Spacer()

            // IMDb Link
            if let url = URL(string: "https://www.imdb.com/title/\(candidate.imdbId)/") {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Open '\(candidate.title)' on IMDb in browser")
            }

            // Select button
            Button("Select") {
                manager.resolveTitleDisambiguation(request: request, candidate: candidate)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.sub.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
