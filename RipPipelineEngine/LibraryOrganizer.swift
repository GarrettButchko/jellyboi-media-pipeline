import Foundation
import LoggingKit

public struct LibraryOrganizer: Sendable {
    public static func safeFilename(_ s: String) -> String {
        var str = s.precomposedStringWithCanonicalMapping
        str = str.replacingOccurrences(of: ":", with: " -")

        // Strip illegal filename characters
        let illegal = CharacterSet(charactersIn: "<>\"/\\|?*")
        str = str.components(separatedBy: illegal).joined()
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func moveToLibrary(
        srcURL: URL,
        title: String,
        year: String,
        imdbId: String,
        libraryDir: URL
    ) throws -> URL? {
        let titleSafe = safeFilename(title)
        let folderName = "\(titleSafe) (\(year)) [imdbid-\(imdbId)]"
        let destDir = libraryDir.appendingPathComponent(folderName)
        let destMKV = destDir.appendingPathComponent("\(folderName).mkv")

        if FileManager.default.fileExists(atPath: destMKV.path) {
            AppLogger.error("Destination already exists — refusing to overwrite: \(destMKV.path)")
            Notifier.notify(
                title: "Rip Pipeline ⚠️",
                message: "\(title) (\(year))",
                subtitle: "Already exists in library — left un-moved, needs manual review"
            )
            return nil
        }

        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        AppLogger.info("Moving MKV → \(destMKV.path)")
        try FileManager.default.moveItem(at: srcURL, to: destMKV)

        AppLogger.info("Done: \(destDir.path)")
        return destMKV
    }

    public static func moveToTVLibrary(
        srcURL: URL,
        seriesTitle: String,
        seriesYear: String,
        seriesImdbId: String,
        season: Int,
        episode: Int,
        episodeTitle: String,
        tvLibraryDir: URL
    ) throws -> URL? {
        let seriesSafe = safeFilename(seriesTitle)
        let seriesFolder = "\(seriesSafe) (\(seriesYear)) [imdbid-\(seriesImdbId)]"
        let seasonFolder = String(format: "Season %02d", season)
        let fileName = String(format: "%@ S%02dE%02d %@.mkv", seriesSafe, season, episode, safeFilename(episodeTitle))

        let destDir = tvLibraryDir
            .appendingPathComponent(seriesFolder)
            .appendingPathComponent(seasonFolder)
        let destMKV = destDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destMKV.path) {
            AppLogger.error("Destination already exists — refusing to overwrite: \(destMKV.path)")
            Notifier.notify(
                title: "Rip Pipeline ⚠️",
                message: String(format: "%@ S%02dE%02d", seriesTitle, season, episode),
                subtitle: "Already exists in library — left un-moved, needs manual review"
            )
            return nil
        }

        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        AppLogger.info("Moving MKV → \(destMKV.path)")
        try FileManager.default.moveItem(at: srcURL, to: destMKV)

        AppLogger.info("Done: \(destDir.path)")
        return destMKV
    }
}
