import SwiftUI
import BaseColors

struct DiscRipTitleSheet: View {
    let request: TitlePromptRequest
    @Bindable var manager: PipelineManager
    @State private var enteredTitle: String = ""

    init(request: TitlePromptRequest, manager: PipelineManager) {
        self.request = request
        self.manager = manager
        _enteredTitle = State(initialValue: request.suggestedTitle ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
                    .background(Color.sub.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Accurate Title or IMDb ID (e.g. tt1234567):")
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
