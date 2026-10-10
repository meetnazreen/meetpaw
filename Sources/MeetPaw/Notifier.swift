import Foundation
import UserNotifications
import AppKit

/// Local notifications firing ~1 minute before each upcoming meeting.
/// Tapping one opens the Meet link.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var center: UNUserNotificationCenter? { .current() }

    func start() {
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Replaces all pending reminders with ones for the given meetings.
    func schedule(_ meetings: [CalendarEvent]) {
        guard let center else { return }
        center.removeAllPendingNotificationRequests()
        let leadMinutes = 15
        for event in meetings {
            guard let start = event.startDate,
                  let url = event.openURL else { continue }
            let fireAt = start.addingTimeInterval(TimeInterval(-leadMinutes * 60))
            guard fireAt > Date() else { continue }   // less than 15 min away / started

            let content = UNMutableNotificationContent()
            content.title = event.summary ?? "Upcoming meeting"
            content.body = "Starts in \(leadMinutes) minutes · tap to \(event.hasMeet ? "join" : "open")"
            content.sound = .default
            content.userInfo = ["url": url.absoluteString]

            let interval = fireAt.timeIntervalSinceNow
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: event.id, content: content, trigger: trigger))
        }
    }

    // Tap → open the Meet link.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }

    // Show even when the app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
