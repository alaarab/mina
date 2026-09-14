import SwiftUI

/// The sheets behind the Today buttons: a bottle, a nursing session or timer, a
/// note, and the editor that any logged entry opens into. Each one builds an
/// `EntryDraft` and hands it back, so nothing here writes to the store itself.

// MARK: Which sheet

enum QuickSheet: Identifiable {
    case bottle, nursing, note
    case extra(EntryKind)
    var id: String {
        switch self {
        case .bottle: return "bottle"
        case .nursing: return "nursing"
        case .note: return "note"
        case .extra(let kind): return "extra-\(kind.rawValue)"
        }
    }
}

// MARK: Bottle

struct BottleSheet: View {
    let unit: VolumeUnit
    let onSave: (EntryDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var amount: Double
    @State private var when = Date.now
    @State private var note = ""

    init(unit: VolumeUnit, onSave: @escaping (EntryDraft) -> Void) {
        self.unit = unit
        self.onSave = onSave
        let last = unit.display(ml: Prefs.lastBottleML)
        _amount = State(initialValue: (last / unit.step).rounded() * unit.step)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 28) {
                HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 28) {
                    StepButton(symbol: "minus") { amount = max(0, amount - unit.step) }
                    VStack(spacing: 0) {
                        AmountField(value: $amount, unit: unit)
                        Text("\(unit.symbol) · tap to type")
                            .font(.mina(.footnote, weight: .medium))
                            .foregroundStyle(MinaTheme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 100 : 150)
                    StepButton(symbol: "plus") { amount = min(unit.maximum, amount + unit.step) }
                }
                .padding(.top, 12)

                HStack(spacing: 8) {
                    ForEach(unit.quickPicks, id: \.self) { pick in
                        Button { amount = pick } label: { Text(VolumeUnit.trim(pick)).frame(minWidth: 24, minHeight: 30) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("\(VolumeUnit.trim(pick)) \(unit.symbol == "oz" ? "ounces" : "milliliters")")
                            .tint(amount == pick ? MinaTheme.bottle : MinaTheme.textMuted)
                            .font(.mina(.body, weight: .semibold))
                    }
                }

                VStack(spacing: 12) {
                    DatePicker("When", selection: $when, in: ...Date.now.addingTimeInterval(60), displayedComponents: [.date, .hourAndMinute])
                        .font(.mina(.body))
                    Divider()
                    TextField("Note (optional)", text: $note)
                        .font(.mina(.body))
                }
                .minaCard()
            }
            .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button { save() } label: {
                    Text("Save bottle").font(.mina(.headline)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MinaTheme.bottle)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(MinaTheme.canvas)
            }
            .minaCanvas()
            .navigationTitle("Bottle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        var draft = EntryDraft(kind: .bottle, startedAt: when)
        draft.amountML = unit.milliliters(fromDisplay: amount)
        draft.note = note
        Prefs.rememberBottle(ml: draft.amountML)
        onSave(draft)
        dismiss()
    }
}

// MARK: Nursing

struct NursingSheet: View {
    let onStart: (NursingSide) -> Void
    let onSave: (EntryDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var bigNumber = 72.0
    @State private var manual = false
    @State private var side: NursingSide = Prefs.suggestedNursingSide
    @State private var minutes = 15
    @State private var when = Date.now
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 24) {
                Picker("Mode", selection: $manual) {
                    Text("Start timer").tag(false)
                    Text("Already done").tag(true)
                }
                .pickerStyle(.segmented)

                if manual {
                    Picker("Side", selection: $side) {
                        ForEach(NursingSide.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 28) {
                        StepButton(symbol: "minus") { minutes = max(1, minutes - 1) }
                        VStack(spacing: 0) {
                            Text("\(minutes)")
                                .font(.system(size: bigNumber, weight: .bold, design: .rounded))
                                .foregroundStyle(MinaTheme.text)
                                .contentTransition(.numericText())
                                .animation(reduceMotion ? nil : .snappy, value: minutes)
                            Text("minutes").font(.mina(.title3, weight: .medium)).foregroundStyle(MinaTheme.textMuted)
                        }
                        .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 100 : 130)
                        StepButton(symbol: "plus") { minutes = min(120, minutes + 1) }
                    }

                    HStack(spacing: 8) {
                        ForEach([5, 10, 15, 20, 30], id: \.self) { pick in
                            Button { minutes = pick } label: { Text("\(pick)").frame(minWidth: 24, minHeight: 30) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("\(pick) minutes")
                                .tint(minutes == pick ? MinaTheme.nursing : MinaTheme.textMuted)
                                .font(.mina(.body, weight: .semibold))
                        }
                    }

                    VStack(spacing: 12) {
                        DatePicker("Started", selection: $when, in: ...Date.now.addingTimeInterval(60), displayedComponents: [.date, .hourAndMinute])
                            .font(.mina(.body))
                        Divider()
                        TextField("Note (optional)", text: $note).font(.mina(.body))
                    }
                    .minaCard()

                    Button { save() } label: {
                        Text("Save nursing").font(.mina(.headline)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MinaTheme.nursing)
                    .controlSize(.large)
                } else {
                    VStack(spacing: 6) {
                        Text("Which side is she starting on?")
                            .font(.mina(.title3, weight: .semibold))
                        if let last = Prefs.lastNursingSide {
                            Text("She finished on the \(last.title.lowercased()) last time.")
                                .font(.mina(.subheadline)).foregroundStyle(MinaTheme.textMuted)
                        }
                    }
                    .padding(.top, 8)

                    let sides = ForEach([NursingSide.left, .right]) { candidate in
                            Button {
                                onStart(candidate)
                                dismiss()
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: candidate == .left ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                                        .font(.largeTitle)
                                        .accessibilityHidden(true)
                                    Text(candidate.title).font(.mina(.headline))
                                    if candidate == Prefs.suggestedNursingSide {
                                        Text("suggested").font(.mina(.caption2, weight: .semibold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 26)
                                .background(candidate == Prefs.suggestedNursingSide ? MinaTheme.nursing : MinaTheme.card,
                                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MinaTheme.border, lineWidth: 1))
                                .foregroundStyle(candidate == Prefs.suggestedNursingSide ? .white : MinaTheme.text)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(candidate == Prefs.suggestedNursingSide ? "Start on the \(candidate.title.lowercased()), suggested" : "Start on the \(candidate.title.lowercased())")
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 14) { sides }
                    } else {
                        HStack(spacing: 14) { sides }
                    }

                    Text("The timer keeps running if you leave the app. Switch sides or stop from the Today screen.")
                        .font(.mina(.footnote)).foregroundStyle(MinaTheme.textMuted).multilineTextAlignment(.center)
                }
            }
            .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .minaCanvas()
            .navigationTitle("Nursing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        var draft = EntryDraft(kind: .nursing, startedAt: when)
        draft.side = side
        draft.endedAt = when.addingTimeInterval(Double(minutes) * 60)
        draft.note = note
        onSave(draft)
        dismiss()
    }
}

// MARK: Note

struct NoteSheet: View {
    let onSave: (EntryDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var when = Date.now
    @State private var photo: EntryPhoto?

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 20) {
                TextField("Spit up after the bottle, vitamin D drops, first smile…", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.mina(.body))
                    .minaCard()
                // A photo on its own is a note too: the rash, the diaper for the doctor.
                PhotoAttachment(photo: $photo, tint: MinaTheme.note)
                    .minaCard()
                DatePicker("When", selection: $when, in: ...Date.now.addingTimeInterval(60), displayedComponents: [.date, .hourAndMinute])
                    .font(.mina(.body))
                    .minaCard()
            }
            .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    var draft = EntryDraft(kind: .note, startedAt: when)
                    draft.note = text
                    draft.photo = photo
                    onSave(draft)
                    dismiss()
                } label: {
                    Text("Save note").font(.mina(.headline)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MinaTheme.note)
                .controlSize(.large)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photo == nil)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(MinaTheme.canvas)
            }
            .minaCanvas()
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: Pieces

/// The big number in the bottle sheet: type it on the number pad, or use the
/// buttons either side to nudge it.
struct AmountField: View {
    @Binding var value: Double
    let unit: VolumeUnit
    @State private var text = ""
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var bigNumber = 64.0

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.system(size: bigNumber, weight: .bold, design: .rounded))
            .foregroundStyle(MinaTheme.text)
            .focused($focused)
            .onAppear { text = VolumeUnit.trim(value) }
            .onChange(of: value) { _, new in
                if Double(text.replacingOccurrences(of: ",", with: ".")) != new { text = VolumeUnit.trim(new) }
            }
            .onChange(of: text) { _, new in
                if let parsed = Double(new.replacingOccurrences(of: ",", with: ".")) { value = min(unit.maximum, max(0, parsed)) }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }.fontWeight(.semibold)
                }
            }
    }
}

struct StepButton: View {
    let symbol: String
    let action: () -> Void
    /// Grows with the text, but never so far that two of them crowd the number out.
    @ScaledMetric(relativeTo: .title2) private var scaled = 60.0
    private var size: CGFloat { min(scaled, 72) }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .frame(width: size, height: size)
                .background(MinaTheme.cardTint, in: Circle())
                .foregroundStyle(MinaTheme.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "minus" ? "Less" : "More")
    }
}

// MARK: Editor

/// Edits any entry. Works on a local draft so Cancel really cancels.
struct EntryEditor: View {
    @ObservedObject var entry: LogEntry

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StoredVolumeUnit private var unit
    @State private var draft: EntryDraft
    @State private var amountDisplay: Double
    @State private var minutes: Int
    @State private var ongoing: Bool
    @State private var endedAt: Date
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var saved = 0

    init(entry: LogEntry) {
        _entry = ObservedObject(wrappedValue: entry)
        let draft = EntryDraft(entry: entry)
        _draft = State(initialValue: draft)
        _amountDisplay = State(initialValue: Prefs.unit.display(ml: draft.amountML))
        let seconds = (draft.endedAt ?? draft.startedAt).timeIntervalSince(draft.startedAt)
        _minutes = State(initialValue: max(1, Int((seconds / 60).rounded())))
        _ongoing = State(initialValue: draft.kind == .sleep && draft.endedAt == nil)
        _endedAt = State(initialValue: draft.endedAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(draft.kind == .sleep ? "Fell asleep" : "When", selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    HStack(spacing: 8) {
                        ForEach([-30, -15, -5, 5, 15], id: \.self) { minutes in
                            Button { draft.startedAt = draft.startedAt.addingTimeInterval(Double(minutes) * 60) } label: {
                                Text(minutes > 0 ? "+\(minutes)m" : "\(minutes)m").frame(minHeight: 30)
                            }
                            .buttonStyle(.bordered).tint(MinaTheme.textMuted).font(.mina(.subheadline, weight: .semibold))
                            .accessibilityLabel(minutes > 0 ? "\(minutes) minutes later" : "\(-minutes) minutes earlier")
                        }
                    }
                }
                switch draft.kind {
                case .bottle:
                    Section("Amount") {
                        HStack {
                            TextField("Amount", value: $amountDisplay, format: .number)
                                .keyboardType(.decimalPad)
                                .font(.mina(.title2, weight: .semibold))
                            Text(unit.symbol).foregroundStyle(MinaTheme.textMuted)
                            Stepper("", value: $amountDisplay, in: 0...unit.maximum, step: unit.step).labelsHidden()
                        }
                        HStack(spacing: 8) {
                            ForEach(unit.quickPicks, id: \.self) { pick in
                                Button { amountDisplay = pick } label: { Text(VolumeUnit.trim(pick)).frame(minWidth: 24, minHeight: 30) }
                                    .buttonStyle(.bordered).tint(amountDisplay == pick ? MinaTheme.bottle : MinaTheme.textMuted).font(.mina(.subheadline, weight: .semibold))
                                    .accessibilityLabel("\(VolumeUnit.trim(pick)) \(unit.symbol == "oz" ? "ounces" : "milliliters")")
                            }
                        }
                    }
                case .nursing:
                    Section("Nursing") {
                        Picker("Side", selection: Binding(get: { draft.side ?? .left }, set: { draft.side = $0 })) {
                            ForEach(NursingSide.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Stepper("\(minutes) min", value: $minutes, in: 1...120)
                    }
                case .diaper:
                    Section("Diaper") {
                        Picker("Type", selection: Binding(get: { draft.diaper ?? .wet }, set: { draft.diaper = $0 })) {
                            ForEach(DiaperKind.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                case .sleep:
                    Section("Sleep") {
                        Toggle("Still asleep", isOn: $ongoing)
                        if !ongoing {
                            DatePicker("Woke up", selection: $endedAt, in: draft.startedAt..., displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                case .pumping:
                    Section("Pumping") {
                        Stepper(value: $amountDisplay, in: 0...unit.maximum, step: unit.step) {
                            Text("\(VolumeUnit.trim(amountDisplay)) \(unit.symbol)").font(.mina(.body, weight: .semibold))
                        }
                        Picker("Side", selection: Binding(get: { draft.side ?? .both }, set: { draft.side = $0 })) {
                            ForEach(NursingSide.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                case .tummyTime:
                    Section("Tummy time") { Stepper("\(minutes) min", value: $minutes, in: 1...60) }
                case .medicine:
                    Section("Medicine") { TextField("Name and dose", text: $draft.label) }
                case .growth:
                    Section("Growth") {
                        Text(entry.title(unit: unit)).foregroundStyle(MinaTheme.textSecondary)
                        Text("Delete and re-add to change the measurements.").font(.mina(.footnote)).foregroundStyle(MinaTheme.textMuted)
                    }
                case .temperature:
                    Section("Temperature") {
                        Text(entry.title(unit: unit)).foregroundStyle(MinaTheme.textSecondary)
                    }
                case .milestone:
                    Section("Milestone") { TextField("What she did", text: $draft.label) }
                case .note, .bath:
                    EmptyView()
                }
                Section(draft.kind == .note ? "Note" : "Note (optional)") {
                    TextField("Note", text: $draft.note, axis: .vertical).lineLimit(1...6)
                }
                if draft.kind == .note || draft.kind == .milestone {
                    Section("Photo") {
                        PhotoAttachment(photo: $draft.photo, tint: draft.kind.color)
                    }
                }
                Section {
                    Button("Delete entry", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Edit \(draft.kind.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    do { try Logbook.shared.delete(entry, in: context); dismiss() } catch { self.error = error.localizedDescription }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .errorAlert($error)
        }
    }

    // MARK: Actions

    private func save() {
        var final = draft
        switch draft.kind {
        case .bottle, .pumping: final.amountML = unit.milliliters(fromDisplay: amountDisplay)
        case .nursing, .tummyTime: final.endedAt = draft.startedAt.addingTimeInterval(Double(minutes) * 60)
        case .sleep: final.endedAt = ongoing ? nil : max(endedAt, draft.startedAt)
        case .diaper, .note, .growth, .medicine, .bath, .temperature, .milestone: break
        }
        Logbook.shared.apply(final, to: entry)
        do {
            try context.save()
            Logbook.widgetsChanged()
            saved &+= 1
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
