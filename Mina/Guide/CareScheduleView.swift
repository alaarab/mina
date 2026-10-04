import CoreData
import SwiftUI

struct CareScheduleView: View {
    @ObservedObject var baby: Baby
    private let initialMonth: Int?
    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var completed: FetchedResults<LogEntry>
    @State private var error: String?

    init(baby: Baby, initialMonth: Int? = nil) {
        _baby = ObservedObject(wrappedValue: baby)
        self.initialMonth = initialMonth
        let request = LogEntry.request()
        request.predicate = NSPredicate(format: "baby == %@ AND kindRaw IN %@", baby, [EntryKind.vaccine.rawValue, EntryKind.checkup.rawValue])
        _completed = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section {
                Text("A planning checklist based on U.S. CDC and AAP schedules. Timing and needed doses vary; confirm every item with her clinician.")
                    .font(.mina(.footnote)).foregroundStyle(MinaTheme.textSecondary)
            }
            ForEach(CareSchedule.items) { item in
                let done = completed.contains { $0.kind == item.kind && $0.label == item.title }
                Button {
                    do {
                        try Logbook.shared.toggleCareItem(kind: item.kind, label: item.title, for: baby, in: context)
                        CareSchedule.scheduleReminders(for: baby, in: context)
                    } catch { self.error = error.localizedDescription }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? MinaTheme.diaper : item.kind.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.mina(.body, weight: .semibold)).foregroundStyle(MinaTheme.text)
                            if let birthDate = baby.birthDate {
                                Text(item.due(from: birthDate).formatted(date: .abbreviated, time: .omitted))
                                    .font(.mina(.caption, weight: .semibold)).foregroundStyle(item.kind.color)
                            }
                            Text(item.detail).font(.mina(.caption)).foregroundStyle(MinaTheme.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityValue([done ? "done" : "not done", baby.birthDate.map { item.due(from: $0).formatted(date: .abbreviated, time: .omitted) }, item.detail].compactMap { $0 }.joined(separator: ", "))
                .accessibilityHint(done ? "Removes completion from her log" : "Logs completion with today's date")
                .accessibilityAddTraits(.isToggle)
                .id(item.id)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .minaCanvas()
        .navigationTitle("Visits & vaccines")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert($error)
        .onAppear {
            if let initialMonth,
               let item = CareSchedule.items.first(where: { ($0.months ?? 0) >= initialMonth }) {
                proxy.scrollTo(item.id, anchor: .top)
            }
        }
        }
    }
}
