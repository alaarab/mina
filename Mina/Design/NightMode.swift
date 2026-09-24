import SwiftUI

/// A dark, slightly softened appearance for the hours when a bright screen is
/// most punishing. It never changes system brightness and can be turned off.
enum NightMode {
    static let key = "threeAMDimMode"
    static let startHour = 22
    static let endHour = 6

    static func isActive(at date: Date = .now, calendar: Calendar = .current, enabled: Bool) -> Bool {
        guard enabled else { return false }
        let hour = calendar.component(.hour, from: date)
        return hour >= startHour || hour < endHour
    }
}

private struct NightAppearance: ViewModifier {
    @AppStorage(NightMode.key, store: Prefs.defaults) private var enabled = true

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let active = NightMode.isActive(at: timeline.date, enabled: enabled)
            content
                .preferredColorScheme(active ? .dark : nil)
                .brightness(active ? -0.025 : 0)
        }
    }
}

extension View {
    func minaNightAppearance() -> some View { modifier(NightAppearance()) }
}
