import SwiftUI

struct EntryRow: View {
    @ObservedObject var entry: LogEntry
    let unit: VolumeUnit
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(entry.color.opacity(0.18))
                Image(systemName: entry.kind.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(entry.color)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title(unit: unit, now: now))
                    .font(.mina(.body, weight: .medium))
                    .foregroundStyle(MinaTheme.text)
                    .lineLimit(2)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.mina(.caption))
                        .foregroundStyle(MinaTheme.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.time(entry.startedAt ?? now))
                    .font(.mina(.subheadline, weight: .medium))
                    .foregroundStyle(MinaTheme.textSecondary)
                if entry.kind == .sleep, let endedAt = entry.endedAt {
                    Text("to \(Format.time(endedAt))")
                        .font(.mina(.caption2))
                        .foregroundStyle(MinaTheme.textMuted)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MinaTheme.textMuted.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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
