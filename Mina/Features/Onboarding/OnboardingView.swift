import SwiftUI

/// The first screen on a fresh install: a name, a birthday, and one button that
/// creates the baby. The partner never sees it; they open the share link
/// instead, which is what the card at the bottom is there to say.

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

                    HStack(spacing: 14) {
                        Image(systemName: "envelope.open.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(MinaTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(MinaTheme.cardTint, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Got an invite?")
                                .font(.mina(.headline))
                            Text("Open the link from Messages and the shared log appears.")
                                .font(.mina(.footnote))
                                .foregroundStyle(MinaTheme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .minaCard()
                }
                .padding(20)
            }
            .minaCanvas()
            .errorAlert($error)
        }
    }

    // MARK: Actions

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            try Logbook.shared.createBaby(name: trimmed.isEmpty ? "Baby" : trimmed, birthDate: birthDate, in: context)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
