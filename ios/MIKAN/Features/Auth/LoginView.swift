import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var login = ""
    @State private var password = ""
    @State private var server = ServerConfig.savedAddress
    @State private var showsServer = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var failureCount = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case login
        case password
        case server
    }

    private var canSubmit: Bool {
        !login.trimmed.isEmpty && !password.isEmpty && !server.trimmed.isEmpty && !isSubmitting
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 36) {
                    Spacer(minLength: 0)
                    header
                    form
                    serverSection
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { LoginBackdrop() }
        .errorAlert($errorMessage, title: "Не удалось войти")
        .sensoryFeedback(.error, trigger: failureCount)
        .onAppear {
            if let notice = appState.signOutNotice {
                errorMessage = notice
                appState.signOutNotice = nil
            }
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                BrandLogo(height: 44)
                Text("STUDIO")
                    .font(.subheadline.weight(.regular))
                    .kerning(10)
                    .foregroundStyle(.secondary)
            }
            Text("Тату и пирсинг · рабочее приложение")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MIKAN STUDIO, рабочее приложение")
        .accessibilityAddTraits(.isHeader)
    }

    private var form: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                inputRow(symbol: "person.fill") {
                    TextField("Логин", text: $login)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .login)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                }
                inputRow(symbol: "lock.fill") {
                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                }
                Button(action: submit) {
                    ZStack {
                        Text("Войти").opacity(isSubmitting ? 0 : 1)
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!canSubmit)
                .padding(.top, 6)
            }
        }
    }

    private func inputRow<Content: View>(symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            content()
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 54)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private var serverSection: some View {
        DisclosureGroup(isExpanded: $showsServer) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("https://…", text: $server)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .server)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                HStack(alignment: .firstTextBaseline) {
                    Text("Адрес сервера студии. Меняйте, только если вам его дали.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if server.trimmed != ServerConfig.defaultAddress {
                        Button("Сбросить") { server = ServerConfig.defaultAddress }
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Сервер", systemImage: "server.rack")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await appState.signIn(login: login, password: password, server: server)
            } catch {
                errorMessage = error.userMessage
                failureCount += 1
            }
        }
    }
}

/// Soft mandarin light blobs for the glass fields to refract.
private struct LoginBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemBackground)
            Circle()
                .fill(Theme.mandarin.opacity(colorScheme == .dark ? 0.55 : 0.42))
                .frame(width: 440)
                .blur(radius: 90)
                .offset(x: -150, y: -320)
            Circle()
                .fill(Theme.mandarinLight.opacity(colorScheme == .dark ? 0.35 : 0.5))
                .frame(width: 360)
                .blur(radius: 100)
                .offset(x: 170, y: -140)
            Circle()
                .fill(Theme.mandarinDeep.opacity(colorScheme == .dark ? 0.35 : 0.22))
                .frame(width: 400)
                .blur(radius: 120)
                .offset(x: 130, y: 380)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Вход") {
    LoginView()
        .appEnvironment(AppState(api: APIClient(serverURL: URL(string: "http://localhost:3000")!), employee: nil, phase: .signedOut))
}
#endif
