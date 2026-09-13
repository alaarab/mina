import SwiftUI

struct OnboardingView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var sync: SyncMonitor
    @State private var name = "Mina"
    @State private var birthDate = Calendar.current.startOfDay(for: .now)
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(MinaTheme.accent)
                        .padding(.top, 40)
                    VStack(spacing: 8) {
                        Text("Welcome, little one")
                            .font(.mina(.largeTitle, weight: .bold))
                        Text("Log feeds, diapers and sleep. Share once with your partner and you both see the same log on your own phones.")
                            .font(.mina(.body))
                            .foregroundStyle(MinaTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 14) {
                        TextField("Baby's name", text: $name)
                            .font(.mina(.title3, weight: .semibold))
                            .textFieldStyle(.roundedBorder)
                        DatePicker("Birthday", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                            .font(.mina(.body))
                    }
                    .minaCard()

                    Button {
                        create()
                    } label: {
                        Text("Start \(name.trimmingCharacters(in: .whitespaces).isEmpty ? "the" : name + "'s") log")
                            .font(.mina(.headline))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    VStack(spacing: 6) {
                        Text("Got an invite?")
                            .font(.mina(.headline))
                        Text("Open the link your partner sent in Messages. The app opens with the shared log, so there's no need to create a second one here.")
                            .font(.mina(.footnote))
                            .foregroundStyle(MinaTheme.textMuted)
                            .multilineTextAlignment(.center)
                        Text(sync.statusText)
                            .font(.mina(.caption2))
                            .foregroundStyle(MinaTheme.textMuted)
                    }
                    .minaCard()
                }
                .padding(20)
            }
            .background(MinaTheme.canvas.ignoresSafeArea())
            .alert("Couldn't save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            try Logbook.shared.createBaby(name: trimmed.isEmpty ? "Baby" : trimmed, birthDate: birthDate, in: context)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
