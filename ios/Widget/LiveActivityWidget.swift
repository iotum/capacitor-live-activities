import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget { LiveActivityWidget() }
}

@available(iOSApplicationExtension 16.2, *)
struct LiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            ActivityPanel(state: context.state)
                .padding(12)
                .activityBackgroundTint(Color(red: 0.094, green: 0.110, blue: 0.125))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(activityURL(context.state.display?.url))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityIcon(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityIndicator(state: context.state, selection: "timer", iconFallback: false)
                        .frame(maxWidth: 72)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityPanel(state: context.state, showTitle: false)
                }
            } compactLeading: {
                ActivityIcon(state: context.state)
            } compactTrailing: {
                ActivityIndicator(state: context.state, selection: context.state.display?.profiles.compact.indicator ?? "icon")
                    .frame(maxWidth: 52)
            } minimal: {
                ActivityIndicator(state: context.state, selection: context.state.display?.profiles.minimal.indicator ?? "icon")
            }
            .keylineTint(activityAccent(context.state.display?.phase))
            .widgetURL(activityURL(context.state.display?.url))
        }
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityPanel: View {
    let state: LiveActivityAttributes.ContentState
    var showTitle = true

    var body: some View {
        let display = state.display.flatMap { $0.supported ? $0 : nil }
        let itemCount = display?.selectedItems.count ?? 0
        let actionCount = display?.selectedActions.count ?? 0
        ViewThatFits(in: .vertical) {
            ForEach(Array((0...itemCount).reversed()), id: \.self) { count in
                content(display, itemCount: count, actionCount: actionCount, subtitle: true)
            }
            if actionCount > 1 { content(display, itemCount: 0, actionCount: 1, subtitle: true) }
            content(display, itemCount: 0, actionCount: 0, subtitle: true)
            content(display, itemCount: 0, actionCount: 0, subtitle: false)
        }
        .frame(maxHeight: 160)
        .foregroundColor(.white)
    }

    private func content(_ display: LiveActivityDisplay?, itemCount: Int, actionCount: Int, subtitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showTitle, let header = display?.header {
                Text(header).font(.caption.weight(.medium)).opacity(0.75).lineLimit(1)
            }
            if showTitle {
                HStack(alignment: .top) {
                    ActivityIcon(state: state)
                    Text(state.title).font(.title3.weight(.bold)).lineLimit(1)
                    Spacer(minLength: 4)
                    ActivityIndicator(state: state, selection: "timer", iconFallback: false).frame(maxWidth: 72)
                }
            }
            if subtitle, display?.profiles.expanded.showSubtitle != false, let text = state.subtitle {
                Text(text).font(.caption).lineLimit(1).opacity(0.8)
            }
            if let status = display?.status {
                Text(status).font(.caption).lineLimit(1).foregroundColor(activityAccent(display?.phase))
            }
            if display?.template == "progress", let progress = state.progress {
                ProgressView(value: min(max(progress, 0), 1)).tint(activityAccent(display?.phase))
            }
            if let display = display {
                ForEach(Array(display.selectedItems.prefix(itemCount))) { item in
                    HStack {
                        if let badge = item.badge { Text(badge).bold().lineLimit(1) }
                        Text(item.label).lineLimit(1)
                        Spacer(minLength: 4)
                        if let value = item.value { Text(value).bold().lineLimit(1) }
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundColor(pillColor(item.color)?.foreground ?? .white)
                    .background(pillFill(item, phase: display.phase), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(pillColor(item.color)?.stroke ?? activityAccent(display.phase).opacity(item.selected == true ? 0.7 : 0), lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(item.selected == true ? .isSelected : [])
                }
                HStack(spacing: 12) {
                    ForEach(Array(display.selectedActions.prefix(actionCount))) { action in
                        if let url = activityURL(action.url) {
                            Link(destination: url) {
                                ActivityAction(action: action, accent: activityAccent(display.phase))
                            }
                        }
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityIcon: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        let symbols = ["call": "phone.fill", "info": "info.circle", "delivery": "shippingbox.fill", "check": "checkmark.circle.fill"]
        Image(systemName: symbols[state.display?.icon ?? "info"] ?? "info.circle")
            .foregroundColor(activityAccent(state.display?.phase))
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityIndicator: View {
    let state: LiveActivityAttributes.ContentState
    let selection: String
    // The card already shows the icon at its leading edge; the trailing slot stays empty until a timer exists.
    var iconFallback = true

    @ViewBuilder private var fallback: some View {
        if iconFallback { ActivityIcon(state: state) }
    }

    var body: some View {
        Group {
            if state.display?.supported != true {
                fallback
            } else if selection == "timer", let timer = state.display?.timer {
                if timer.mode == "elapsed", let start = timer.start {
                    Text(Date(timeIntervalSince1970: start), style: .timer)
                } else if timer.mode == "countdown", let end = timer.end {
                    Text(timerInterval: Date(timeIntervalSince1970: min(timer.start ?? Date().timeIntervalSince1970, end))...Date(timeIntervalSince1970: end), countsDown: true)
                } else if timer.mode == "frozen", let seconds = timer.seconds {
                    Text(String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60))
                } else {
                    fallback
                }
            } else if selection == "status", let status = state.display?.status {
                Text(status)
            } else if selection == "progress", let progress = state.progress {
                Text(min(max(progress, 0), 1), format: .percent.precision(.fractionLength(0)))
            } else {
                fallback
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .foregroundColor(activityAccent(state.display?.phase))
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityAction: View {
    let action: LiveActivityDisplay.Action
    let accent: Color

    var body: some View {
        let primary = action.emphasis == "primary"
        let destructive = action.emphasis == "destructive"
        let symbols = ["record": "person.crop.circle", "ticket": "ticket", "note": "square.and.pencil", "open": "arrow.up.right"]
        let tint = destructive ? Color(red: 1, green: 0.55, blue: 0.55) : accent
        HStack(spacing: 4) {
            if let icon = action.icon { Image(systemName: symbols[icon] ?? "arrow.up.right") }
            Text(action.label).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(primary && !destructive ? .black : (destructive ? tint : .white))
        .frame(maxWidth: .infinity, minHeight: 32)
        .padding(.horizontal, 8)
        .background(primary ? tint : tint.opacity(destructive ? 0.28 : 0.15), in: RoundedRectangle(cornerRadius: 6))
    }
}

private func activityAccent(_ phase: String?) -> Color {
    switch phase {
    case "ringing": return Color(red: 244 / 255.0, green: 201 / 255.0, blue: 93 / 255.0)
    case "connected": return Color(red: 101 / 255.0, green: 214 / 255.0, blue: 154 / 255.0)
    case "ended": return Color(red: 184 / 255.0, green: 192 / 255.0, blue: 204 / 255.0)
    default: return .white
    }
}

private struct PillColor {
    let fill: Color
    let stroke: Color
    let foreground: Color
}

// Accepts #RRGGBB or #RRGGBBAA; anything else falls back to the neutral pill.
private func pillColor(_ hex: String?) -> PillColor? {
    guard let hex = hex, hex.hasPrefix("#"), [7, 9].contains(hex.count),
          let value = UInt32(hex.dropFirst().prefix(6), radix: 16) else { return nil }
    let alpha = hex.count == 9 ? (UInt32(hex.suffix(2), radix: 16) ?? 255) : 255
    let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
    let a = Double(alpha) / 255
    // Text contrasts with the colour as blended on the dark card, so a faint tint keeps white text.
    let luminance = (0.299 * r + 0.587 * g + 0.114 * b) * a
    return PillColor(fill: Color(red: r, green: g, blue: b).opacity(a),
                     stroke: Color(red: r, green: g, blue: b).opacity(min(1, a + 0.3)),
                     foreground: luminance > 0.6 ? .black : .white)
}

private func pillFill(_ item: LiveActivityDisplay.Item, phase: String?) -> Color {
    pillColor(item.color)?.fill ?? activityAccent(phase).opacity(item.selected == true ? 0.25 : 0.1)
}

private func activityURL(_ value: String?) -> URL? {
    guard let value = value, let url = URL(string: value), url.scheme?.lowercased() == "https",
          url.host != nil, url.user == nil, url.password == nil else { return nil }
    return url
}