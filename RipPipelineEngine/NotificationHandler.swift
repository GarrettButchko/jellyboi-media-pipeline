import Foundation
import UserNotifications

public protocol NotificationHandler: Sendable {
    func notify(title: String, message: String, subtitle: String?) async
}

/// Standard macOS Notification Center handler (publish-safe, App Store & Notarization compliant)
public struct AppUserNotificationHandler: NotificationHandler {
    public static let shared = AppUserNotificationHandler()

    public init() {}

    public func requestAuthorization() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func notify(title: String, message: String, subtitle: String? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = title
        if let sub = subtitle {
            content.subtitle = sub
        }
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Fallback notification handler for CLI environments
public struct CLINotificationHandler: NotificationHandler {
    public static let shared = CLINotificationHandler()

    public init() {}

    public func notify(title: String, message: String, subtitle: String? = nil) async {
        let subStr = subtitle != nil ? " (\(subtitle!))" : ""
        Logger.info("[Notification] \(title): \(message)\(subStr)")
    }
}
