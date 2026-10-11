import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveActivityWidget()
    }
}

@available(iOSApplicationExtension 16.2, *)
struct LiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            ActivityPanel(state: context.state)
                .padding(context.state.display?.header == nil ? 12 : 10)
                .frame(maxHeight: 160)
                .activityBackgroundTint(Color(hex: context.state.backgroundColor) ?? .black.opacity(0.85))
                .activitySystemActionForegroundColor(Color(hex: context.state.textColor) ?? .white)
                .widgetURL(activityURL(context.state.display?.url))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityIcon(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityStatus(state: context.state)
                        .foregroundColor(Color(hex: context.state.progressColor) ?? .white)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        if let subtitle = context.state.subtitle {
                            Text(subtitle).font(.caption).lineLimit(1)
                        }
                    }
                    .foregroundColor(Color(hex: context.state.textColor) ?? .white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Group {
                        if context.state.display?.version == 1 {
                            ActivityDetails(display: context.state.display, limit: 4)
                        } else {
                            ActivityProgress(state: context.state)
                        }
                    }
                    .foregroundColor(Color(hex: context.state.textColor) ?? .white)
                }
            } compactLeading: {
                ActivityIcon(state: context.state)
            } compactTrailing: {
                ActivityStatus(state: context.state)
                    .foregroundColor(Color(hex: context.state.progressColor) ?? .white)
                    .frame(maxWidth: 52)
            } minimal: {
                ActivityIcon(state: context.state)
            }
            .keylineTint(Color(hex: context.state.keylineTint))
            .widgetURL(activityURL(context.state.display?.url))
        }
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityPanel: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        if let display = state.display, display.version == 1, let header = display.header {
            ViewThatFits(in: .vertical) {
                ActivityCard(state: state, display: display, header: header, showSubtitle: true, showPills: true)
                ActivityCard(state: state, display: display, header: header, showSubtitle: true, showPills: false)
                ActivityCard(state: state, display: display, header: header, showSubtitle: false, showPills: false)
            }
            .foregroundColor(Color(hex: state.textColor) ?? .white)
        } else {
            standard
        }
    }

    private var standard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                ActivityIcon(state: state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.headline).lineLimit(1)
                    if let subtitle = state.subtitle {
                        Text(subtitle).font(.footnote).opacity(0.8).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                ActivityStatus(state: state)
            }
            if state.display?.version == 1 {
                ViewThatFits(in: .vertical) {
                    ActivityDetails(display: state.display, limit: 6)
                    ActivityDetails(display: state.display, limit: 4)
                    ActivityDetails(display: state.display, limit: 2)
                    ActivityDetails(display: state.display, limit: 0)
                }
            } else {
                ActivityProgress(state: state)
            }
        }
        .foregroundColor(Color(hex: state.textColor) ?? .white)
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityCard: View {
    let state: LiveActivityAttributes.ContentState
    let display: LiveActivityDisplay
    let header: String
    let showSubtitle: Bool
    let showPills: Bool

    var body: some View {
        let items = Array((display.sections.first?.items ?? []).prefix(3))
        // Only actions with a tappable URL are rendered, so the row never has dead buttons.
        let actions = display.actions.compactMap { action in
            activityURL(action.url).map { (action, $0) }
        }.prefix(2)
        VStack(alignment: .leading, spacing: 4) {
            Text(header).font(.caption.weight(.medium)).opacity(0.75).lineLimit(1)
            Text(state.title).font(.system(.title3, weight: .bold)).lineLimit(1)
            if showSubtitle, let subtitle = state.subtitle {
                Text(subtitle).font(.footnote).opacity(0.8).lineLimit(1)
            }
            if showPills && !items.isEmpty {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        if let url = activityURL(item.url) {
                            Link(destination: url) { ActivityPill(item: item, fill: false) }
                        } else {
                            ActivityPill(item: item, fill: false)
                        }
                    }
                }
            }
            if !actions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(actions), id: \.0.id) { action, url in
                        Link(destination: url) { ActivityButton(action: action) }
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityButton: View {
    let action: LiveActivityDisplay.Action

    var body: some View {
        let style = action.style ?? "default"
        let fill: Color = style == "primary" ? Color(red: 0.13, green: 0.65, blue: 0.35)
            : style == "destructive" ? Color.red.opacity(0.28)
            : Color.white.opacity(0.15)
        let text: Color = style == "primary" ? .white
            : style == "destructive" ? Color(red: 1, green: 0.55, blue: 0.55)
            : .white
        HStack(spacing: 4) {
            if let icon = action.icon { Image(systemName: icon) }
            Text(action.label)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(text)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(fill, in: Capsule())
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityIcon: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.icon ?? "info.circle")
            .foregroundColor(Color(hex: state.iconColor) ?? .white)
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityProgress: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        let tint = Color(hex: state.progressColor) ?? .white
        if let end = state.timerEnd {
            let start = min(state.timerStart ?? Date(), end)
            ProgressView(timerInterval: start...end, countsDown: state.timerCountsDown ?? true) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(tint)
        } else if let progress = state.progress {
            if let height = state.progressBarHeight {
                let clamped = min(max(height, 2), 20)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: state.progressBarRadius ?? clamped / 2).fill(tint.opacity(0.25))
                        RoundedRectangle(cornerRadius: state.progressBarRadius ?? clamped / 2).fill(tint)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: clamped)
            } else {
                ProgressView(value: min(max(progress, 0), 1)).tint(tint)
            }
        }
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityStatus: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        Group {
            if let status = state.display?.status {
                Text(status)
            } else if let end = state.timerEnd {
                Text(end, style: .timer)
            } else if let start = state.timerStart {
                Text(start, style: .timer)
            } else if let progress = state.progress {
                Text(progress, format: .percent.precision(.fractionLength(0)))
            }
        }
        .font(.footnote.weight(.medium).monospacedDigit())
        .lineLimit(1)
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityDetails: View {
    let display: LiveActivityDisplay?
    let limit: Int

    var body: some View {
        if let display = display, display.version == 1 {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(display.sections.prefix(2).enumerated()), id: \.element.id) { sectionIndex, section in
                    let preceding = display.sections.prefix(sectionIndex).reduce(0) { $0 + $1.items.count }
                    let available = max(0, limit - preceding)
                    if available > 0 && !section.items.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach(Array(section.items.prefix(available))) { item in
                                if let url = activityURL(item.url) {
                                    Link(destination: url) { ActivityPill(item: item) }
                                } else {
                                    ActivityPill(item: item)
                                }
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(section.title ?? section.id)
                    }
                }
                HStack(spacing: 12) {
                    ForEach(Array(display.actions.prefix(2))) { action in
                        if let url = activityURL(action.url) {
                            Link(destination: url) {
                                Label(action.label, systemImage: action.icon ?? "arrow.up.right")
                                    .lineLimit(1)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    if display.sections.reduce(0, { $0 + $1.items.count }) > limit,
                       let url = activityURL(display.url) {
                        Link("Open", destination: url).lineLimit(1)
                    }
                }
                .font(.caption)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityPill: View {
    let item: LiveActivityDisplay.Item
    var fill: Bool = true

    var body: some View {
        let tint = Color(hex: item.color)
        let selected = item.selected == true
        let fillOpacity = selected ? 0.3 : (tint != nil ? 0.2 : 0.12)
        let strokeOpacity = selected ? 0.7 : (tint != nil ? 0.4 : 0)
        HStack(spacing: 4) {
            if let badge = item.badge {
                Text(badge).bold().lineLimit(1)
            }
            Text(item.label).lineLimit(1)
            if let value = item.value {
                Text(value).bold().lineLimit(1)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
        .background((tint ?? .white).opacity(fillOpacity), in: Capsule())
        .overlay(Capsule().strokeBorder((tint ?? .white).opacity(strokeOpacity), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.badge, item.label, item.value].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(item.selected == true ? [.isSelected] : [])
    }
}

private func activityURL(_ value: String?) -> URL? {
    guard let value = value, let url = URL(string: value),
          let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
          url.host != nil else { return nil }
    return url
}

private extension Color {
    init?(hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        // Shorthand #RGB / #RGBA expands each digit; 8 digits are #RRGGBBAA.
        if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: hasAlpha ? Double(value & 0xFF) / 255 : 1
        )
    }
}