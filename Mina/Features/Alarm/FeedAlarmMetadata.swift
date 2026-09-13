import Foundation
#if canImport(AlarmKit)
import AlarmKit

/// What the alarm carries; shared with the widget so it can draw the countdown.
@available(iOS 26.0, *)
struct FeedAlarmMetadata: AlarmMetadata {
    var babyName: String
    var lastFeedAt: Date?
}
#endif
