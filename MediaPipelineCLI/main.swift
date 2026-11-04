import Foundation
import LoggingKit

struct RipPipelineMain {
    static func run() async {
        let args = ProcessInfo.processInfo.arguments

        var targetPath: String? = nil
        var outputDirOverride: URL? = nil
        var forceSubs = false
        var isVerbose = false

        var i = 1
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--help", "-h":
                printUsage()
                return
            case "--force-subs":
                forceSubs = true
            case "--verbose", "-v":
                isVerbose = true
            case "--output", "-o":
                i += 1
                if i < args.count {
                    outputDirOverride = URL(fileURLWithPath: (args[i] as NSString).expandingTildeInPath)
                }
            default:
                if !arg.hasPrefix("-") && targetPath == nil {
                    targetPath = arg
                }
            }
            i += 1
        }

        if isVerbose {
            AppLogger.minimumLevel = .debug
        }

        let config = PipelineConfig.load()
        let pipeline = Pipeline(config: config)
        pipeline.toolRegistry.logDiagnostics()

        let targetURL: URL
        if let targetPath = targetPath {
            targetURL = URL(fileURLWithPath: (targetPath as NSString).expandingTildeInPath)
        } else {
            targetURL = config.watchDir
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            AppLogger.error("Path does not exist: \(targetURL.path)")
            return
        }

        if isDir.boolValue {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: nil) else {
                AppLogger.info("No files found in \(targetURL.path)")
                return
            }

            // Clean MKV filtering: ignore dot files, AppleDouble files, and intermediate temporary files
            let mkvFiles = contents
                .filter { url in
                    let name = url.lastPathComponent
                    guard url.pathExtension.lowercased() == "mkv" else { return false }
                    guard !name.hasPrefix(".") && !name.hasPrefix("._") else { return false }
                    guard !name.contains(".stripping.") && !name.contains(".tmp.") else { return false }
                    return true
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !mkvFiles.isEmpty else {
                AppLogger.info("No MKV files found in \(targetURL.path)")
                return
            }

            AppLogger.info("Batch mode: \(mkvFiles.count) MKV file(s) in \(targetURL.path)")
            for mkv in mkvFiles {
                await pipeline.process(fileURL: mkv, outputDir: outputDirOverride, forceSubs: forceSubs)
            }
        } else {
            let name = targetURL.lastPathComponent
            if targetURL.pathExtension.lowercased() != "mkv" || name.hasPrefix(".") || name.hasPrefix("._") {
                AppLogger.info("Skipping non-MKV file: \(name)")
                return
            }
            await pipeline.process(fileURL: targetURL, outputDir: outputDirOverride, forceSubs: forceSubs)
        }
    }

    static func printUsage() {
        print("""
        Usage: MediaPipelineCLI [options] [path]

        Arguments:
          path                     MKV file or directory to process (defaults to watch_dir in config)

        Options:
          -o, --output <dir>       Override destination library directory
          --force-subs             Always check OpenSubtitles even if English SubRip subtitle is embedded
          -v, --verbose            Enable verbose debug logging
          -h, --help               Show this help message
        """)
    }
}

await RipPipelineMain.run()
