import Foundation
import SwiftUI

/// Everything the app remembers between launches, and the unit system that
/// shapes how amounts are typed and read back. Both live in the App Group so
/// the widgets, the Siri intents and the app itself agree on a bottle size and
/// on which phone logged what.

// MARK: Units

enum VolumeUnit: String, CaseIterable, Identifiable {
    case ounces, milliliters

    var id: String { rawValue }
    static let millilitersPerOunce = 29.5735

    var symbol: String { self == .ounces ? "oz" : "ml" }
    var title: String { self == .ounces ? "Ounces" : "Milliliters" }
    /// One tap on a stepper, in the display unit.
    var step: Double { self == .ounces ? 0.5 : 1 }
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

// MARK: Stored settings

/// Features that exist in the code but aren't shown in this release.
enum FeatureFlags {
    /// The Nanit import talks to Nanit's private API. Off for App Store builds;
    /// flip on for personal builds.
    static let nanit = false
}

/// Weight, length and temperature units, separate from the bottle unit so a
/// millilitre household can still weigh in pounds and ounces.
enum BodyUnit: String, CaseIterable, Identifiable {
    case imperial, metric
    var id: String { rawValue }
    var title: String { self == .imperial ? "lb / oz, in, °F" : "kg, cm, °C" }
    var isImperial: Bool { self == .imperial }
}

/// Settings shared between the app and its widgets through the App Group.
enum Prefs {
    static let appGroup = Bundle.main.bundleIdentifier?.hasSuffix(".recovery") == true ? "group.com.alaarab.mina.recovery" : "group.com.alaarab.mina"
    static let unitKey = "volumeUnit"
    static let bodyUnitKey = "bodyUnit"
    static let nameKey = "yourName"
    static let lastBottleKey = "lastBottleML"
    static let partnerAlertsKey = "partnerAlerts"
    static let deviceIDKey = "deviceID"
    static let lastNursingSideKey = "lastNursingSide"
    static let selectedBabyKey = "selectedBaby"

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
    /// Defaults to pounds and ounces regardless of the bottle unit.
    static var bodyUnit: BodyUnit {
        BodyUnit(rawValue: defaults.string(forKey: bodyUnitKey) ?? "") ?? .imperial
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
    /// The side she finished on last time, so the next feed can start on the other.
    static var lastNursingSide: NursingSide? {
        get { defaults.string(forKey: lastNursingSideKey).flatMap(NursingSide.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: lastNursingSideKey) }
    }
    static var suggestedNursingSide: NursingSide {
        switch lastNursingSide {
        case .left: return .right
        case .right: return .left
        default: return .left
        }
    }

    /// Which baby the app shows when there's more than one (twins, a second child).
    static var selectedBabyID: UUID? {
        get { defaults.string(forKey: selectedBabyKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: selectedBabyKey) }
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

/// The chosen bottle unit, read straight into a view and kept live when
/// Settings changes it: `@StoredVolumeUnit private var unit`. Wraps the
/// `@AppStorage` string so no screen has to decode the raw value itself.
@propertyWrapper
struct StoredVolumeUnit: DynamicProperty {
    @AppStorage(Prefs.unitKey, store: Prefs.defaults) private var raw = VolumeUnit.ounces.rawValue

    var wrappedValue: VolumeUnit { VolumeUnit(rawValue: raw) ?? .ounces }
}
