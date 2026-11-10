import SwiftUI
import BaseColors

struct SubtitleSelectionSheet: View {
    let request: SubtitleSelectionRequest
    @Bindable var manager: PipelineManager
    @AppStorage("promptForSubtitleFallback") private var promptForSubtitleFallback = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Alternative Subtitle for \(request.mediaTitle)")
                        .font(.headline)
                        .foregroundStyle(Color.mainOpp)
                    
                    Text("No subtitles passed all quality restrictions. You may pick an alternative release or skip:")
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
                .background(Color.sub.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            
            // Subtitle candidates list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(request.candidates.enumerated()), id: \.element.id) { index, candidate in
                        SubtitleCandidateRow(index: index + 1, candidate: candidate) {
                            manager.resolveSubtitlePrompt(request: request, candidate: candidate)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 320)
            
            Divider()
            
            // Footer
            HStack {
                Toggle("Prompt when no subtitles pass restrictions", isOn: $promptForSubtitleFallback)
                    .font(.caption)
                    .foregroundStyle(Color.mainOpp.opacity(0.7))
                    .onChange(of: promptForSubtitleFallback) { _, newValue in
                        manager.config.promptForSubtitleFallback = newValue
                        manager.config.saveToUserDefaults()
                    }
                
                Spacer()
                
                Button("Skip Subtitles") {
                    manager.resolveSubtitlePrompt(request: request, candidate: nil)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 620)
        .background(Color.bg)
    }
}

private struct SubtitleCandidateRow: View {
    let index: Int
    let candidate: SubtitleCandidate
    let onChoose: () -> Void
    
    @State private var showingRejections = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    // Release title
                    Text(candidate.release)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.mainOpp)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Text("\(candidate.downloadCount.formatted()) dl")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mainOpp.opacity(0.6))
                }
                
                // Attributes and badges
                HStack(spacing: 6) {
                    if let fps = candidate.fps {
                        badge(text: String(format: "%.3f fps", fps), color: .accentColor)
                    }
                    
                    if candidate.hearingImpaired {
                        badge(text: "SDH / HI", color: .orange)
                    }
                    
                    if candidate.isHDTV {
                        badge(text: "HDTV", color: .purple)
                    }
                    
                    if candidate.isCutVariant {
                        badge(text: "Cut Variant", color: .indigo)
                    }
                    
                    if candidate.isCommentary {
                        badge(text: "Commentary", color: .red)
                    }
                    
                    if !candidate.rejectionReasons.isEmpty {
                        Button {
                            showingRejections.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(candidate.rejectionReasons.count == 1 ? "1 Issue" : "\(candidate.rejectionReasons.count) Issues")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.orange)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingRejections, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Color.orange)
                                    Text("Rejection Reasons")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color.mainOpp)
                                }
                                
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(candidate.rejectionReasons, id: \.self) { reason in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text(reason)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color.mainOpp.opacity(0.85))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .frame(width: 280)
                        }
                        .help("View why this subtitle was rejected")
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
        .background(Color.sub.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
