import Foundation

@MainActor
public final class SubscriptionAuthManager: ObservableObject {

    let provider: AIProvider
    private let codexAuthManager: CodexCLIAuthManager

    @Published var isAuthenticated = false
    @Published var accountLabel: String?
    @Published var authError: String?

    public init(provider: AIProvider, codexAuthManager: CodexCLIAuthManager) {
        self.provider = provider
        self.codexAuthManager = codexAuthManager
        checkAuthenticationStatus()
    }

    var hasAccountSession: Bool {
        isAuthenticated
    }

    var accountStatusText: String {
        guard isAuthenticated else {
            return "Not signed in via Codex CLI"
        }
        if let accountLabel, !accountLabel.isEmpty {
            return "Signed in as \(accountLabel)"
        }
        return "Signed in via Codex CLI"
    }

    func checkAuthenticationStatus() {
        guard provider == .openAI else {
            isAuthenticated = false
            accountLabel = nil
            return
        }

        let codex = codexAuthManager
        codex.checkStatus()
        isAuthenticated = codex.isAuthenticated
        accountLabel = codex.accountEmail
    }

    func signOut() {
        guard provider == .openAI else { return }
        codexAuthManager.signOut()
        isAuthenticated = false
        accountLabel = nil
    }
}

extension AIProvider {
    var subscriptionProductName: String {
        switch self {
        case .openAI:
            return "ChatGPT"
        default:
            return displayName
        }
    }
}
