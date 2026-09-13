import Charts
import CoreData
import SwiftUI

/// Fourteen days of charts, a seven-day average, the growth entries, and the
/// one-page PDF those all fold into for the pediatrician. `TrendMath` turns the
/// fetched entries into a row per day; everything below it just draws.

// MARK: Day rows

/// One row per day for the charts and the report.
struct DayStat: Identifiable {
    let day: Date
    let summary: DaySummary
    let longestSleep: TimeInterval
    var id: Date { day }
}

enum TrendMath {
    static func stats(entries: [LogEntry], days: Int, now: Date = .now, calendar: Calendar = .current) -> [DayStat] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset -> DayStat? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let summary = DaySummary(entries: entries, day: day, now: now, calendar: calendar)
            let longest = entries
                .filter { $0.kind == .sleep && $0.endedAt != nil && ($0.startedAt ?? .distantPast) >= day && ($0.startedAt ?? .distantPast) < end }
                .map { $0.duration(now: now) ?? 0 }
                .max() ?? 0
            return DayStat(day: day, summary: summary, longestSleep: longest)
        }
    }

    static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: Screen

struct TrendsView: View {
    @ObservedObject var baby: Baby
    @StoredVolumeUnit private var unit
    @FetchRequest private var entries: FetchedResults<LogEntry>
    @State private var reportURL: URL?
    @State private var asking = false

    private static let days = 14

    init(baby: Baby) {
        _baby = ObservedObject(wrappedValue: baby)
        let start = Calendar.current.date(byAdding: .day, value: -Self.days, to: Calendar.current.startOfDay(for: .now)) ?? .now
        _entries = FetchRequest(fetchRequest: LogEntry.request(for: baby, from: start), animation: .default)
    }

    var body: some View {
        let stats = TrendMath.stats(entries: Array(entries), days: Self.days)
        let week = Array(stats.suffix(7))
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekSummary(week)
                    feedChart(stats)
                    sleepChart(stats)
                    diaperChart(stats)
                    growthList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .minaCanvas()
            .navigationTitle("Trends")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { asking = true } label: { Label("Ask", systemImage: "sparkles") }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let reportURL {
                        ShareLink(item: reportURL, subject: Text("\(baby.displayName)'s week")) {
                            Label("Share report", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .task(id: entries.count) { reportURL = await Report.render(baby: baby, stats: week, entries: Array(entries), unit: unit) }
            .sheet(isPresented: $asking) {
                AskView(baby: baby, stats: stats, recent: entries.prefix(12).map { "\(($0.startedAt ?? .now).formatted(.dateTime.weekday(.abbreviated).hour().minute())): \($0.title(unit: unit))" }, unit: unit)
            }
        }
    }

    // MARK: Subviews

    private func weekSummary(_ week: [DayStat]) -> some View {
        let feeds = TrendMath.average(week.map { Double($0.summary.feeds) })
        let ml = TrendMath.average(week.map(\.summary.bottleML))
        let sleep = TrendMath.average(week.map(\.summary.sleepSeconds))
        let wet = TrendMath.average(week.map { Double($0.summary.wet) })
        let dirty = TrendMath.average(week.map { Double($0.summary.dirty) })
        let longest = week.map(\.longestSleep).max() ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("Last 7 days, per day").font(.mina(.headline))
            HStack(spacing: 10) {
                StatTile(title: "Feeds", value: String(format: "%.1f", feeds), color: MinaTheme.bottle, detail: ml > 0 ? "\(unit.format(ml: ml)) by bottle" : "no bottles", expect: nil)
                StatTile(title: "Diapers", value: String(format: "%.1f", wet + dirty), color: MinaTheme.diaper, detail: String(format: "%.1f wet · %.1f dirty", wet, dirty), expect: nil)
                StatTile(title: "Sleep", value: Format.duration(sleep), color: MinaTheme.sleep, detail: "longest \(Format.duration(longest))", expect: nil)
            }
        }
    }

    private func feedChart(_ stats: [DayStat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bottle \(unit.symbol) per day").font(.mina(.headline))
            Chart(stats) { stat in
                BarMark(x: .value("Day", stat.day, unit: .day), y: .value(unit.symbol, unit.display(ml: stat.summary.bottleML)))
                    .foregroundStyle(MinaTheme.bottle)
                    .cornerRadius(4)
                if stat.summary.feeds > 0 {
                    PointMark(x: .value("Day", stat.day, unit: .day), y: .value(unit.symbol, unit.display(ml: stat.summary.bottleML)))
                        .annotation(position: .top) { Text("\(stat.summary.feeds)").font(.mina(.caption2)).foregroundStyle(MinaTheme.textMuted) }
                        .opacity(0)
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day()) } }
            .frame(height: 160)
            Text("Number above each bar is the feed count, nursing included.").font(.mina(.caption2)).foregroundStyle(MinaTheme.textMuted)
        }
        .minaCard()
    }

    private func sleepChart(_ stats: [DayStat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep hours per day").font(.mina(.headline))
            Chart(stats) { stat in
                BarMark(x: .value("Day", stat.day, unit: .day), y: .value("Hours", stat.summary.sleepSeconds / 3600))
                    .foregroundStyle(MinaTheme.sleep.opacity(0.45))
                    .cornerRadius(4)
                LineMark(x: .value("Day", stat.day, unit: .day), y: .value("Longest", stat.longestSleep / 3600))
                    .foregroundStyle(MinaTheme.sleep)
                    .interpolationMethod(.catmullRom)
                    .symbol(.circle)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day()) } }
            .frame(height: 160)
            Text("Bars are total sleep; the line is her longest single stretch.").font(.mina(.caption2)).foregroundStyle(MinaTheme.textMuted)
        }
        .minaCard()
    }

    private func diaperChart(_ stats: [DayStat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diapers per day").font(.mina(.headline))
            Chart(stats) { stat in
                BarMark(x: .value("Day", stat.day, unit: .day), y: .value("Wet", stat.summary.wet))
                    .foregroundStyle(MinaTheme.diaper)
                BarMark(x: .value("Day", stat.day, unit: .day), y: .value("Dirty", stat.summary.dirty))
                    .foregroundStyle(MinaTheme.diaperDirty)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day()) } }
            .frame(height: 140)
            HStack(spacing: 12) {
                Label("Wet", systemImage: "circle.fill").foregroundStyle(MinaTheme.diaper)
                Label("Dirty", systemImage: "circle.fill").foregroundStyle(MinaTheme.diaperDirty)
            }
            .font(.mina(.caption2))
        }
        .minaCard()
    }

    private var growthList: some View {
        let growth = entries.filter { $0.kind == .growth }
        return Group {
            if !growth.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Growth").font(.mina(.headline))
                    ForEach(growth) { entry in
                        HStack {
                            Text(entry.title(unit: unit)).font(.mina(.subheadline))
                            Spacer()
                            Text((entry.startedAt ?? .now).formatted(date: .abbreviated, time: .omitted)).font(.mina(.caption)).foregroundStyle(MinaTheme.textMuted)
                        }
                    }
                }
                .minaCard()
            }
        }
    }
}

// MARK: Report

/// A one-page PDF for the pediatrician, rendered from a SwiftUI view.
enum Report {
    @MainActor
    static func render(baby: Baby, stats: [DayStat], entries: [LogEntry], unit: VolumeUnit) async -> URL? {
        let view = ReportPage(babyName: baby.displayName, age: baby.ageDescription(), stats: stats, entries: entries, unit: unit)
            .frame(width: 612)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = .init(width: 612, height: nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(baby.displayName)-week.pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        renderer.render { size, draw in
            var page = CGRect(x: 0, y: 0, width: 612, height: max(792, size.height + 40))
            context.beginPage(mediaBox: &page)
            context.translateBy(x: 0, y: page.height - size.height - 20)
            draw(context)
            context.endPage()
        }
        context.closePDF()
        return url
    }
}

private struct ReportPage: View {
    let babyName: String
    let age: String
    let stats: [DayStat]
    let entries: [LogEntry]
    let unit: VolumeUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(babyName), \(age)").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Log for \(stats.first.map { $0.day.formatted(date: .abbreviated, time: .omitted) } ?? "") to \(stats.last.map { $0.day.formatted(date: .abbreviated, time: .omitted) } ?? "")")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    ForEach(["Day", "Feeds", "Bottle", "Nursing", "Wet", "Dirty", "Sleep", "Longest"], id: \.self) { Text($0).font(.system(size: 11, weight: .semibold)) }
                }
                Divider()
                ForEach(stats) { stat in
                    GridRow {
                        Text(stat.day.formatted(.dateTime.weekday(.abbreviated).day()))
                        Text("\(stat.summary.feeds)")
                        Text(unit.format(ml: stat.summary.bottleML))
                        Text(stat.summary.nursingSeconds > 0 ? Format.duration(stat.summary.nursingSeconds) : "–")
                        Text("\(stat.summary.wet)")
                        Text("\(stat.summary.dirty)")
                        Text(Format.duration(stat.summary.sleepSeconds))
                        Text(Format.duration(stat.longestSleep))
                    }
                    .font(.system(size: 11))
                }
            }
            let growth = entries.filter { $0.kind == .growth }
            if !growth.isEmpty {
                Text("Growth").font(.system(size: 14, weight: .semibold))
                ForEach(growth) { entry in
                    Text("\((entry.startedAt ?? .now).formatted(date: .abbreviated, time: .omitted)): \(entry.title(unit: unit))").font(.system(size: 11))
                }
            }
            let medicine = entries.filter { $0.kind == .medicine || $0.kind == .temperature }
            if !medicine.isEmpty {
                Text("Medicine and temperature").font(.system(size: 14, weight: .semibold))
                ForEach(medicine.prefix(20)) { entry in
                    Text("\((entry.startedAt ?? .now).formatted(date: .abbreviated, time: .shortened)): \(entry.title(unit: unit))").font(.system(size: 11))
                }
            }
            let notes = entries.filter { $0.kind == .note || $0.kind == .milestone }
            if !notes.isEmpty {
                Text("Notes and milestones").font(.system(size: 14, weight: .semibold))
                ForEach(notes.prefix(15)) { entry in
                    Text("\((entry.startedAt ?? .now).formatted(date: .abbreviated, time: .omitted)): \(entry.title(unit: unit))").font(.system(size: 11))
                }
            }
            Text("Made with Mina").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(36)
        .background(Color.white)
        .foregroundStyle(.black)
    }
}
