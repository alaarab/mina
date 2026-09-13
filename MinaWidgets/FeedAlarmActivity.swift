import SwiftUI
import WidgetKit
#if canImport(AlarmKit)
import AlarmKit
import ActivityKit

/// Lock-screen and Dynamic Island face of a snoozed feed alarm.
@available(iOS 26.0, *)
struct FeedAlarmActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<FeedAlarmMetadata>.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "waterbottle.fill").font(.title2).foregroundStyle(MinaTheme.bottle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.attributes.metadata?.babyName ?? "Baby")'s feed").font(.headline)
                    if case .countdown(let countdown) = context.state.mode {
                        Text(timerInterval: Date.now...countdown.fireDate, countsDown: true).font(.subheadline).monospacedDigit()
                    } else {
                        Text("Time to feed").font(.subheadline)
                    }
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(MinaTheme.card)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "waterbottle.fill").foregroundStyle(MinaTheme.bottle) }
                DynamicIslandExpandedRegion(.center) { Text("\(context.attributes.metadata?.babyName ?? "Baby")'s feed") }
                DynamicIslandExpandedRegion(.trailing) {
                    if case .countdown(let countdown) = context.state.mode {
                        Text(timerInterval: Date.now...countdown.fireDate, countsDown: true).monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: "waterbottle.fill").foregroundStyle(MinaTheme.bottle)
            } compactTrailing: {
                if case .countdown(let countdown) = context.state.mode {
                    Text(timerInterval: Date.now...countdown.fireDate, countsDown: true).monospacedDigit().frame(width: 44)
                }
            } minimal: {
                Image(systemName: "waterbottle.fill").foregroundStyle(MinaTheme.bottle)
            }
        }
    }
}
#endif
