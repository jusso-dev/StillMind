import Foundation
import UserNotifications
import os

/// Manages daily journal reminder notifications using UNUserNotificationCenter.
///
/// Schedules a repeating local notification at a user-configured time (default 10 AM).
/// When the user records an entry, the pending notification for that day can be
/// dismissed so they aren't reminded unnecessarily.
final class NotificationService: @unchecked Sendable {
    static let dailyReminderIdentifier = "com.stillmind.daily-reminder"

    private let logger = Logger(subsystem: "com.au.yarndigi.StillMind", category: "Notifications")
    private let center = UNUserNotificationCenter.current()

    // UserDefaults keys
    private static let enabledKey = "dailyReminderEnabled"
    private static let hourKey = "dailyReminderHour"
    private static let minuteKey = "dailyReminderMinute"

    // MARK: - Configuration

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                scheduleDailyReminder()
            } else {
                cancelDailyReminder()
            }
        }
    }

    /// The hour component of the reminder time (0-23). Defaults to 10 (10 AM).
    var reminderHour: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: Self.hourKey)
            // UserDefaults returns 0 for missing keys; distinguish via registration
            if UserDefaults.standard.object(forKey: Self.hourKey) == nil { return 10 }
            return value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.hourKey)
            if isEnabled { scheduleDailyReminder() }
        }
    }

    /// The minute component of the reminder time (0-59). Defaults to 0.
    var reminderMinute: Int {
        get { UserDefaults.standard.integer(forKey: Self.minuteKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.minuteKey)
            if isEnabled { scheduleDailyReminder() }
        }
    }

    /// Combined Date representing just the time-of-day for the reminder.
    var reminderTime: Date {
        get {
            var components = DateComponents()
            components.hour = reminderHour
            components.minute = reminderMinute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = components.hour ?? 10
            reminderMinute = components.minute ?? 0
        }
    }

    // MARK: - Reminder Messages

    private static let reminderMessages = [
        "Take a moment to reflect. Your voice journal is ready.",
        "How was your day? Capture your thoughts with a quick recording.",
        "A few seconds of reflection can make a big difference. Record a voice entry.",
        "Your future self will thank you. Take a moment to journal today.",
        "Pause and reflect — what's on your mind right now?",
        "Haven't journaled today yet. Even a short entry counts!",
        "Check in with yourself. How are you feeling right now?",
        "A quick voice note today keeps your reflection streak alive.",
        "What happened today that's worth remembering? Record it now.",
        "Your journal is waiting. Take 30 seconds to capture your thoughts."
    ]

    // MARK: - Permission

    /// Request notification permission from the user. Returns whether permission was granted.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                logger.info("Notification permission granted")
            } else {
                logger.info("Notification permission denied")
            }
            return granted
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }

    /// Check current authorization status.
    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    // MARK: - Scheduling

    /// Schedule (or reschedule) the daily reminder notification.
    func scheduleDailyReminder() {
        // Remove any existing reminder first
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "StillMind"
        content.body = Self.reminderMessages.randomElement() ?? Self.reminderMessages[0]
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: Self.dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule daily reminder: \(error.localizedDescription)")
            } else {
                logger.info("Daily reminder scheduled for \(dateComponents.hour ?? 0):\(String(format: "%02d", dateComponents.minute ?? 0))")
            }
        }
    }

    /// Cancel the daily reminder notification.
    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.dailyReminderIdentifier])
        logger.info("Daily reminder cancelled")
    }

    /// Call when the user records a new entry to dismiss any delivered reminder for today.
    func dismissTodayReminder() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.dailyReminderIdentifier])
    }
}
