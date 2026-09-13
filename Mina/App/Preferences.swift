import Foundation

enum VolumeUnit: String, CaseIterable, Identifiable {
    case ounces, milliliters

    var id: String { rawValue }
    static let millilitersPerOunce = 29.5735

    var symbol: String { self == .ounces ? "oz" : "ml" }
    var title: String { self == .ounces ? "Ounces" : "Milliliters" }
    /// One tap on a stepper, in the display unit.
    var step: Double { self == .ounces ? 0.5 : 10 }
    var maximum: Double { self == .ounces ? 20 : 600 }
    var quickPicks: [Double] { self == .ounces ? [2, 3, 4, 5, 6] : [60, 90, 120, 150, 180] }

    func display(ml: Double) -> Double { self == .ounces ? ml / Self.millilitersPerOunce : ml }
    func milliliters(fromDisplay value: Double) -> Double { self == .ounces ? value * Self.millilitersPerOunce : value }

    /// "4 oz", "4.5 oz", "120 ml". Ounces round to the nearest quarter.
    func format(ml: Double) -> String {
        let value = display(ml: ml)
        switch self {
        case .ounces: return "\(Self.trim((value * 4).rounded() / 4)) oz"
        case .milliliters: return "\(Int(value.rounded())) ml"
        }
    }

    static func trim(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

/// Settings shared between the app and its widgets through the App Group.
enum Prefs {
    static let appGroup = "group.com.alaarab.mina"
    static let unitKey = "volumeUnit"
    static let nameKey = "yourName"
    static let lastBottleKey = "lastBottleML"
    static let partnerAlertsKey = "partnerAlerts"
    static let deviceIDKey = "deviceID"

    static let defaults: UserDefaults = {
        let group = UserDefaults(suiteName: appGroup) ?? .standard
        // Early builds kept these in the standard domain; carry them over once.
        for key in [unitKey, nameKey, lastBottleKey] where group.object(forKey: key) == nil {
            if let value = UserDefaults.standard.object(forKey: key) { group.set(value, forKey: key) }
        }
        return group
    }()

    static var unit: VolumeUnit {
        VolumeUnit(rawValue: defaults.string(forKey: unitKey) ?? "") ?? .ounces
    }
    static var yourName: String {
        (defaults.string(forKey: nameKey) ?? "").trimmingCharacters(in: .whitespaces)
    }
    static var lastBottleML: Double {
        let stored = defaults.double(forKey: lastBottleKey)
        return stored > 0 ? stored : 3 * VolumeUnit.millilitersPerOunce
    }
    static func rememberBottle(ml: Double) {
        defaults.set(ml, forKey: lastBottleKey)
    }
    static var partnerAlerts: Bool {
        defaults.object(forKey: partnerAlertsKey) == nil ? true : defaults.bool(forKey: partnerAlertsKey)
    }

    /// Stable per-phone id, stamped on every entry so a phone can tell its own
    /// entries from its partner's without either parent typing a name.
    static var deviceID: String {
        if let existing = defaults.string(forKey: deviceIDKey) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: deviceIDKey)
        return fresh
    }
}
