import SwiftUI

struct TitlePromptSheet: View {
    let request: TitlePromptRequest
    @Bindable var manager: PipelineManager

    @State private var inputTitle: String = ""

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Raw Disc Rip Detected")
                        .font(.title2)
                        .bold()

                    Text(request.fileName)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(request.reason.userExplanation)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Enter Media Title:")
                    .font(.headline)

                TextField("e.g. The Matrix (1999) or Breaking Bad S01E01", text: $inputTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submit()
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Label("For Movies: Include title and release year (e.g. Inception (2010))", systemImage: "film")
                    Label("For TV Shows: Include series name and SxxExx (e.g. Friends S01E01)", systemImage: "tv")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Keep Original Name & Skip") {
                    manager.submitTitle(nil)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Apply Title & Continue") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(inputTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            if let suggested = request.suggestedTitle, !suggested.isEmpty {
                inputTitle = suggested
            }
        }
    }

    private func submit() {
        let trimmed = inputTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            manager.submitTitle(trimmed)
        } else {
            manager.submitTitle(nil)
        }
    }
}
