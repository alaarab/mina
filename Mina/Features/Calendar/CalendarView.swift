import CoreData
import SwiftUI

/// Month grid math, kept pure so it can be tested.
enum MonthGrid {
    /// 7-wide rows of days, nil for padding cells outside the month.
    static func cells(for month: Date, calendar: Calendar = .current) -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}

struct CalendarView: View {
    @ObservedObject var baby: Baby

    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selected = Calendar.current.startOfDay(for: .now)

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    MonthSection(baby: baby, month: month, selected: $selected)
                        .id(month)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(MinaTheme.canvas.ignoresSafeArea())
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Today") { jumpToToday() }
                        .font(.mina(.subheadline, weight: .semibold))
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).frame(width: 40, height: 40)
            }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.mina(.title3, weight: .bold))
                .foregroundStyle(MinaTheme.text)
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)).frame(width: 40, height: 40)
            }
            .disabled(calendar.compare(month, to: .now, toGranularity: .month) != .orderedAscending)
        }
        .padding(.top, 4)
    }

    private func shift(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        withAnimation(.snappy) {
            month = next
            if let interval = calendar.dateInterval(of: .month, for: next) {
                let today = calendar.startOfDay(for: .now)
                selected = interval.contains(today) ? today : interval.start
            }
        }
    }

    private func jumpToToday() {
        withAnimation(.snappy) {
            month = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
            selected = calendar.startOfDay(for: .now)
        }
    }
}

private struct MonthSection: View {
    @ObservedObject var baby: Baby
    let month: Date
    @Binding var selected: Date

    @Environment(\.managedObjectContext) private var context
    @AppStorage(Prefs.unitKey, store: Prefs.defaults) private var unitRaw = VolumeUnit.ounces.rawValue
    @FetchRequest private var entries: FetchedResults<LogEntry>
    @State private var editing: LogEntry?
    @State private var error: String?

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var calendar: Calendar { .current }

    init(baby: Baby, month: Date, selected: Binding<Date>) {
        _baby = ObservedObject(wrappedValue: baby)
        self.month = month
        _selected = selected
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -1, to: month) ?? month
        let end = calendar.date(byAdding: .month, value: 1, to: month) ?? month
        _entries = FetchRequest(fetchRequest: LogEntry.request(for: baby, from: start, to: end), animation: .default)
    }

    var body: some View {
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.startedAt ?? .distantPast) }
        let now = Date.now
        VStack(spacing: 16) {
            grid(byDay: byDay, now: now)
            dayDetail(byDay[selected] ?? [], now: now)
        }
        .sheet(item: $editing) { EntryEditor(entry: $0) }
        .alert("Couldn't delete", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func grid(byDay: [Date: [LogEntry]], now: Date) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let today = calendar.startOfDay(for: now)
        return LazyVGrid(columns: columns, spacing: 4) {
            // Weekday letters repeat (S, T), so the position is the identity.
            ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.mina(.caption2, weight: .semibold))
                    .foregroundStyle(MinaTheme.textMuted)
                    .frame(height: 20)
            }
            ForEach(Array(MonthGrid.cells(for: month).enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(day: day, entries: byDay[day] ?? [], isSelected: day == selected, isToday: day == today, isFuture: day > today)
                        .onTapGesture { withAnimation(.snappy) { selected = day } }
                } else {
                    Color.clear.frame(height: 54)
                }
            }
        }
        .minaCard(padding: 10)
    }

    private func dayDetail(_ dayEntries: [LogEntry], now: Date) -> some View {
        let summary = DaySummary(entries: entries.filter { entry in
            // Include the previous day's sleep so an overnight stretch is clipped in, not dropped.
            guard let startedAt = entry.startedAt else { return false }
            return startedAt < (calendar.date(byAdding: .day, value: 1, to: selected) ?? selected) && startedAt >= (calendar.date(byAdding: .day, value: -1, to: selected) ?? selected)
        }, day: selected, now: now)
        let sorted = dayEntries.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(Format.dayTitle(selected, now: now) + (calendar.isDate(selected, inSameDayAs: now) ? "" : ", " + selected.formatted(.dateTime.year())))
                .font(.mina(.headline))
                .padding(.horizontal, 4)
            HStack(spacing: 10) {
                SummaryPill(symbol: EntryKind.bottle.symbol, color: MinaTheme.bottle,
                            text: "\(summary.feeds) \(summary.feeds == 1 ? "feed" : "feeds")" + (summary.bottleML > 0 ? " · \(unit.format(ml: summary.bottleML))" : ""))
                SummaryPill(symbol: EntryKind.diaper.symbol, color: MinaTheme.diaper, text: "\(summary.wet) wet · \(summary.dirty) dirty")
                SummaryPill(symbol: EntryKind.sleep.symbol, color: MinaTheme.sleep, text: summary.sleepSeconds > 0 ? Format.duration(summary.sleepSeconds) : "no sleep logged")
            }
            if sorted.isEmpty {
                Text("Nothing logged this day.")
                    .font(.mina(.subheadline))
                    .foregroundStyle(MinaTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .minaCard()
            } else {
                EntryList(entries: sorted, unit: unit, now: now, onEdit: { editing = $0 }) { entry in
                    do { try Logbook.shared.delete(entry, in: context) } catch { self.error = error.localizedDescription }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let entries: [LogEntry]
    let isSelected: Bool
    let isToday: Bool
    let isFuture: Bool

    private var kinds: [Color] {
        var colors: [Color] = []
        if entries.contains(where: { $0.kind.isFeed }) { colors.append(MinaTheme.bottle) }
        if entries.contains(where: { $0.kind == .diaper }) { colors.append(MinaTheme.diaper) }
        if entries.contains(where: { $0.kind == .sleep }) { colors.append(MinaTheme.sleep) }
        if entries.contains(where: { $0.kind == .note || EntryKind.extras.contains($0.kind) }) { colors.append(MinaTheme.note) }
        return colors
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.mina(.callout, weight: isSelected || isToday ? .bold : .medium))
                .foregroundStyle(isSelected ? .white : (isFuture ? MinaTheme.textMuted : MinaTheme.text))
                .frame(width: 34, height: 34)
                .background(isSelected ? MinaTheme.accent : .clear, in: Circle())
                .overlay(Circle().strokeBorder(isToday && !isSelected ? MinaTheme.accent : .clear, lineWidth: 1.5))
            HStack(spacing: 3) {
                ForEach(Array(kinds.enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .contentShape(Rectangle())
        .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted))
    }
}

private struct SummaryPill: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            Text(text)
                .font(.mina(.caption2, weight: .medium))
                .foregroundStyle(MinaTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(MinaTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MinaTheme.border, lineWidth: 1))
    }
}
