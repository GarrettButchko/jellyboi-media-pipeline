import Foundation

public enum LogLevel: String, Comparable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"

    private var order: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.order < rhs.order
    }
}

public final class Logger: @unchecked Sendable {
    public static var currentLevel: LogLevel = .info
    public static var notificationHandler: NotificationHandler = CLINotificationHandler.shared
    public static var logCallback: (@Sendable (LogLevel, String) -> Void)? = nil

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let lock = NSLock()

    public static func log(_ level: LogLevel, _ message: String) {
        guard level >= currentLevel else { return }

        let timeStr = dateFormatter.string(from: Date())
        let levelPadded = level.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
        let formatted = "\(timeStr)  \(levelPadded) \(message)"

        lock.lock()
        print(formatted)
        fflush(stdout)
        lock.unlock()

        logCallback?(level, formatted)
    }

    public static func debug(_ message: String) { log(.debug, message) }
    public static func info(_ message: String) { log(.info, message) }
    public static func warning(_ message: String) { log(.warning, message) }
    public static func error(_ message: String) { log(.error, message) }

    public static func notify(title: String, message: String, subtitle: String? = nil) {
        Task {
            await notificationHandler.notify(title: title, message: message, subtitle: subtitle)
        }
    }
}
