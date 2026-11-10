import SwiftUI
import BaseColors

struct DiscRipTitleSheet: View {
    let request: TitlePromptRequest
    @Bindable var manager: PipelineManager
    @State private var enteredTitle: String = ""

    init(request: TitlePromptRequest, manager: PipelineManager) {
        self.request = request
        self.manager = manager
        _enteredTitle = State(initialValue: request.suggestedTitle ?? request.candidates.first ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Media Title Confirmation")
                        .font(.headline)
                        .foregroundStyle(Color.mainOpp)

                    Text(request.reason.userExplanation)
                        .font(.caption)
                        .foregroundStyle(Color.mainOpp.opacity(0.7))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Source File:")
                    .font(.caption)
                    .foregroundStyle(Color.mainOpp.opacity(0.6))
                Text(request.fileURL.lastPathComponent)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.mainOpp)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.sub, in: RoundedRectangle(cornerRadius: 6))
            }

            if !request.candidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                        Text("Suggested Matches:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.mainOpp)
                    }

                    VStack(spacing: 6) {
                        ForEach(request.candidates, id: \.self) { candidate in
                            let isSelected = enteredTitle.caseInsensitiveCompare(candidate) == .orderedSame
                            Button {
                                enteredTitle = candidate
                            } label: {
                                HStack {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.accentColor : Color.mainOpp.opacity(0.4))
                                    Text(candidate)
                                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                                        .foregroundStyle(Color.mainOpp)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.sub)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    enteredTitle = candidate
                                    submit()
                                }
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(request.candidates.isEmpty ? "Accurate Title or IMDb ID (e.g. tt1234567):" : "Edit or Enter Title / IMDb ID:")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.mainOpp)

                TextField("Enter movie or TV series title", text: $enteredTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submit()
                    }
            }

            HStack {
                Button("Skip") {
                    manager.resolveTitlePrompt(request: request, title: nil)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Confirm Title") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(enteredTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(Color.bg)
    }

    private func submit() {
        let trimmed = enteredTitle.trimmingCharacters(in: .whitespaces)
        manager.resolveTitlePrompt(request: request, title: trimmed.isEmpty ? nil : trimmed)
    }
}
