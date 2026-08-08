import ActivityKit
import EventKit
import Flutter
import UIKit
import UserNotifications

@available(iOS 16.1, *)
struct NoteActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var status: String
  }

  var title: String
  var body: String
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let eventStore = EKEventStore()
  private var liveActivity: Any?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAppleServicesChannel(registry: engineBridge.pluginRegistry)
  }

  private func registerAppleServicesChannel(registry: FlutterPluginRegistry) {
    let registrar = registry.registrar(forPlugin: "AppleServicesPlugin")
    let channel = FlutterMethodChannel(
      name: "liquid_notes/apple_services",
      binaryMessenger: registrar.messenger()
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let arguments = call.arguments as? [String: Any] ?? [:]

      switch call.method {
      case "createCalendarEvent":
        self.createCalendarEvent(arguments: arguments, result: result)
      case "createReminder":
        self.createReminder(arguments: arguments, result: result)
      case "scheduleNotification":
        self.scheduleNotification(arguments: arguments, result: result)
      case "startLiveActivity":
        self.startLiveActivity(arguments: arguments, result: result)
      case "endLiveActivity":
        self.endLiveActivity(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func createCalendarEvent(arguments: [String: Any], result: @escaping FlutterResult) {
    requestEventAccess(entityType: .event) { [weak self] granted, error in
      guard let self else { return }
      if let error {
        result(self.flutterError("calendar_permission", error.localizedDescription))
        return
      }
      guard granted else {
        result(self.flutterError("calendar_denied", "Calendar access was not granted."))
        return
      }

      let event = EKEvent(eventStore: self.eventStore)
      event.title = self.string(arguments["title"], fallback: "Note")
      event.notes = self.string(arguments["body"], fallback: "")
      event.startDate = self.date(arguments["start"]) ?? Date().addingTimeInterval(3600)
      event.endDate = self.date(arguments["end"]) ?? event.startDate.addingTimeInterval(1800)
      event.calendar = self.eventStore.defaultCalendarForNewEvents

      do {
        try self.eventStore.save(event, span: .thisEvent)
        result("Added to Calendar.")
      } catch {
        result(self.flutterError("calendar_save_failed", error.localizedDescription))
      }
    }
  }

  private func createReminder(arguments: [String: Any], result: @escaping FlutterResult) {
    requestEventAccess(entityType: .reminder) { [weak self] granted, error in
      guard let self else { return }
      if let error {
        result(self.flutterError("reminder_permission", error.localizedDescription))
        return
      }
      guard granted else {
        result(self.flutterError("reminder_denied", "Reminders access was not granted."))
        return
      }

      let reminder = EKReminder(eventStore: self.eventStore)
      reminder.title = self.string(arguments["title"], fallback: "Note")
      reminder.notes = self.string(arguments["body"], fallback: "")
      reminder.calendar = self.eventStore.defaultCalendarForNewReminders()
      if let dueDate = self.date(arguments["due"]) {
        reminder.dueDateComponents = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute],
          from: dueDate
        )
      }

      do {
        try self.eventStore.save(reminder, commit: true)
        result("Added to Reminders.")
      } catch {
        result(self.flutterError("reminder_save_failed", error.localizedDescription))
      }
    }
  }

  private func scheduleNotification(arguments: [String: Any], result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      [weak self] granted, error in
      guard let self else { return }
      if let error {
        result(self.flutterError("notification_permission", error.localizedDescription))
        return
      }
      guard granted else {
        result(self.flutterError("notification_denied", "Notification access was not granted."))
        return
      }

      let content = UNMutableNotificationContent()
      content.title = self.string(arguments["title"], fallback: "Note")
      content.body = self.string(arguments["body"], fallback: "Open this note.")
      content.sound = .default

      let fireAt = self.date(arguments["fireAt"]) ?? Date().addingTimeInterval(300)
      let interval = max(fireAt.timeIntervalSinceNow, 5)
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
      let id = self.string(arguments["id"], fallback: UUID().uuidString)
      let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

      UNUserNotificationCenter.current().add(request) { error in
        if let error {
          result(self.flutterError("notification_schedule_failed", error.localizedDescription))
        } else {
          result("Notification scheduled.")
        }
      }
    }
  }

  private func startLiveActivity(arguments: [String: Any], result: @escaping FlutterResult) {
    if #available(iOS 16.1, *) {
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        result(flutterError("live_activity_disabled", "Live Activities are disabled."))
        return
      }

      let attributes = NoteActivityAttributes(
        title: string(arguments["title"], fallback: "Note"),
        body: string(arguments["body"], fallback: "")
      )
      let state = NoteActivityAttributes.ContentState(status: "In progress")

      do {
        let activity = try Activity.request(
          attributes: attributes,
          contentState: state,
          pushType: nil
        )
        liveActivity = activity
        result("Live Activity started.")
      } catch {
        result(flutterError("live_activity_failed", error.localizedDescription))
      }
    } else {
      result(flutterError("live_activity_unavailable", "Live Activities require iOS 16.1 or later."))
    }
  }

  private func endLiveActivity(result: @escaping FlutterResult) {
    if #available(iOS 16.1, *) {
      Task {
        for activity in Activity<NoteActivityAttributes>.activities {
          await activity.end(
            using: NoteActivityAttributes.ContentState(status: "Complete"),
            dismissalPolicy: .immediate
          )
        }
        DispatchQueue.main.async {
          self.liveActivity = nil
          result("Live Activity ended.")
        }
      }
    } else {
      result(flutterError("live_activity_unavailable", "Live Activities require iOS 16.1 or later."))
    }
  }

  private func requestEventAccess(
    entityType: EKEntityType,
    completion: @escaping (Bool, Error?) -> Void
  ) {
    if #available(iOS 17.0, *) {
      switch entityType {
      case .event:
        eventStore.requestFullAccessToEvents(completion: completion)
      case .reminder:
        eventStore.requestFullAccessToReminders(completion: completion)
      @unknown default:
        eventStore.requestAccess(to: entityType, completion: completion)
      }
    } else {
      eventStore.requestAccess(to: entityType, completion: completion)
    }
  }

  private func string(_ value: Any?, fallback: String) -> String {
    guard
      let value = value as? String,
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return fallback
    }
    return value
  }

  private func date(_ value: Any?) -> Date? {
    guard let value = value as? String else {
      return nil
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
      return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private func flutterError(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
