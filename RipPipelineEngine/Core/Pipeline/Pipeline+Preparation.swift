import Foundation
import LoggingKit

extension Pipeline {
    func validateAndPrepare(
        fileURL: URL,
        workingURL: URL,
        fileName: String,
        delegate: PipelineDelegate?
    ) async -> Bool {
        AppLogger.info("=== Processing: \(fileName) ===")
        Notifier.notify(title: "Rip Pipeline", message: "Processing: \(fileName)")

        await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
            fileURL: fileURL,
            stage: .queued,
            progressFraction: 0.0,
            detail: "Queued for processing"
        ))

        guard await waitForWrite(fileURL: workingURL, delegate: delegate) else {
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "File write incomplete or file disappeared"
            ))
            return false
        }

        guard !config.omdbKey.isEmpty else {
            AppLogger.error("OMDb API key not configured. Set via preferences or config file.")
            Notifier.notify(title: "Rip Pipeline ⚠️", message: "OMDb API key not configured.")
            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .failed,
                detail: "OMDb API key is missing. Configure in Preferences."
            ))
            return false
        }

        return true
    }

    func handleRawDiscRip(
        fileURL: URL,
        workingURL: URL,
        fileName: String,
        delegate: PipelineDelegate?
    ) async -> (workingURL: URL, fileName: String) {
        var currentURL = workingURL
        var currentName = fileName

        let discCheck = DiscRipRecognizer.analyze(fileURL: currentURL)
        if discCheck.isDiscRip, let promptProvider = titlePromptProvider {
            AppLogger.info("Raw disc rip detected (\(discCheck.reason?.rawValue ?? "disc")): \(currentName)")

            var candidates: [String] = []
            if MediaQueryAssistant.isAvailable {
                await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                    fileURL: fileURL,
                    stage: .awaitingTitle,
                    progressFraction: 0.06,
                    detail: "Analyzing disc rip with on-device AI…"
                ))
                let parentDir = currentURL.deletingLastPathComponent().lastPathComponent
                candidates = await MediaQueryAssistant.suggestDiscRipCandidates(
                    fileName: currentName,
                    parentFolder: (parentDir.isEmpty || parentDir == "/") ? nil : parentDir
                )
            }

            if let suggested = discCheck.suggestedTitle, !suggested.isEmpty {
                if !candidates.contains(where: { $0.caseInsensitiveCompare(suggested) == .orderedSame }) {
                    candidates.insert(suggested, at: 0)
                }
            }

            await delegate?.pipelineDidUpdateProgress(PipelineProgressUpdate(
                fileURL: fileURL,
                stage: .awaitingTitle,
                progressFraction: 0.08,
                detail: discCheck.reason?.userExplanation ?? "Raw disc rip detected. Please enter accurate title."
            ))

            if let userTitle = await promptProvider.promptForTitle(
                fileURL: currentURL,
                suggestedTitle: discCheck.suggestedTitle ?? candidates.first,
                candidates: candidates,
                reason: discCheck.reason ?? .genericMakeMKV
            ), !userTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                let trimmedTitle = userTitle.trimmingCharacters(in: .whitespaces)
                AppLogger.info("User provided accurate title: '\(trimmedTitle)'")

                let dir = currentURL.deletingLastPathComponent()
                let ext = currentURL.pathExtension
                let safeName = LibraryOrganizer.safeFilename(trimmedTitle) + (ext.isEmpty ? "" : ".\(ext)")
                let targetURL = dir.appendingPathComponent(safeName)

                if targetURL.path != currentURL.path && !FileManager.default.fileExists(atPath: targetURL.path) {
                    if (try? FileManager.default.moveItem(at: currentURL, to: targetURL)) != nil {
                        currentURL = targetURL
                        currentName = currentURL.lastPathComponent
                        AppLogger.info("Renamed file to: \(currentName)")
                    }
                }
            }
        }

        return (currentURL, currentName)
    }
}
