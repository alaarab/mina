import ActivityKit
import Foundation

/// Shared by the app that starts the activity and the widget extension that
/// draws it. All changing values live in `ContentState`.
struct CareTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var detail: String
    }

    let entryID: UUID
    let babyName: String
    /// `EntryKind.rawValue`; kept as a string so the activity payload stays
    /// independent of Core Data.
    let kind: String
}
