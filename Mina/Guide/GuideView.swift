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
    @State private var selectedStageID: String?
    @FetchRequest private var milestones: FetchedResults<LogEntry>

    init(baby: Baby) {
        _baby = ObservedObject(wrappedValue: baby)
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@ AND kindRaw == %@", baby, EntryKind.milestone.rawValue)
        _milestones = FetchRequest(fetchRequest: request, animation: .default)
    }

    private var currentStage: GuideStage {
        baby.ageDays().map(Guidance.stage(forAgeDays:)) ?? Guidance.stages[0]
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
                    GuideSection(title: "Feeding", symbol: EntryKind.bottle.symbol, color: MinaTheme.bottle, items: stage.feeding)
                    GuideSection(title: "Diapers", symbol: EntryKind.diaper.symbol, color: MinaTheme.diaper, items: stage.diapers)
                    GuideSection(title: "Sleep", symbol: EntryKind.sleep.symbol, color: MinaTheme.sleep, items: stage.sleep)
                    GuideSection(title: "Growth", symbol: "chart.line.uptrend.xyaxis", color: MinaTheme.accent, items: stage.growth)
                    milestoneSection
                    GuideSection(title: "Checkups", symbol: "stethoscope", color: MinaTheme.note, items: stage.checkups)
                    GuideSection(title: "Worth a call", symbol: "exclamationmark.bubble.fill", color: MinaTheme.warning, items: stage.watchFor)
                    GuideSection(title: "Call the doctor, any age", symbol: "phone.fill", color: MinaTheme.danger, items: Guidance.callTheDoctor)
                    GuideSection(title: "Everyday", symbol: "house.fill", color: MinaTheme.textSecondary, items: Guidance.everyday)
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
        let done = Dictionary(uniqueKeysWithValues: milestones.compactMap { entry in entry.label.map { ($0, entry) } })
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(MinaTheme.warning)
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
                            .font(.system(size: 18))
                            .foregroundStyle(entry == nil ? MinaTheme.textMuted : MinaTheme.warning)
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                            withAnimation(.snappy) { selectedStageID = candidate.id }
                        } label: {
                            HStack(spacing: 6) {
                                if isCurrent { Circle().fill(isSelected ? .white : MinaTheme.accent).frame(width: 6, height: 6) }
                                Text(candidate.title)
                            }
                            .font(.mina(.subheadline, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? MinaTheme.accent : MinaTheme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? .clear : MinaTheme.border, lineWidth: 1))
                            .foregroundStyle(isSelected ? .white : MinaTheme.text)
                        }
                        .buttonStyle(.plain)
                        .id(candidate.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(currentStage.id, anchor: .center) }
        }
    }

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(stage.title).font(.mina(.title2, weight: .bold))
                Spacer()
                if stage.id == currentStage.id {
                    Text(baby.ageDescription())
                        .font(.mina(.caption, weight: .semibold))
                        .foregroundStyle(MinaTheme.accent)
                } else if let days = baby.ageDays(), days < stage.ageDays.lowerBound {
                    Text("coming up")
                        .font(.mina(.caption, weight: .semibold))
                        .foregroundStyle(MinaTheme.textMuted)
                }
            }
            Text(stage.headline)
                .font(.mina(.body))
                .foregroundStyle(MinaTheme.textSecondary)
            Divider()
            HStack(spacing: 8) {
                ExpectChip(label: "Feeds", value: stage.expectation.feedsText(), color: MinaTheme.bottle)
                ExpectChip(label: "Per feed", value: stage.expectation.perFeedText(unit: unit), color: MinaTheme.bottle)
                ExpectChip(label: "Wet", value: stage.expectation.wetText() + " a day", color: MinaTheme.diaper)
                ExpectChip(label: "Sleep", value: stage.expectation.sleepText() + " a day", color: MinaTheme.sleep)
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
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                Text(title).font(.mina(.headline))
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(color.opacity(0.7)).frame(width: 6, height: 6).padding(.top, 7)
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
