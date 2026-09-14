import SwiftUI

/// One logged thing as a row, and the card of rows that Today and Calendar both
/// build a day out of. The row shows only what an entry already knows how to
/// say about itself, so a bottle reads the same wherever it appears. A note or
/// milestone with a picture shows its thumbnail, which opens the viewer.

struct EntryRow: View {
    @ObservedObject var entry: LogEntry
    let unit: VolumeUnit
    let now: Date
    @ScaledMetric(relativeTo: .body) private var badge = 42.0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text: the time goes under the title instead of beside it.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) { icon; titles; Spacer(minLength: 0) }
                    HStack(spacing: 12) {
                        if let thumb = entry.photoThumb { EntryThumbnail(thumb: thumb) { entry.photo } }
                        times
                        Spacer(minLength: 8)
                        chevron
                    }
                    .padding(.leading, badge + 12)
                }
            } else {
                HStack(spacing: 12) {
                    icon
                    titles
                    Spacer(minLength: 8)
                    if let thumb = entry.photoThumb { EntryThumbnail(thumb: thumb) { entry.photo } }
                    times
                    chevron
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        // One element per row: "Bottle, 4 ounces, by Mom, 10:00 AM". The
        // photo thumbnail stays reachable as the row's "Photo" action.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Spoken.entry(entry, unit: unit, now: now))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the entry to edit")
    }

    private var icon: some View {
        ZStack {
            Circle().fill(entry.color.opacity(0.18))
            Image(systemName: entry.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(entry.color)
        }
        .frame(width: badge, height: badge)
        .accessibilityHidden(true)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title(unit: unit, now: now))
                .font(.mina(.body, weight: .medium))
                .foregroundStyle(MinaTheme.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            if let subtitle = entry.subtitle {
                Text(subtitle)
                    .font(.mina(.caption))
                    .foregroundStyle(MinaTheme.textMuted)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        }
    }

    private var times: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text(Format.time(entry.startedAt ?? now))
                .font(.mina(.subheadline, weight: .medium))
                .foregroundStyle(MinaTheme.textSecondary)
            if entry.kind == .sleep, let endedAt = entry.endedAt {
                Text("to \(Format.time(endedAt))")
                    .font(.mina(.caption2))
                    .foregroundStyle(MinaTheme.textMuted)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(MinaTheme.textMuted.opacity(0.7))
            .accessibilityHidden(true)
    }
}

/// A card of rows for one day, tappable to edit and long-pressable to delete.
struct EntryList: View {
    let entries: [LogEntry]
    let unit: VolumeUnit
    let now: Date
    let onEdit: (LogEntry) -> Void
    let onDelete: (LogEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.objectID) { index, entry in
                EntryRow(entry: entry, unit: unit, now: now)
                    .onTapGesture { onEdit(entry) }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { onEdit(entry) }
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(entry) }
                    }
                if index < entries.count - 1 {
                    Divider().padding(.leading, 66)
                }
            }
        }
        .minaCard(padding: 4)
    }
}
