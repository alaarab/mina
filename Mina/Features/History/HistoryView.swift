import CoreData
import SwiftUI

/// Everything ever logged, searchable and filterable, grouped by day. The
/// filter and the search text go into the fetch itself rather than filtering in
/// memory, and the fetch is batched, so a year of entries scrolls without ever
/// being loaded all at once.

// MARK: Filter

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, feeds, diapers, sleep, health, notes

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .feeds: return "Feeds"
        case .diapers: return "Diapers"
        case .sleep: return "Sleep"
        case .health: return "Health"
        case .notes: return "Notes"
        }
    }
    var kinds: [EntryKind]? {
        switch self {
        case .all: return nil
        case .feeds: return [.bottle, .nursing, .pumping]
        case .diapers: return [.diaper]
        case .sleep: return [.sleep, .tummyTime, .bath]
        case .health: return [.growth, .medicine, .temperature]
        case .notes: return [.note, .milestone]
        }
    }

    static func predicate(baby: Baby, filter: HistoryFilter, query: String) -> NSPredicate {
        var parts = [NSPredicate(format: "baby == %@", baby)]
        if let kinds = filter.kinds { parts.append(NSPredicate(format: "kindRaw IN %@", kinds.map(\.rawValue))) }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            var text = [NSPredicate(format: "note CONTAINS[cd] %@", trimmed), NSPredicate(format: "label CONTAINS[cd] %@", trimmed),
                        NSPredicate(format: "loggedBy CONTAINS[cd] %@", trimmed)]
            if let kind = EntryKind.allCases.first(where: { $0.title.lowercased().hasPrefix(trimmed.lowercased()) }) {
                text.append(NSPredicate(format: "kindRaw == %@", kind.rawValue))
            }
            if let diaper = DiaperKind.allCases.first(where: { $0.title.lowercased().hasPrefix(trimmed.lowercased()) }) {
                text.append(NSPredicate(format: "diaperRaw == %@", diaper.rawValue))
            }
            if let side = NursingSide.allCases.first(where: { $0.title.lowercased().hasPrefix(trimmed.lowercased()) }) {
                text.append(NSPredicate(format: "sideRaw == %@", side.rawValue))
            }
            parts.append(NSCompoundPredicate(orPredicateWithSubpredicates: text))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }
}

// MARK: Screen

struct HistoryView: View {
    @ObservedObject var baby: Baby
    @State private var filter: HistoryFilter = DebugLaunch.argument("-history-filter").flatMap(HistoryFilter.init(rawValue:)) ?? .all
    @State private var query = DebugLaunch.argument("-history-query") ?? ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HistoryFilter.allCases) { candidate in
                        Button {
                            withAnimation(.snappy) { filter = candidate }
                        } label: {
                            Text(candidate.title)
                                .font(.mina(.subheadline, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(filter == candidate ? MinaTheme.accent : MinaTheme.card, in: Capsule())
                                .overlay(Capsule().strokeBorder(filter == candidate ? .clear : MinaTheme.border, lineWidth: 1))
                                .foregroundStyle(filter == candidate ? .white : MinaTheme.text)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == candidate ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .background(MinaTheme.canvas)
            HistoryList(baby: baby, filter: filter, query: query)
                .id("\(filter.rawValue)|\(query)")
        }
        .minaCanvas()
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes, medicine, who logged it…")
    }
}

// MARK: List

private struct HistoryList: View {
    @ObservedObject var baby: Baby
    let filter: HistoryFilter
    let query: String

    @Environment(\.managedObjectContext) private var context
    @StoredVolumeUnit private var unit
    @FetchRequest private var entries: FetchedResults<LogEntry>
    @State private var editing: LogEntry?

    init(baby: Baby, filter: HistoryFilter, query: String) {
        _baby = ObservedObject(wrappedValue: baby)
        self.filter = filter
        self.query = query
        let request = LogEntry.request()
        request.predicate = HistoryFilter.predicate(baby: baby, filter: filter, query: query)
        request.fetchBatchSize = 60
        _entries = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        let now = Date.now
        // Index ranges, not arrays: the section headers must not undo the
        // batched fetch by pulling every entry into memory.
        let groups = DayGrouping.dayRuns(entries)
        List {
            if entries.isEmpty {
                Text(query.isEmpty ? "Nothing logged here yet." : "No matches for “\(query)”.")
                    .font(.mina(.subheadline)).foregroundStyle(MinaTheme.textMuted)
                    .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.day) { group in
                Section {
                    ForEach(group.range, id: \.self) { index in
                        let entry = entries[index]
                        EntryRow(entry: entry, unit: unit, now: now)
                            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 8))
                            .listRowBackground(MinaTheme.card)
                            .onTapGesture { editing = entry }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { try? Logbook.shared.delete(entry, in: context) } label: { Label("Delete", systemImage: "trash") }
                                Button { editing = entry } label: { Label("Edit", systemImage: "pencil") }.tint(MinaTheme.accent)
                            }
                    }
                } header: {
                    Text(Format.dayTitle(group.day, now: now) + (Calendar.current.isDate(group.day, equalTo: now, toGranularity: .year) ? "" : " " + group.day.formatted(.dateTime.year())))
                        .font(.mina(.subheadline, weight: .semibold)).foregroundStyle(MinaTheme.textSecondary).textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .scrollContentBackground(.hidden)
        .background(MinaTheme.canvas)
        .sheet(item: $editing) { EntryEditor(entry: $0) }
    }
}
