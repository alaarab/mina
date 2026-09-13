import SwiftUI

/// One sheet for the less frequent kinds: pumping, growth, medicine, tummy
/// time and temperature. Bath needs no sheet; it logs on tap.
struct ExtraSheet: View {
    let kind: EntryKind
    let unit: VolumeUnit
    let onSave: (EntryDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var when = Date.now
    @State private var note = ""
    @State private var amount: Double
    @State private var side: NursingSide = .both
    @State private var minutes = 5
    @State private var pounds = 0
    @State private var ounces = 0.0
    @State private var kilograms = 0.0
    @State private var length = 0.0
    @State private var head = 0.0
    @State private var temperature: Double
    @State private var medicine = "Vitamin D"
    @State private var dose = "400 IU"

    private let bodyUnit = Prefs.bodyUnit

    init(kind: EntryKind, unit: VolumeUnit, onSave: @escaping (EntryDraft) -> Void) {
        self.kind = kind
        self.unit = unit
        self.onSave = onSave
        _amount = State(initialValue: unit == .ounces ? 3 : 90)
        _temperature = State(initialValue: Prefs.bodyUnit.isImperial ? 98.6 : 37.0)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .pumping:
                    Section("Amount") {
                        Stepper(value: $amount, in: 0...unit.maximum, step: unit.step) {
                            Text("\(VolumeUnit.trim(amount)) \(unit.symbol)").font(.mina(.title3, weight: .semibold))
                        }
                        Picker("Side", selection: $side) { ForEach(NursingSide.allCases) { Text($0.title).tag($0) } }
                            .pickerStyle(.segmented)
                    }
                case .growth:
                    Section("Weight") {
                        if bodyUnit.isImperial {
                            Stepper("\(pounds) lb", value: $pounds, in: 0...40)
                            Stepper("\(VolumeUnit.trim(ounces)) oz", value: $ounces, in: 0...15.5, step: 0.5)
                        } else {
                            Stepper("\(VolumeUnit.trim(kilograms)) kg", value: $kilograms, in: 0...30, step: 0.05)
                        }
                    }
                    Section("Length and head") {
                        Stepper("Length \(VolumeUnit.trim(length)) \(lengthUnit)", value: $length, in: 0...(bodyUnit.isImperial ? 40 : 100), step: bodyUnit.isImperial ? 0.25 : 0.5)
                        Stepper("Head \(VolumeUnit.trim(head)) \(lengthUnit)", value: $head, in: 0...(bodyUnit.isImperial ? 25 : 60), step: bodyUnit.isImperial ? 0.25 : 0.5)
                    }
                case .medicine:
                    Section("Medicine") {
                        TextField("Name", text: $medicine)
                        TextField("Dose", text: $dose)
                    }
                case .tummyTime:
                    Section("Tummy time") {
                        Stepper("\(minutes) min", value: $minutes, in: 1...60)
                    }
                case .temperature:
                    Section("Temperature") {
                        Stepper(value: $temperature, in: bodyUnit.isImperial ? 90...110 : 32...43, step: 0.1) {
                            Text(String(format: "%.1f %@", temperature, bodyUnit.isImperial ? "°F" : "°C")).font(.mina(.title3, weight: .semibold))
                        }
                        if isFever {
                            Label("100.4 °F / 38 °C or higher under 3 months old is a call to the doctor, day or night.", systemImage: "phone.fill")
                                .font(.mina(.footnote)).foregroundStyle(MinaTheme.danger)
                        }
                    }
                default:
                    EmptyView()
                }
                Section {
                    DatePicker("When", selection: $when, in: ...Date.now.addingTimeInterval(60), displayedComponents: [.date, .hourAndMinute])
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
            }
        }
    }

    private var lengthUnit: String { bodyUnit.isImperial ? "in" : "cm" }
    private var isFever: Bool { Measure.celsius(fromDisplay: temperature, unit: bodyUnit) >= 38 }

    private func save() {
        var draft = EntryDraft(kind: kind, startedAt: when)
        draft.note = note
        switch kind {
        case .pumping:
            draft.amountML = unit.milliliters(fromDisplay: amount)
            draft.side = side
        case .growth:
            draft.weightGrams = bodyUnit.isImperial ? (Double(pounds) * 16 + ounces) * Measure.gramsPerOunce : kilograms * 1000
            draft.lengthCM = Measure.cm(fromDisplay: length, unit: bodyUnit)
            draft.headCM = Measure.cm(fromDisplay: head, unit: bodyUnit)
        case .medicine:
            draft.label = [medicine, dose].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .tummyTime:
            draft.endedAt = when.addingTimeInterval(Double(minutes) * 60)
        case .temperature:
            draft.temperatureC = Measure.celsius(fromDisplay: temperature, unit: bodyUnit)
        default:
            break
        }
        onSave(draft)
        dismiss()
    }
}
