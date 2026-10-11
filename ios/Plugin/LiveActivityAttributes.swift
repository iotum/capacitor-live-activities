import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

// ---------------------------------------------------------------------------
// Generic JSON-driven ActivityAttributes
// ---------------------------------------------------------------------------
// Compiled into both the plugin and the host app's Widget Extension. Keep this
// file free of app-only APIs so the extension can include it verbatim.

@available(iOS 16.2, *)
public struct LiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var subtitle: String?
        public var progress: Double?
        public var icon: String?
        /// When set, the widget renders a live countdown using SwiftUI's
        /// timerInterval — no repeated update() calls needed from JS.
        public var timerEnd: Date?
        /// Start of the timer interval. Used to compute the progress ring fill.
        /// Defaults to the moment start() was called if omitted.
        public var timerStart: Date?
        /// Direction of the timer bar/ring. true = drain (default), false = fill.
        public var timerCountsDown: Bool?
        /// Hex color string for the activity background tint (e.g. "1a1a2e" or "#1a1a2e").
        public var backgroundColor: String?
        /// Hex color string for progress bars, rings and timer bar. Defaults to white.
        public var progressColor: String?
        /// Hex color string for title and subtitle text. Defaults to white.
        public var textColor: String?
        /// Hex color string for the SF Symbol icon. Defaults to white.
        public var iconColor: String?
        /// Hex color string for the expanded Dynamic Island keyline outline.
        public var keylineTint: String?
        /// Thickness in points of the linear progress bar (2–20).
        public var progressBarHeight: Double?
        /// Corner radius in points of the linear progress bar.
        public var progressBarRadius: Double?
        public var display: LiveActivityDisplay?
        public var extras: [String: AnyCodable]

        public init(
            title: String,
            subtitle: String? = nil,
            progress: Double? = nil,
            icon: String? = nil,
            timerEnd: Date? = nil,
            timerStart: Date? = nil,
            timerCountsDown: Bool? = nil,
            backgroundColor: String? = nil,
            progressColor: String? = nil,
            textColor: String? = nil,
            iconColor: String? = nil,
            keylineTint: String? = nil,
            progressBarHeight: Double? = nil,
            progressBarRadius: Double? = nil,
            display: LiveActivityDisplay? = nil,
            extras: [String: AnyCodable] = [:]
        ) {
            self.title = title
            self.subtitle = subtitle
            self.progress = progress
            self.icon = icon
            self.timerEnd = timerEnd
            self.timerStart = timerStart
            self.timerCountsDown = timerCountsDown
            self.backgroundColor = backgroundColor
            self.progressColor = progressColor
            self.textColor = textColor
            self.iconColor = iconColor
            self.keylineTint = keylineTint
            self.progressBarHeight = progressBarHeight
            self.progressBarRadius = progressBarRadius
            self.display = display
            self.extras = extras
        }

        // APNs content-state payloads usually omit `extras`; don't fail decoding.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
            progress = try c.decodeIfPresent(Double.self, forKey: .progress)
            icon = try c.decodeIfPresent(String.self, forKey: .icon)
            timerEnd = try c.decodeIfPresent(Date.self, forKey: .timerEnd)
            timerStart = try c.decodeIfPresent(Date.self, forKey: .timerStart)
            timerCountsDown = try c.decodeIfPresent(Bool.self, forKey: .timerCountsDown)
            backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor)
            progressColor = try c.decodeIfPresent(String.self, forKey: .progressColor)
            textColor = try c.decodeIfPresent(String.self, forKey: .textColor)
            iconColor = try c.decodeIfPresent(String.self, forKey: .iconColor)
            keylineTint = try c.decodeIfPresent(String.self, forKey: .keylineTint)
            progressBarHeight = try c.decodeIfPresent(Double.self, forKey: .progressBarHeight)
            progressBarRadius = try c.decodeIfPresent(Double.self, forKey: .progressBarRadius)
            display = try? c.decodeIfPresent(LiveActivityDisplay.self, forKey: .display)
            extras = try c.decodeIfPresent([String: AnyCodable].self, forKey: .extras) ?? [:]
        }
    }

    public var activityType: String
    public var staticData: [String: AnyCodable]

    public init(activityType: String, staticData: [String: AnyCodable] = [:]) {
        self.activityType = activityType
        self.staticData = staticData
    }

    // Push-to-start `attributes` payloads usually omit `staticData`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activityType = try c.decode(String.self, forKey: .activityType)
        staticData = try c.decodeIfPresent([String: AnyCodable].self, forKey: .staticData) ?? [:]
    }
}

// ---------------------------------------------------------------------------
// AnyCodable — lightweight wrapper so we can store arbitrary JSON in Codable
// ---------------------------------------------------------------------------

public struct LiveActivityDisplay: Codable, Hashable {
    public var version: Int
    public var template: String
    public var status: String?
    public var icon: String?
    public var url: String?
    public var timer: Timer?
    public var phase: String?
    public var header: String?
    public var items: [Item]
    public var actions: [Action]
    public var profiles: Profiles

    public var supported: Bool { version == 2 && ["summary", "progress"].contains(template) }

    public var selectedItems: [Item] {
        profiles.expanded.itemIds.prefix(3).compactMap { id in items.first { $0.id == id } }
    }

    public var selectedActions: [Action] {
        profiles.expanded.actionIds.prefix(2).compactMap { id in actions.first { $0.id == id } }
    }

    public struct Timer: Codable, Hashable {
        public var mode: String
        public var start: Double?
        public var end: Double?
        public var seconds: Double?
    }

    public struct Profiles: Codable, Hashable {
        public var minimal: Indicator
        public var compact: Indicator
        public var expanded: Expanded
    }

    public struct Indicator: Codable, Hashable {
        public var indicator: String
    }

    public struct Expanded: Codable, Hashable {
        public var itemIds: [String]
        public var actionIds: [String]
        public var showSubtitle: Bool
    }

    public struct Item: Codable, Hashable, Identifiable {
        public var id: String
        public var kind: String
        public var label: String
        public var value: String?
        public var badge: String?
        public var selected: Bool?
    }

    public struct Action: Codable, Hashable, Identifiable {
        public var id: String
        public var label: String
        public var url: String
        public var icon: String?
        public var emphasis: String?
    }
}

public struct AnyCodable: Codable, Hashable {
    public let value: Any

    public init(_ value: Any) {
        switch value {
        case let dictionary as [String: Any]:
            self.value = dictionary.mapValues { AnyCodable($0) }
        case let array as [Any]:
            self.value = array.map { AnyCodable($0) }
        default:
            self.value = value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)   { value = v; return }
        if let v = try? container.decode(Int.self)    { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        if let v = try? container.decode(String.self) { value = v; return }
        if let v = try? container.decode([String: AnyCodable].self) { value = v; return }
        if let v = try? container.decode([AnyCodable].self) { value = v; return }
        value = NSNull()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:                    try container.encode(v)
        case let v as Int:                     try container.encode(v)
        case let v as Double:                  try container.encode(v)
        case let v as String:                  try container.encode(v)
        case let v as [String: AnyCodable]:    try container.encode(v)
        case let v as [AnyCodable]:            try container.encode(v)
        default:                               try container.encodeNil()
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple equality for Hashable conformance
        "\(lhs.value)" == "\(rhs.value)"
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine("\(value)")
    }
}
