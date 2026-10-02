import CoreData
import Foundation
import UserNotifications

/// Planning dates for routine U.S. well-child care and the common childhood
/// immunization series. Sources are the AAP Bright Futures periodicity
/// schedule and CDC's parent schedule; the clinician remains authoritative.
/// https://www.aap.org/periodicityschedule
/// https://www.cdc.gov/vaccines-children/schedules/
enum CareSchedule {
    static let remindersKey = "careScheduleReminders"

    struct Item: Identifiable {
        let id: String
        let kind: EntryKind
        let title: String
        let detail: String
        let days: Int?
        let months: Int?

        func due(from birthDate: Date, calendar: Calendar = .current) -> Date {
            if let days { return calendar.date(byAdding: .day, value: days, to: birthDate) ?? birthDate }
            return calendar.date(byAdding: .month, value: months ?? 0, to: birthDate) ?? birthDate
        }
    }

    static let items: [Item] = [
        .init(id: "checkup-3d", kind: .checkup, title: "3–5 day checkup", detail: "Feeding, jaundice, hydration and weight", days: 3, months: nil),
        .init(id: "checkup-1m", kind: .checkup, title: "1-month checkup", detail: "Growth, feeding and newborn screening follow-up", days: nil, months: 1),
        .init(id: "vaccines-birth", kind: .vaccine, title: "Birth vaccines", detail: "Hepatitis B; ask about RSV protection and maternal vaccination", days: 0, months: nil),
        .init(id: "checkup-2m", kind: .checkup, title: "2-month checkup", detail: "Growth and development", days: nil, months: 2),
        .init(id: "vaccines-2m", kind: .vaccine, title: "2-month vaccines", detail: "Rotavirus, DTaP, Hib, pneumococcal and polio; HepB timing varies", days: nil, months: 2),
        .init(id: "checkup-4m", kind: .checkup, title: "4-month checkup", detail: "Growth and development", days: nil, months: 4),
        .init(id: "vaccines-4m", kind: .vaccine, title: "4-month vaccines", detail: "Second rotavirus, DTaP, Hib, pneumococcal and polio doses", days: nil, months: 4),
        .init(id: "checkup-6m", kind: .checkup, title: "6-month checkup", detail: "Growth, development, feeding and oral health", days: nil, months: 6),
        .init(id: "vaccines-6m", kind: .vaccine, title: "6-month vaccines", detail: "DTaP and pneumococcal series; Hib, polio, rotavirus and HepB timing varies; annual flu starts at 6 months", days: nil, months: 6),
        .init(id: "checkup-9m", kind: .checkup, title: "9-month checkup", detail: "Developmental screening", days: nil, months: 9),
        .init(id: "checkup-12m", kind: .checkup, title: "12-month checkup", detail: "Growth, development, anemia/lead risk and dental care", days: nil, months: 12),
        .init(id: "vaccines-12m", kind: .vaccine, title: "12-month vaccines", detail: "MMR, varicella, hepatitis A, Hib and pneumococcal ranges begin around 12–15 months", days: nil, months: 12),
        .init(id: "checkup-15m", kind: .checkup, title: "15-month checkup", detail: "Growth and development", days: nil, months: 15),
        .init(id: "vaccines-15m", kind: .vaccine, title: "15-month vaccines", detail: "DTaP, Hib and pneumococcal booster windows", days: nil, months: 15),
        .init(id: "checkup-18m", kind: .checkup, title: "18-month checkup", detail: "Developmental and autism screening", days: nil, months: 18),
        .init(id: "vaccines-18m", kind: .vaccine, title: "18-month vaccines", detail: "Complete hepatitis A series and any clinician-directed catch-up doses", days: nil, months: 18),
        .init(id: "checkup-24m", kind: .checkup, title: "2-year checkup", detail: "Growth, development and autism screening", days: nil, months: 24),
        .init(id: "checkup-30m", kind: .checkup, title: "30-month checkup", detail: "Growth and developmental screening", days: nil, months: 30),
        .init(id: "checkup-36m", kind: .checkup, title: "3-year checkup", detail: "Growth and development; plan ongoing well-child care", days: nil, months: 36),
    ]

    /// A planning reminder the morning before the calendar-based visit date.
    static func reminderDate(for item: Item, birthDate: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let due = item.due(from: birthDate, calendar: calendar)
        guard let day = calendar.date(byAdding: .day, value: -1, to: due),
              let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day), fire > now else { return nil }
        return fire
    }

    static var remindersOn: Bool {
        get { Prefs.defaults.bool(forKey: remindersKey) }
        set { Prefs.defaults.set(newValue, forKey: remindersKey) }
    }

    static func isDone(_ item: Item, baby: Baby, in context: NSManagedObjectContext) -> Bool {
        Logbook.shared.labelled(item.title, kind: item.kind, for: baby, in: context) != nil
    }

    static func scheduleReminders(for baby: Baby, in context: NSManagedObjectContext, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        let identifiers = items.map { identifier($0, baby: baby) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard remindersOn, let birthDate = baby.birthDate else { return }

        for item in items where !isDone(item, baby: baby, in: context) {
            guard let fire = reminderDate(for: item, birthDate: birthDate, now: now) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(item.title) is coming up"
            content.body = "For \(baby.displayName): \(item.detail). Confirm timing with her clinician."
            content.sound = .default
            content.threadIdentifier = "care"
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: identifier(item, baby: baby), content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            center.add(request)
        }
    }

    private static func identifier(_ item: Item, baby: Baby) -> String {
        "care.\(baby.id?.uuidString ?? "baby").\(item.id)"
    }
}
