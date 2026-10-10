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
                .padding(12)
                .frame(maxHeight: 160)
                .activityBackgroundTint(.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(activityURL(context.state.display?.url))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.icon ?? "info.circle")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityStatus(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        if let subtitle = context.state.subtitle {
                            Text(subtitle).font(.caption).lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityDetails(display: context.state.display, limit: 4)
                }
            } compactLeading: {
                Image(systemName: context.state.icon ?? "info.circle")
            } compactTrailing: {
                ActivityStatus(state: context.state)
            } minimal: {
                Image(systemName: context.state.icon ?? "info.circle")
            }
            .widgetURL(activityURL(context.state.display?.url))
        }
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct ActivityPanel: View {
    let state: LiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: state.icon ?? "info.circle")
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.headline).lineLimit(1)
                    if let subtitle = state.subtitle {
                        Text(subtitle).font(.caption).lineLimit(1)
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
            } else if let progress = state.progress {
                ProgressView(value: min(max(progress, 0), 1))
            }
        }
        .foregroundStyle(.white)
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
        .font(.caption.monospacedDigit())
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

    var body: some View {
        HStack(spacing: 4) {
            if let badge = item.badge {
                Text(badge).bold().lineLimit(1)
            }
            Text(item.label).lineLimit(1)
            if let value = item.value {
                Text(value).bold().lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(item.selected == true ? 0.25 : 0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(item.selected == true ? 0.6 : 0), lineWidth: 1))
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