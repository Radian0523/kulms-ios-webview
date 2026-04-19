import SwiftUI
import WebKit

/// ECS-ID/パスワードを入力する独自ログイン画面。
struct CredentialLoginView: View {
    @EnvironmentObject private var appState: AppState

    let onRequireWebViewLogin: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var savePassword = true
    @State private var passwordVisible = false
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var didAutoLogin = false
    @FocusState private var focusedField: Field?

    enum Field { case username, password }

    var body: some View {
        ZStack {
            HiddenWebView()
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)

            credentialForm
        }
    }

    private var credentialForm: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                VStack(spacing: 8) {
                    Text("KULMS+")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text(String(localized: "loginSubtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)

                VStack(alignment: .leading, spacing: 16) {
                    // Username
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "labelUsername"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("a0123456", text: $username)
                            .textContentType(.username)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .username)
                            .onSubmit { focusedField = .password }
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .disabled(isSubmitting)
                    }

                    // Password
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "labelPassword"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Group {
                                if passwordVisible {
                                    TextField(String(localized: "labelPassword"), text: $password)
                                        .textContentType(.password)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                } else {
                                    SecureField(String(localized: "labelPassword"), text: $password)
                                        .textContentType(.password)
                                }
                            }
                            .submitLabel(.go)
                            .focused($focusedField, equals: .password)
                            .onSubmit { submit() }
                            .disabled(isSubmitting)

                            Button {
                                passwordVisible.toggle()
                            } label: {
                                Image(systemName: passwordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Save password toggle
                    Toggle(isOn: $savePassword) {
                        Text(String(localized: "savePassword"))
                            .font(.subheadline)
                    }
                    .disabled(isSubmitting)

                    // Error
                    if let error = errorText {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Login button
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                                Text(String(localized: "loggingIn"))
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(String(localized: "login"))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSubmitting || username.isEmpty || password.isEmpty)
                    .padding(.top, 8)
                }

                Divider().padding(.vertical, 24)

                VStack(spacing: 4) {
                    Button {
                        onRequireWebViewLogin()
                    } label: {
                        Text(String(localized: "loginBrowser"))
                    }
                    .disabled(isSubmitting)

                    Text(String(localized: "loginBrowserDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            tryAutoLogin()
        }
        .onChange(of: appState.isLoggedIn) { _, newValue in
            if newValue == false {
                didAutoLogin = false
                tryAutoLogin()
            }
        }
    }

    private func submit() {
        guard !isSubmitting, !username.isEmpty, !password.isEmpty else { return }
        focusedField = nil
        Task { await performLogin(saveOnSuccess: savePassword) }
    }

    private func tryAutoLogin() {
        guard !didAutoLogin else { return }
        didAutoLogin = true
        if let creds = CredentialStore.load() {
            username = creds.username
            password = creds.password
            Task { await performLogin(saveOnSuccess: true) }
        }
    }

    @MainActor
    private func performLogin(saveOnSuccess: Bool) async {
        isSubmitting = true
        errorText = nil

        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await WebViewManager.shared.loginWithCredentials(
            username: trimmedUser,
            password: password
        )

        switch result {
        case .success:
            if saveOnSuccess {
                CredentialStore.save(username: trimmedUser, password: password)
            }
            appState.isLoggedIn = true
            isSubmitting = false
        case .otpRequired:
            if saveOnSuccess {
                CredentialStore.save(username: trimmedUser, password: password)
            }
            isSubmitting = false
            onRequireWebViewLogin()
        case .failed(let msg):
            errorText = msg
            isSubmitting = false
        }
    }
}

// MARK: - Hidden WKWebView wrapper

private struct HiddenWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        WebViewManager.shared.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
