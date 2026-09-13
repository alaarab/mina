import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Builds the text the on-device model reasons over: her age, the stage
/// guidance, and two weeks of daily totals. Pure, so it's tested.
enum AskContext {
    static func build(babyName: String, age: String, stage: GuideStage?, stats: [DayStat], recent: [String], unit: VolumeUnit) -> String {
        var lines: [String] = []
        lines.append("Baby: \(babyName), \(age).")
        if let stage {
            lines.append("Stage: \(stage.title). Typical: \(stage.expectation.feedsText()) feeds, \(stage.expectation.perFeedText(unit: unit)), \(stage.expectation.wetText()) diapers, \(stage.expectation.sleepText()) sleep.")
            lines.append("Feeding notes: " + stage.feeding.joined(separator: " "))
            lines.append("Sleep notes: " + stage.sleep.joined(separator: " "))
            lines.append("Watch for: " + stage.watchFor.joined(separator: " "))
        }
        lines.append("Daily totals, oldest first (day: feeds, bottle, nursing min, wet, dirty, sleep, longest sleep):")
        for stat in stats {
            let s = stat.summary
            lines.append("\(stat.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): \(s.feeds), \(unit.format(ml: s.bottleML)), \(Int(s.nursingSeconds / 60)), \(s.wet), \(s.dirty), \(Format.duration(s.sleepSeconds)), \(Format.duration(stat.longestSleep))")
        }
        if !recent.isEmpty {
            lines.append("Most recent entries, newest first:")
            lines.append(contentsOf: recent.prefix(12))
        }
        return lines.joined(separator: "\n")
    }

    static let instructions = """
    You are a calm, practical helper inside a newborn tracking app, answering a parent's questions about their own baby's log. \
    Use only the data provided and the stage notes. Be concrete: cite the numbers and days you used. Keep answers under 120 words. \
    If something looks concerning (fever of 38 C or 100.4 F under 3 months, fewer than 6 wet diapers after day 5, not waking to feed), say to call the pediatrician. \
    Never diagnose. If the data doesn't answer the question, say so.
    """
}

struct AskView: View {
    @ObservedObject var baby: Baby
    let stats: [DayStat]
    let recent: [String]
    let unit: VolumeUnit

    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var transcript: [(role: String, text: String)] = []
    @State private var busy = false
    @State private var unavailable: String?

    private let starters = ["How is her sleep trending?", "Is she eating enough for her age?", "Anything I should mention to the pediatrician?", "What was her longest stretch this week?"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if transcript.isEmpty {
                                Text("Answers come from Apple's on-device model, using only this log and the guide. Nothing leaves your phone.")
                                    .font(.mina(.footnote)).foregroundStyle(MinaTheme.textMuted)
                                ForEach(starters, id: \.self) { starter in
                                    Button(starter) { ask(starter) }
                                        .buttonStyle(.bordered).tint(MinaTheme.accent).font(.mina(.subheadline))
                                }
                            }
                            ForEach(Array(transcript.enumerated()), id: \.offset) { index, turn in
                                Text(turn.text)
                                    .font(.mina(.body))
                                    .padding(12)
                                    .background(turn.role == "you" ? MinaTheme.cardTint : MinaTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MinaTheme.border, lineWidth: 1))
                                    .frame(maxWidth: .infinity, alignment: turn.role == "you" ? .trailing : .leading)
                                    .id(index)
                            }
                            if busy { ProgressView().padding(.leading, 12) }
                            if let unavailable {
                                Text(unavailable).font(.mina(.footnote)).foregroundStyle(MinaTheme.danger)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: transcript.count) { _, count in withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) } }
                }
                HStack(spacing: 10) {
                    TextField("Ask about her log…", text: $question, axis: .vertical).lineLimit(1...4)
                        .textFieldStyle(.roundedBorder).font(.mina(.body))
                        .onSubmit { ask(question) }
                    Button { ask(question) } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }
                        .disabled(busy || question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
                .background(MinaTheme.card)
            }
            .background(MinaTheme.canvas.ignoresSafeArea())
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { checkAvailability() }
        }
    }

    private func checkAvailability() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: unavailable = nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: unavailable = "This iPhone can't run Apple's on-device model (needs iPhone 15 Pro or newer)."
                case .appleIntelligenceNotEnabled: unavailable = "Turn on Apple Intelligence in Settings to ask questions."
                case .modelNotReady: unavailable = "Apple's model is still downloading. Try again in a bit."
                @unknown default: unavailable = "Apple's on-device model isn't available right now."
                }
            }
            return
        }
        #endif
        unavailable = "Asking questions needs iOS 26 and Apple Intelligence."
    }

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy, unavailable == nil else { return }
        question = ""
        transcript.append((role: "you", text: trimmed))
        busy = true
        Task {
            defer { busy = false }
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let stage = baby.ageDays().map(Guidance.stage(forAgeDays:))
                let context = AskContext.build(babyName: baby.displayName, age: baby.ageDescription(), stage: stage, stats: stats, recent: recent, unit: unit)
                let session = LanguageModelSession(instructions: AskContext.instructions + "\n\nDATA:\n" + context)
                do {
                    let response = try await session.respond(to: trimmed)
                    transcript.append((role: "mina", text: response.content))
                } catch {
                    transcript.append((role: "mina", text: "Couldn't answer that: \(error.localizedDescription)"))
                }
                return
            }
            #endif
            transcript.append((role: "mina", text: "Asking questions needs iOS 26 and Apple Intelligence."))
        }
    }
}
