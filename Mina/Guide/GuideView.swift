import CoreData
import SwiftUI

/// What to expect at her age, and her baby book. It opens on the stage she is
/// in now but lets you read ahead or back; the milestones in each stage are
/// checkboxes, and ticking one logs it with today's date.

// MARK: Screen

struct GuideView: View {
    @ObservedObject var baby: Baby
    @Environment(\.managedObjectContext) private var context
    @StoredVolumeUnit private var unit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedStageID: String?
    @FetchRequest private var milestones: FetchedResults<LogEntry>

    init(baby: Baby) {
        _baby = ObservedObject(wrappedValue: baby)
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@ AND kindRaw == %@", baby, EntryKind.milestone.rawValue)
        _milestones = FetchRequest(fetchRequest: request, animation: .default)
    }

    private var currentStage: GuideStage {
        baby.guideStage() ?? Guidance.stages[0]
    }
    private var stage: GuideStage {
        Guidance.stages.first { $0.id == selectedStageID } ?? currentStage
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stagePicker
                    headlineCard
                    NavigationLink { CareScheduleView(baby: baby, initialMonth: stage.startMonth) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(MinaTheme.note)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Visits & vaccines").font(.mina(.headline)).foregroundStyle(MinaTheme.text)
                                Text("Dates from her birthday · tap to track").font(.mina(.caption)).foregroundStyle(MinaTheme.textMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(MinaTheme.textMuted)
                        }
                        .minaCard()
                    }
                    .buttonStyle(.plain)
                    GuideSection(title: "Feeding", symbol: EntryKind.bottle.symbol, color: MinaTheme.bottle, items: stage.feeding)
                    if stage.startMonth == 6 || stage.startMonth == 9 {
                        GuideSection(title: "Starting solids", symbol: EntryKind.solid.symbol, color: EntryKind.solid.color, items: Guidance.solids)
                    }
                    GuideSection(title: "Diapers", symbol: EntryKind.diaper.symbol, color: MinaTheme.diaper, items: stage.diapers)
                    GuideSection(title: "Sleep", symbol: EntryKind.sleep.symbol, color: MinaTheme.sleep, items: stage.sleep)
                    GuideSection(title: "Growth", symbol: "chart.line.uptrend.xyaxis", color: MinaTheme.accent, items: stage.growth)
                    if !stage.milestones.isEmpty { milestoneSection }
                    GuideSection(title: "Checkups", symbol: "stethoscope", color: MinaTheme.note, items: stage.checkups)
                    GuideSection(title: "Worth a call", symbol: "exclamationmark.bubble.fill", color: MinaTheme.warning, items: stage.watchFor)
                    GuideSection(title: "When to get help", symbol: "phone.fill", color: MinaTheme.danger, items: stage.startMonth == nil ? Guidance.callTheDoctor : Guidance.olderCallTheDoctor)
                    GuideSection(title: "Everyday", symbol: "house.fill", color: MinaTheme.textSecondary, items: stage.startMonth == nil ? Guidance.everyday : Guidance.olderEveryday)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sources").font(.mina(.headline))
                        ForEach(Guidance.sources, id: \.url) { source in
                            if let url = URL(string: source.url) {
                                Link(source.title, destination: url).frame(minHeight: 44, alignment: .leading)
                            }
                        }
                    }.minaCard()
                    Text(Guidance.disclaimer)
                        .font(.mina(.caption))
                        .foregroundStyle(MinaTheme.textMuted)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .readableWidth()
            }
            .minaCanvas()
            .navigationTitle("Guide")
        }
    }

    // MARK: Subviews

    /// Each milestone is a checkbox; ticking it logs the date, so the guide doubles as her baby book.
    private var milestoneSection: some View {
        let done = Dictionary(milestones.compactMap { entry in entry.label.map { ($0, entry) } }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 10) {
            Text("Dated memories, not a developmental screening test. Discuss concerns or lost skills with her clinician.")
                .font(.mina(.caption)).foregroundStyle(MinaTheme.textMuted)
            HStack(spacing: 8) {
                Image(systemName: "star.fill").font(.subheadline.weight(.semibold)).foregroundStyle(MinaTheme.warning).accessibilityHidden(true)
                Text("What she's learning").font(.mina(.headline))
                Spacer()
                Text("tap when she does it").font(.mina(.caption2)).foregroundStyle(MinaTheme.textMuted)
            }
            ForEach(Array(stage.milestones.enumerated()), id: \.offset) { _, item in
                let entry = done[item]
                Button {
                    try? Logbook.shared.toggleMilestone(item, for: baby, in: context)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: entry == nil ? "circle" : "checkmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(entry == nil ? MinaTheme.textMuted : MinaTheme.warning)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item)
                                .font(.mina(.subheadline))
                                .foregroundStyle(MinaTheme.textSecondary)
                                .strikethrough(entry != nil, color: MinaTheme.textMuted)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if let date = entry?.startedAt {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.mina(.caption2, weight: .semibold)).foregroundStyle(MinaTheme.warning)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item)
                .accessibilityValue(entry?.startedAt.map { "done, \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "not yet")
                .accessibilityHint(entry == nil ? "Logs it with today's date" : "Removes it from her log")
                .accessibilityAddTraits(.isToggle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .minaCard()
    }

    private var stagePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Guidance.stages) { candidate in
                        let isCurrent = candidate.id == currentStage.id
                        let isSelected = candidate.id == stage.id
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy) { selectedStageID = candidate.id }
                        } label: {
                            HStack(spacing: 6) {
                                if isCurrent { Circle().fill(isSelected ? .white : MinaTheme.accent).frame(width: 6, height: 6).accessibilityHidden(true) }
                                Text(candidate.title)
                            }
                            .font(.mina(.subheadline, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? MinaTheme.accent : MinaTheme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? .clear : MinaTheme.border, lineWidth: 1))
                            .foregroundStyle(isSelected ? .white : MinaTheme.text)
                            .padding(.vertical, 4)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("guide-stage-\(candidate.id)")
                        .accessibilityLabel(isCurrent ? "\(candidate.title), her stage now" : candidate.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(candidate.id)
                    }
                }
            }
            .accessibilityIdentifier("guide-stage-picker")
            .onAppear { proxy.scrollTo(currentStage.id, anchor: .center) }
            .onChange(of: currentStage.id) { _, id in
                selectedStageID = nil
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            let title = Text(stage.title).font(.mina(.title2, weight: .bold))
            let tag: Text? = stage.id == currentStage.id
                ? Text(baby.ageDescription()).font(.mina(.caption, weight: .semibold)).foregroundStyle(MinaTheme.accent)
                : (baby.ageDays().map { $0 < stage.ageDays.lowerBound } ?? false)
                    ? Text("coming up").font(.mina(.caption, weight: .semibold)).foregroundStyle(MinaTheme.textMuted)
                    : nil
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) { title; tag }
            } else {
                HStack(alignment: .firstTextBaseline) { title; Spacer(); tag }
            }
            Text(stage.headline)
                .font(.mina(.body))
                .foregroundStyle(MinaTheme.textSecondary)
            Divider()
            // Four chips across; two rows of two once text is large.
            let chips: [(String, String, Color)] = {
                var values: [(String, String, Color)] = []
                if stage.expectation.feedsPerDay != nil { values.append(("Feeds", stage.expectation.feedsText(), MinaTheme.bottle)) }
                if stage.expectation.mlPerFeed != nil { values.append(("Per feed", stage.expectation.perFeedText(unit: unit), MinaTheme.bottle)) }
                if stage.expectation.wetDiapersPerDay != nil { values.append(("Wet", stage.expectation.wetText() + " a day", MinaTheme.diaper)) }
                if stage.expectation.sleepHours != nil { values.append(("Sleep", stage.expectation.sleepText() + " a day", MinaTheme.sleep)) }
                return values
            }()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 2 : max(1, chips.count)), alignment: .leading, spacing: 10) {
                ForEach(chips, id: \.0) { chip in
                    ExpectChip(label: chip.0, value: chip.1, color: chip.2)
                }
            }
        }
        .minaCard()
    }
}

// MARK: Pieces

private struct ExpectChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.mina(.caption2, weight: .semibold)).foregroundStyle(color)
            Text(value).font(.mina(.caption, weight: .medium)).foregroundStyle(MinaTheme.text)
                .lineLimit(3).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Spoken.sentence([label, value]))
    }
}

private struct GuideSection: View {
    let title: String
    let symbol: String
    let color: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(color).accessibilityHidden(true)
                Text(title).font(.mina(.headline))
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(color.opacity(0.7)).frame(width: 6, height: 6).padding(.top, 7).accessibilityHidden(true)
                    Text(item)
                        .font(.mina(.subheadline))
                        .foregroundStyle(MinaTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .minaCard()
    }
}
