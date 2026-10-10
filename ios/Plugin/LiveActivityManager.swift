import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

// ---------------------------------------------------------------------------
// LiveActivityManager
// ---------------------------------------------------------------------------

@available(iOS 16.2, *)
public class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    // activityId → Activity<LiveActivityAttributes>
    private var activities: [String: Activity<LiveActivityAttributes>] = [:]
    // activity.pushToken can stay nil (e.g. push-started activities) even after pushTokenUpdates emits.
    private var pushTokens: [String: String] = [:]
    private let lock = NSLock()
    private var isObservingActivities = false

    // Latest push-to-start token (iOS 17.2+), cached as it rotates.
    private var pushToStartToken: String?
    private var isObservingPushToStart = false

    // MARK: - isSupported

    func isSupported() -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Push-to-start token (iOS 17.2+)

    /// Begins observing the type-level push-to-start token. Call once at app
    /// launch. The token lets your server START a Live Activity remotely,
    /// without the app having called `start()` first.
    func startObservingPushToStartToken() {
        guard !isObservingPushToStart else { return }
        isObservingPushToStart = true

        if #available(iOS 17.2, *) {
            Task {
                for await tokenData in Activity<LiveActivityAttributes>.pushToStartTokenUpdates {
                    let token = tokenData.map { String(format: "%02x", $0) }.joined()
                    self.pushToStartToken = token
                    NotificationCenter.default.post(
                        name: .liveActivityPushToStartTokenUpdated,
                        object: nil,
                        userInfo: ["token": token, "type": "apns"]
                    )
                }
            }
        }
    }

    /// Returns the latest cached push-to-start token, or nil if not yet issued
    /// or unsupported (< iOS 17.2). Listen to `pushToStartTokenUpdated` for the
    /// value as soon as the system issues it.
    func getPushToStartToken() -> String? {
        pushToStartToken
    }

    // MARK: - Activity tracking

    /// Adopts activities that survived an app relaunch and ones started remotely
    /// via push-to-start, so update()/end()/getPushToken() and token events
    /// work for them too. Call once at app launch.
    func startObservingActivities() {
        guard !isObservingActivities else { return }
        isObservingActivities = true

        Activity<LiveActivityAttributes>.activities.forEach { track($0) }
        Task {
            for await activity in Activity<LiveActivityAttributes>.activityUpdates {
                self.track(activity)
            }
        }
    }

    private func activity(for id: String) -> Activity<LiveActivityAttributes>? {
        lock.lock(); defer { lock.unlock() }
        return activities[id] ?? Activity<LiveActivityAttributes>.activities.first { $0.id == id }
    }

    private func forget(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        activities.removeValue(forKey: id)
        pushTokens.removeValue(forKey: id)
    }

    private func pushTokenString(for activity: Activity<LiveActivityAttributes>) -> String? {
        if let tokenData = activity.pushToken {
            return tokenData.map { String(format: "%02x", $0) }.joined()
        }
        lock.lock(); defer { lock.unlock() }
        return pushTokens[activity.id]
    }

    private func track(_ activity: Activity<LiveActivityAttributes>) {
        let activityId = activity.id
        lock.lock()
        let isNew = activities[activityId] == nil
        activities[activityId] = activity
        lock.unlock()
        guard isNew else { return }

        // Observe state changes and forward them as Capacitor events
        Task {
            for await stateUpdate in activity.activityStateUpdates {
                NotificationCenter.default.post(
                    name: .liveActivityStateChanged,
                    object: nil,
                    userInfo: [
                        "activityId": activityId,
                        "activityState": stateUpdate.rawStateString
                    ]
                )
                if stateUpdate == .ended || stateUpdate == .dismissed {
                    self.forget(activityId)
                }
            }
        }

        // Observe push token changes (issued on first request, may rotate)
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                self.lock.lock()
                self.pushTokens[activityId] = token
                self.lock.unlock()
                NotificationCenter.default.post(
                    name: .liveActivityPushTokenUpdated,
                    object: nil,
                    userInfo: [
                        "activityId": activityId,
                        "token": token,
                        "type": "apns"
                    ]
                )
            }
        }
    }

    // MARK: - areActivitiesEnabled

    func areActivitiesEnabled() -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - start

    func start(
        attributes: [String: Any],
        state: [String: Any],
        staleAfterSeconds: Double?
    ) throws -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.activitiesDisabled
        }

        let activityType = attributes["activityType"] as? String ?? "unknown"
        var staticData: [String: AnyCodable] = [:]
        for (k, v) in attributes where k != "activityType" {
            staticData[k] = AnyCodable(v)
        }

        let contentState = try buildContentState(from: state)
        let activityAttributes = LiveActivityAttributes(
            activityType: activityType,
            staticData: staticData
        )

        var staleDate: Date? = nil
        if let seconds = staleAfterSeconds, seconds > 0 {
            staleDate = Date().addingTimeInterval(seconds)
        }

        // pushType .token makes ActivityKit issue a per-activity APNs token for server updates.
        let activity = try Activity<LiveActivityAttributes>.request(
            attributes: activityAttributes,
            content: ActivityContent(state: contentState, staleDate: staleDate),
            pushType: .token
        )

        track(activity)
        return activity.id
    }

    // MARK: - update

    func update(
        activityId: String,
        state: [String: Any],
        alertTitle: String?,
        alertBody: String?
    ) async throws {
        guard let activity = activity(for: activityId) else {
            throw LiveActivityError.activityNotFound(activityId)
        }

        let contentState = try buildContentState(from: state)
        var alertConfig: AlertConfiguration? = nil

        if let title = alertTitle, let body = alertBody {
            alertConfig = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: title),
                body: LocalizedStringResource(stringLiteral: body),
                sound: .default
            )
        }

        await activity.update(
            ActivityContent(
                state: contentState,
                staleDate: nil
            ),
            alertConfiguration: alertConfig
        )
    }

    // MARK: - end

    func end(
        activityId: String,
        finalState: [String: Any]?,
        dismissalPolicy: String?
    ) async throws {
        guard let activity = activity(for: activityId) else {
            throw LiveActivityError.activityNotFound(activityId)
        }

        let policy: ActivityUIDismissalPolicy
        switch dismissalPolicy {
        case "immediate":    policy = .immediate
        case "after-delay":  policy = .after(.now + 30)
        default:             policy = .default
        }

        if let stateDict = finalState {
            let contentState = try buildContentState(from: stateDict)
            await activity.end(
                ActivityContent(state: contentState, staleDate: nil),
                dismissalPolicy: policy
            )
        } else {
            await activity.end(dismissalPolicy: policy)
        }

        forget(activityId)
    }

    // MARK: - getPushToken

    func getPushToken(activityId: String) -> String? {
        guard let activity = activity(for: activityId) else { return nil }
        return pushTokenString(for: activity)
    }

    // MARK: - getActiveActivities

    func getActiveActivities() -> [[String: String]] {
        Activity<LiveActivityAttributes>.activities.map { activity in
            var info = [
                "activityId": activity.id,
                "activityType": activity.attributes.activityType,
                "state": activity.activityState.rawStateString
            ]
            if let token = pushTokenString(for: activity) {
                info["pushToken"] = token
            }
            return info
        }
    }

    // MARK: - Helpers

    private func buildContentState(from dict: [String: Any]) throws -> LiveActivityAttributes.ContentState {
        guard let title = dict["title"] as? String else {
            throw LiveActivityError.missingField("title")
        }

        var extras: [String: AnyCodable] = [:]
        let reserved: Set<String> = [
            "title", "subtitle", "progress", "icon",
            "timerEnd", "timerStart", "timerCountsDown",
            "backgroundColor", "progressColor", "textColor", "iconColor",
            "keylineTint", "progressBarHeight", "progressBarRadius"
        ]
        for (k, v) in dict where !reserved.contains(k) {
            extras[k] = AnyCodable(v)
        }

        // Accept timerEnd / timerStart as Unix timestamps (seconds since epoch)
        var timerEnd: Date? = nil
        var timerStart: Date? = nil
        if let ts = dict["timerEnd"] as? Double { timerEnd = Date(timeIntervalSince1970: ts) }
        if let ts = dict["timerStart"] as? Double { timerStart = Date(timeIntervalSince1970: ts) }

        return LiveActivityAttributes.ContentState(
            title: title,
            subtitle: dict["subtitle"] as? String,
            progress: dict["progress"] as? Double,
            icon: dict["icon"] as? String,
            timerEnd: timerEnd,
            timerStart: timerStart,
            timerCountsDown: dict["timerCountsDown"] as? Bool,
            backgroundColor: dict["backgroundColor"] as? String,
            progressColor: dict["progressColor"] as? String,
            textColor: dict["textColor"] as? String,
            iconColor: dict["iconColor"] as? String,
            keylineTint: dict["keylineTint"] as? String,
            progressBarHeight: dict["progressBarHeight"] as? Double,
            progressBarRadius: dict["progressBarRadius"] as? Double,
            extras: extras
        )
    }
}

// MARK: - Helpers on ActivityState

@available(iOS 16.2, *)
private extension ActivityState {
    var rawStateString: String {
        switch self {
        case .active:    return "active"
        case .ended:     return "ended"
        case .dismissed: return "dismissed"
        @unknown default: return "active"
        }
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let liveActivityStateChanged    = Notification.Name("LiveActivityStateChanged")
    static let liveActivityPushTokenUpdated = Notification.Name("LiveActivityPushTokenUpdated")
    static let liveActivityPushToStartTokenUpdated = Notification.Name("LiveActivityPushToStartTokenUpdated")
}

// MARK: - Errors

enum LiveActivityError: LocalizedError {
    case activitiesDisabled
    case activityNotFound(String)
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .activitiesDisabled:        return "Live Activities are disabled for this app."
        case .activityNotFound(let id):  return "No active Live Activity found with id: \(id)"
        case .missingField(let field):   return "Required field missing from state: \(field)"
        }
    }
}
