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

/// One turn in the chat. The reply is filled in as the model streams it.
private struct AskMessage: Identifiable {
    enum Role { case you, mina }
    let id = UUID()
    let role: Role
    var text: String
    var streaming = false
    var error: String?
}

/// Holds the single `LanguageModelSession` for this chat so follow-up
/// questions keep their context. Untyped, because the framework only exists
/// on iOS 26 and this view compiles down to iOS 17.
private final class AskSession {
    var model: Any?
}

struct AskView: View {
    @ObservedObject var baby: Baby
    let stats: [DayStat]
    let recent: [String]
    let unit: VolumeUnit

    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var messages: [AskMessage] = []
    @State private var streaming = false
    @State private var unavailable: String?
    @State private var revision = 0
    @State private var answering: Task<Void, Never>?
    @State private var chat = AskSession()
    @StateObject private var dictation = Dictation()
    @StateObject private var speaker = Speaker()
    @AppStorage(Speaker.key, store: Prefs.defaults) private var speaks = false
    @FocusState private var composing: Bool

    private let starters = ["How is her sleep trending?", "Is she eating enough for her age?", "Anything I should mention to the pediatrician?", "What was her longest stretch this week?"]
    private static let bottom = "ask-bottom"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                composer
                bindVoice()
            }
            .background(MinaTheme.canvas.ignoresSafeArea())
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { checkAvailability() }
            .onDisappear { answering?.cancel() }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty { emptyState }
                    if let unavailable { notice(unavailable) }
                    ForEach(messages) { message in
                        AskMessageRow(message: message).id(message.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readableWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            }
            // Streaming snapshots arrive faster than an animation can settle,
            // so the follow is unanimated — that reads as smooth, not jittery.
            .onChange(of: revision) { _, _ in proxy.scrollTo(Self.bottom, anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("On-device · Apple Intelligence", systemImage: "sparkles")
                .font(.mina(.caption, weight: .semibold))
                .foregroundStyle(MinaTheme.accent)
            Text("Answers come from Apple's on-device model using only this log and the guide. Nothing leaves your phone.")
                .font(.mina(.footnote))
                .foregroundStyle(MinaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            AskFlow(spacing: 8) {
                ForEach(starters, id: \.self) { starter in
                    Button { ask(starter) } label: {
                        Text(starter)
                            .font(.mina(.subheadline))
                            .foregroundStyle(MinaTheme.text)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(MinaTheme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(MinaTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(unavailable != nil)
                    .accessibilityLabel("Ask: \(starter)")
                }
            }
            .padding(.top, 4)
        }
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.mina(.footnote))
            .foregroundStyle(MinaTheme.danger)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .minaCard(padding: 12)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            TextField("Ask about her log…", text: $question, axis: .vertical)
                .lineLimit(1...5)
                .focused($composing)
                .font(.mina(.body))
                .foregroundStyle(MinaTheme.text)
                .tint(MinaTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .disabled(unavailable != nil)
                .accessibilityLabel("Question")
            HStack(alignment: .bottom, spacing: 4) {
                Button { newChat() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MinaTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(messages.isEmpty && question.isEmpty)
                .accessibilityLabel("New chat")

                Button {
                    speaks.toggle()
                    if !speaks { speaker.stop() }
                    else if let last = messages.last(where: { $0.role == .mina && !$0.text.isEmpty }), !streaming { speaker.speak(last.text) }
                } label: {
                    Image(systemName: speaks ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(speaks ? MinaTheme.accent : MinaTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(speaks ? "Stop reading answers aloud" : "Read answers aloud")

                Button { dictation.toggle() } label: {
                    Image(systemName: dictation.listening ? "mic.fill" : "mic")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(dictation.listening ? Color.white : MinaTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(dictation.listening ? MinaTheme.danger : Color.clear, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(unavailable != nil || streaming)
                .accessibilityLabel(dictation.listening ? "Stop dictating" : "Dictate a question")

                Spacer(minLength: 4)

                Button { streaming ? stop() : ask(question) } label: {
                    Image(systemName: streaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: streaming ? 13 : 17, weight: .semibold))
                        .foregroundStyle(sendEnabled ? Color.white : MinaTheme.textMuted)
                        .frame(width: 36, height: 36)
                        .background(sendEnabled ? MinaTheme.accent : MinaTheme.border, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!sendEnabled)
                .accessibilityLabel(streaming ? "Stop answering" : "Send question")
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .background(MinaTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MinaTheme.border, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .readableWidth()
        .background(MinaTheme.canvas.ignoresSafeArea(.container, edges: .bottom))
    }

    private func bindVoice() -> some View {
        EmptyView()
            .onChange(of: dictation.transcript) { _, text in if dictation.listening || !text.isEmpty { question = text } }
            .onChange(of: dictation.listening) { was, now in
                if was && !now, speaks, !question.trimmingCharacters(in: .whitespaces).isEmpty { ask(question) }
            }
            .onChange(of: dictation.problem) { _, problem in if let problem { messages.append(AskMessage(role: .mina, text: "", error: problem)) } }
            .onDisappear { dictation.stop(); speaker.stop() }
    }

    private var sendEnabled: Bool {
        if streaming { return true }
        return unavailable == nil && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Asking

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

    #if canImport(FoundationModels)
    /// One session per chat: the transcript it keeps is what makes follow-up
    /// questions ("and last week?") land.
    @available(iOS 26.0, *)
    private func session() -> LanguageModelSession {
        if let existing = chat.model as? LanguageModelSession { return existing }
        let stage = baby.ageDays().map(Guidance.stage(forAgeDays:))
        let context = AskContext.build(babyName: baby.displayName, age: baby.ageDescription(), stage: stage, stats: stats, recent: recent, unit: unit)
        let made = LanguageModelSession(instructions: AskContext.instructions + "\n\nDATA:\n" + context)
        chat.model = made
        return made
    }
    #endif

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !streaming, unavailable == nil else { return }
        dictation.stop()
        speaker.stop()
        question = ""
        composing = false
        messages.append(AskMessage(role: .you, text: trimmed))
        let reply = AskMessage(role: .mina, text: "", streaming: true)
        messages.append(reply)
        streaming = true
        answering = Task { @MainActor in
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                do {
                    // Each snapshot carries the whole answer so far, not a
                    // delta — assign it, don't append it.
                    for try await snapshot in session().streamResponse(to: trimmed) {
                        if Task.isCancelled { break }
                        update(reply.id) { $0.text = snapshot.content }
                        revision &+= 1
                    }
                } catch is CancellationError {
                    // Stopped on purpose; keep whatever arrived.
                } catch {
                    let note = "Couldn't answer that: \(error.localizedDescription)"
                    update(reply.id) { $0.error = note }
                }
                settle()
                return
            }
            #endif
            update(reply.id) { $0.error = "Asking questions needs iOS 26 and Apple Intelligence." }
            settle()
        }
    }

    private func stop() {
        answering?.cancel()
        answering = nil
        settle()
    }

    private func newChat() {
        answering?.cancel()
        answering = nil
        streaming = false
        messages = []
        question = ""
        chat.model = nil
        checkAvailability()
    }

    private func update(_ id: UUID, _ change: (inout AskMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    /// Idempotent: both the stop button and the finished task call it.
    private func settle() {
        let wasStreaming = streaming
        streaming = false
        if wasStreaming, speaks, let last = messages.last(where: { $0.role == .mina }), !last.text.isEmpty, last.error == nil { speaker.speak(last.text) }
        for index in messages.indices where messages[index].streaming {
            messages[index].streaming = false
            if messages[index].text.isEmpty && messages[index].error == nil { messages[index].text = "Stopped." }
        }
    }
}

// MARK: - Rows

private struct AskMessageRow: View {
    let message: AskMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .you { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                if message.role == .you {
                    Text(message.text)
                        .font(.mina(.body))
                        .foregroundStyle(MinaTheme.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    if !message.text.isEmpty { AskRichText(text: message.text).equatable() }
                    if message.streaming { AskCaret() }
                    if let error = message.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.mina(.footnote))
                            .foregroundStyle(MinaTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(message.role == .you ? 14 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(message.role == .you ? MinaTheme.cardTint : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message.role == .you ? "Your question" : "Answer")
    }
}

/// The "still writing" cursor at the end of a streaming answer.
private struct AskCaret: View {
    @State private var dim = false
    var body: some View {
        Capsule()
            .fill(MinaTheme.accent)
            .frame(width: 4, height: 14)
            .opacity(dim ? 0.15 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Markdown

/// Native Markdown in Mina's rounded type: paragraphs, headings, bullets and
/// the occasional fenced block. Nothing is fetched; this only formats text.
struct AskRichText: View, Equatable {
    let text: String
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    private enum Kind { case paragraph, heading, bullet, code }
    private struct Block: Identifiable {
        let id: Int
        let text: String
        let kind: Kind
        var marker: String?
        var language: String?
    }

    /// Splits "- a" / "1. a" off a list line; nil when the line is prose.
    private static func bullet(_ line: String) -> (marker: String, text: String)? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        for prefix in ["- ", "* ", "• "] where trimmed.hasPrefix(prefix) {
            return ("•", String(trimmed.dropFirst(prefix.count)))
        }
        if let range = trimmed.range(of: #"^\d{1,2}[.)] "#, options: .regularExpression) {
            return (String(trimmed[range]).trimmingCharacters(in: .whitespaces), String(trimmed[range.upperBound...]))
        }
        return nil
    }

    private var blocks: [Block] {
        var result: [Block] = [], lines: [String] = []
        var language: String?
        func flush() {
            guard !lines.isEmpty else { return }
            let raw = lines.joined(separator: "\n")
            // Code keeps its whitespace; prose does not need blank lines.
            let content = language == nil ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : raw
            lines = []
            guard !content.isEmpty else { return }
            result.append(Block(id: result.count, text: content, kind: language == nil ? .paragraph : .code, language: language))
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                flush()
                language = language == nil ? String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) : nil
            } else if language != nil {
                lines.append(line)
            } else if line.range(of: #"^#{1,6} "#, options: .regularExpression) != nil {
                flush()
                result.append(Block(id: result.count, text: String(line.drop(while: { $0 == "#" || $0 == " " })), kind: .heading))
            } else if let item = Self.bullet(line) {
                flush()
                result.append(Block(id: result.count, text: item.text, kind: .bullet, marker: item.marker))
            } else {
                lines.append(line)
            }
        }
        flush()
        return result
    }

    private func styled(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading:
                    Text(styled(block.text))
                        .font(.mina(.headline, weight: .semibold))
                        .foregroundStyle(MinaTheme.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(block.marker ?? "•")
                            .font(.mina(.body, weight: .semibold))
                            .foregroundStyle(MinaTheme.accent)
                        Text(styled(block.text))
                            .font(.mina(.body))
                            .foregroundStyle(MinaTheme.text)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .textSelection(.enabled)
                case .code:
                    Text(block.text)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(MinaTheme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(MinaTheme.cardTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                case .paragraph:
                    Text(styled(block.text))
                        .font(.mina(.body))
                        .foregroundStyle(MinaTheme.text)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Chips wrap onto as many rows as they need. iOS has no stock flow layout.
private struct AskFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: limit, height: nil))
            if x > 0 && x + size.width > limit { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            width = max(width, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(width, limit), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > 0 && x + size.width > bounds.width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
