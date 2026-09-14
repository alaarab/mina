import AppIntents
import SwiftUI
import WidgetKit

/// Control Center: a bottle at the last amount, the nursing timer, and sleep.
/// Add them from Control Center → + → Mina. Each reads the shared store the
/// way the widgets do and reloads when the app or a widget logs something.

@available(iOS 18.0, *)
struct ControlProvider: ControlValueProvider {
    /// The controls gallery shows this; it must never be a real entry.
    var previewValue: ControlState {
        var state = ControlState()
        state.hasBaby = true
        state.lastBottleML = 4 * VolumeUnit.millilitersPerOunce
        state.unit = .ounces
        state.suggestedSide = .left
        return state
    }

    func currentValue() async throws -> ControlState { ControlState.load() }
}

@available(iOS 18.0, *)
struct LogBottleControl: ControlWidget {
    static let kind = "com.alaarab.mina.control.bottle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: ControlProvider()) { state in
            ControlWidgetButton(action: WidgetLogBottleIntent()) {
                Label("Log bottle", systemImage: "waterbottle.fill")
                Text(state.bottleValue)
            }
            .tint(MinaTheme.bottle)
        }
        .displayName("Log bottle")
        .description("Log a bottle at the last amount.")
    }
}

@available(iOS 18.0, *)
struct NursingControl: ControlWidget {
    static let kind = "com.alaarab.mina.control.nursing"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: ControlProvider()) { state in
            ControlWidgetToggle("Nursing", isOn: state.isNursing, action: WidgetSetNursingIntent()) { isOn in
                Label(state.nursingValue, systemImage: isOn ? "heart.fill" : "heart")
                    .controlWidgetActionHint(isOn ? "Stop nursing" : "Start nursing")
            }
            .tint(MinaTheme.nursing)
        }
        .displayName("Nursing")
        .description("Start the nursing timer on the suggested side, or stop it.")
    }
}

@available(iOS 18.0, *)
struct SleepControl: ControlWidget {
    static let kind = "com.alaarab.mina.control.sleep"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: ControlProvider()) { state in
            ControlWidgetToggle("Sleep", isOn: state.isSleeping, action: WidgetSetSleepIntent()) { isOn in
                Label(state.sleepValue, systemImage: isOn ? "moon.zzz.fill" : "sun.max.fill")
                    .controlWidgetActionHint(isOn ? "Log that she woke up" : "Start a sleep")
            }
            .tint(MinaTheme.sleep)
        }
        .displayName("Sleep")
        .description("Start a sleep, or log that she woke up.")
    }
}
