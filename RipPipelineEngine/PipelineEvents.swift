import Foundation

/// Defines all lifecycle stages of media disc rip processing
public enum PipelineStage: String, CaseIterable, Sendable {
    case queued = "Queued"
    case waitingForWrite = "Waiting for Write"
    case awaitingTitle = "Awaiting Title"
    case detectingSource = "Detecting Source"
    case extractingMetadata = "Extracting Metadata"
    case matchingMetadata = "Matching with IMDb"
    case detectingCrop = "Detecting Crop"
    case processingSubtitles = "Processing Subtitles"
    case remuxingTracks = "Remuxing Tracks"
    case applyingCrop = "Applying Crop"
    case movingToLibrary = "Moving to Library"
    case completed = "Completed"
    case failed = "Failed"

    public var systemImageName: String {
        switch self {
        case .queued: return "clock"
        case .waitingForWrite: return "hourglass"
        case .awaitingTitle: return "pencil.and.outline"
        case .detectingSource: return "opticaldisc"
        case .extractingMetadata: return "doc.text.magnifyingglass"
        case .matchingMetadata: return "film"
        case .detectingCrop: return "crop"
        case .processingSubtitles: return "captions.bubble"
        case .remuxingTracks: return "slider.horizontal.3"
        case .applyingCrop: return "aspectratio"
        case .movingToLibrary: return "folder"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

/// A structured progress event emitted during pipeline operations
public struct PipelineProgressUpdate: Sendable, Identifiable {
    public let id: UUID
    public let fileURL: URL
    public let destinationURL: URL?
    public let fileName: String
    public let stage: PipelineStage
    public let progressFraction: Double?
    public let detail: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        destinationURL: URL? = nil,
        stage: PipelineStage,
        progressFraction: Double? = nil,
        detail: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.destinationURL = destinationURL
        self.fileName = fileURL.lastPathComponent
        self.stage = stage
        self.progressFraction = progressFraction
        self.detail = detail
        self.timestamp = timestamp
    }
}

/// Protocol implemented by CLI runners, SwiftUI ViewModels, or automation listeners
public protocol PipelineDelegate: AnyObject, Sendable {
    func pipelineDidUpdateProgress(_ update: PipelineProgressUpdate) async
    func pipelineDidLog(level: LogLevel, message: String) async
}
