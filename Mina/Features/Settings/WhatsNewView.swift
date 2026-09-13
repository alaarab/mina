import SwiftUI

/// The changelog, parsed from CHANGELOG.md in the bundle. Shown once after an
/// update (the newest section only) and any time from Settings (all of it).
struct ChangelogSection: Identifiable {
    let id: String          // "0.0.16"
    let version: String     // same
    let groups: [(title: String, items: [String])]
}

enum Changelog {
    static let seenKey = "whatsNew.seenVersion"

    static var sections: [ChangelogSection] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [ChangelogSection] = []
        var heading = ""; var groups: [(String, [String])] = []; var group = ""
        func flush() {
            if !heading.isEmpty { result.append(ChangelogSection(id: heading, version: heading.split(separator: " ").first.map(String.init) ?? heading, groups: groups.map { ($0.0, $0.1) })) }
            heading = ""; groups = []; group = ""
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") { flush(); heading = String(line.dropFirst(3)) }
            else if line.hasPrefix("### ") { group = String(line.dropFirst(4)); groups.append((group, [])) }
            else if line.hasPrefix("- "), !heading.isEmpty {
                if groups.isEmpty { groups.append(("", [])) }
                groups[groups.count - 1].1.append(String(line.dropFirst(2)))
            }
        }
        flush()
        return result
    }

    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    /// True the first time this version runs, when there is something to show.
    static var shouldShow: Bool {
        guard let newest = sections.first, newest.version == current else { return false }
        return Prefs.defaults.string(forKey: seenKey) != current
    }

    static func markSeen() { Prefs.defaults.set(current, forKey: seenKey) }
}

struct WhatsNewView: View {
    var onlyNewest = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(onlyNewest ? Array(Changelog.sections.prefix(1)) : Changelog.sections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(onlyNewest ? "What's new in \(section.version)" : section.id)
                                .font(.mina(onlyNewest ? .title : .title3, weight: .bold))
                            ForEach(Array(section.groups.enumerated()), id: \.offset) { _, group in
                                if !group.title.isEmpty {
                                    Text(group.title).font(.mina(.headline)).foregroundStyle(group.title == "Fixed" ? MinaTheme.textSecondary : MinaTheme.accent)
                                }
                                ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                                    HStack(alignment: .top, spacing: 10) {
                                        Circle().fill(group.title == "Fixed" ? MinaTheme.textMuted : MinaTheme.accent).frame(width: 6, height: 6).padding(.top, 7)
                                        Text(item).font(.mina(.subheadline)).foregroundStyle(MinaTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .minaCard()
                    }
                    if onlyNewest {
                        Button { Changelog.markSeen(); dismiss() } label: {
                            Text("Got it").font(.mina(.headline)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
                .padding(16)
            }
            .minaCanvas()
            .navigationTitle(onlyNewest ? "" : "What's new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onlyNewest { ToolbarItem(placement: .cancellationAction) { Button("Later") { Changelog.markSeen(); dismiss() } } }
            }
        }
    }
}
