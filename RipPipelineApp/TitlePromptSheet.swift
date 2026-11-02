import SwiftUI
import BaseColors
import LoggingKit

struct TitlePromptSheet: View {
    let request: TitlePromptRequest
    @Bindable var manager: PipelineManager

    @State private var inputTitle: String = ""

    var body: some View {
        ZStack {
            Color.bg
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 52, height: 52)

                        Image(systemName: "opticaldisc.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Raw Disc Rip Detected")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.mainOpp)

                        Text(request.fileName)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.mainOpp.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.subTwo, in: Capsule())
                    }

                    Spacer()
                }

                // Explanation note
                Text(request.reason.userExplanation)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                // Input card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter Media Title:")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.mainOpp)

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)

                        TextField("e.g. The Matrix (1999) or Breaking Bad S01E01", text: $inputTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color.mainOpp)
                            .onSubmit {
                                submit()
                            }

                        if !inputTitle.isEmpty {
                            Button {
                                inputTitle = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.mainOpp.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(Color.subTwo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Suggested title quick chip
                    if let suggested = request.suggestedTitle, !suggested.isEmpty, inputTitle != suggested {
                        Button {
                            inputTitle = suggested
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Suggestion: \(suggested)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(Color.accentColor).interactive(), in: Capsule())
                        .foregroundStyle(Color.white)
                    }

                    // Format tips
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: "film")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                            Text("Movies: Include title and release year (e.g. Inception (2010))")
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "tv")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                            Text("TV Shows: Include series name and SxxExx (e.g. Friends S01E01)")
                        }
                    }
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color.mainOpp.opacity(0.5))
                    .padding(.top, 4)
                }
                .padding(16)
                .jellyCard(cornerRadius: 16)

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        manager.submitTitle(nil)
                    } label: {
                        Text("Keep Original & Skip")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .foregroundStyle(Color.mainOpp.opacity(0.75))
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Apply & Continue")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(Color.accentColor).interactive(), in: Capsule())
                    .foregroundStyle(Color.white)
                    .keyboardShortcut(.defaultAction)
                    .disabled(inputTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(inputTitle.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1.0)
                }
                .padding(.top, 6)
            }
            .padding(24)
        }
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
