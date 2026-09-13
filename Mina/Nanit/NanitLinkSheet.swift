import SwiftUI

/// Email and password, then the emailed code, then pick the baby.
///
/// The password exists only as `@State` on this sheet, only for as long as
/// Nanit's two-step login needs it, and is never written to disk, defaults, the
/// Keychain or a log. `clearCredentials()` wipes it the moment it is done with,
/// and again when the sheet goes away.
struct NanitLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var nanit = NanitSync.shared

    private enum Step { case credentials, code, baby }
    @State private var step: Step = .credentials
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var mfaToken: String?
    @State private var tokens: NanitTokens?
    @State private var babies: [NanitBaby] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .credentials:
                    Section {
                        TextField("Nanit email", text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password).textContentType(.password)
                    } footer: {
                        Text("Your password is sent to Nanit once and not kept. Mina keeps only the sign-in token, in the Keychain on this phone.")
                    }
                    Section {
                        Button { Task { await signIn() } } label: { row("Send me a code") }
                            .disabled(busy || email.isEmpty || password.isEmpty)
                    }
                case .code:
                    Section {
                        TextField("Code from the Nanit email", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    } footer: {
                        Text("Nanit just emailed a code to \(email).")
                    }
                    Section {
                        Button { Task { await verify() } } label: { row("Connect") }
                            .disabled(busy || code.count < 4)
                    }
                case .baby:
                    Section("Which camera?") {
                        ForEach(babies) { baby in
                            Button {
                                if let tokens {
                                    nanit.link(tokens: tokens, baby: baby)
                                    clearCredentials()
                                    dismiss()
                                }
                            } label: {
                                HStack { Text(baby.name); Spacer(); Image(systemName: "video.fill").foregroundStyle(MinaTheme.textMuted) }
                            }
                        }
                        if babies.isEmpty { Text("No babies on this Nanit account.").foregroundStyle(MinaTheme.textMuted) }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(MinaTheme.danger).font(.mina(.footnote)) }
                }
            }
            .navigationTitle("Connect Nanit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onDisappear { clearCredentials() }
    }

    /// Nothing secret outlives the sheet, whether linking worked or not.
    private func clearCredentials() {
        password = ""
        code = ""
        mfaToken = nil
        tokens = nil
    }

    private func row(_ title: String) -> some View {
        HStack { Text(title); if busy { Spacer(); ProgressView() } }
    }

    private func signIn() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            switch try await nanit.client.login(email: email, password: password) {
            case .needsCode(let token): mfaToken = token; step = .code
            case .tokens(let tokens): await loadBabies(tokens)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func verify() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            switch try await nanit.client.login(email: email, password: password, mfaToken: mfaToken, code: code) {
            case .tokens(let tokens): await loadBabies(tokens)
            case .needsCode(let token):
                mfaToken = token
                code = ""
                self.error = "Nanit asked for another code. Check your email."
            }
        } catch { self.error = error.localizedDescription }
    }

    private func loadBabies(_ tokens: NanitTokens) async {
        self.tokens = tokens
        // Past this point the token does the talking, so drop the password and
        // the one-time code even if listing the cameras fails.
        password = ""
        code = ""
        mfaToken = nil
        do {
            babies = try await nanit.client.babies(token: tokens.accessToken)
            step = .baby
        } catch { self.error = error.localizedDescription }
    }
}
