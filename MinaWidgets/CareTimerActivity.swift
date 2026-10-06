import ActivityKit
import SwiftUI
import WidgetKit

/// Lock-screen and Dynamic Island timer for an ongoing nursing session or nap.
struct CareTimerActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CareTimerAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: symbol(context.attributes.kind))
                    .font(.title2)
                    .foregroundStyle(color(context.attributes.kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.isStale ? "Open Mina to check this timer" : title(context.attributes.kind, babyName: context.attributes.babyName)).font(.headline)
                    Text(timerInterval: context.state.startedAt...context.state.startedAt.addingTimeInterval(8 * 60 * 60), countsDown: false)
                        .font(.subheadline).monospacedDigit()
                    Text(context.state.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(MinaTheme.card)
            .privacySensitive()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol(context.attributes.kind)).foregroundStyle(color(context.attributes.kind))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(title(context.attributes.kind, babyName: context.attributes.babyName))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...context.state.startedAt.addingTimeInterval(8 * 60 * 60), countsDown: false).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detail).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: symbol(context.attributes.kind)).foregroundStyle(color(context.attributes.kind))
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "clock.badge.questionmark")
                } else {
                    Text(timerInterval: context.state.startedAt...context.state.startedAt.addingTimeInterval(8 * 60 * 60), countsDown: false, showsHours: true)
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7).frame(width: 56)
                }
            } minimal: {
                Image(systemName: symbol(context.attributes.kind)).foregroundStyle(color(context.attributes.kind))
            }
            .keylineTint(color(context.attributes.kind))
        }
    }

    private func symbol(_ kind: String) -> String { kind == EntryKind.nursing.rawValue ? "heart.fill" : "moon.zzz.fill" }
    private func color(_ kind: String) -> Color { kind == EntryKind.nursing.rawValue ? MinaTheme.nursing : MinaTheme.sleep }
    private func title(_ kind: String, babyName: String) -> String { kind == EntryKind.nursing.rawValue ? "Nursing \(babyName)" : "\(babyName) is asleep" }
}
