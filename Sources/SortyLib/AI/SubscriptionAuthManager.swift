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

    public func checkAuthenticationStatus() {
        guard provider == .openAI else {
            isAuthenticated = false
            accountLabel = nil
            return
        }

        let codex = codexAuthManager
        // `refreshStatus()` performs its blocking Codex CLI probes off the main
        // thread; await it so we mirror the resolved state instead of reading
        // stale values, while keeping the main thread free during launch.
        Task { [weak self] in
            await codex.refreshStatus()
            guard let self else { return }
            self.synchronizeWithCodexStatus()
        }
    }

    /// Mirrors the already-resolved Codex state without launching another CLI probe.
    func synchronizeWithCodexStatus() {
        guard provider == .openAI else { return }
        if isAuthenticated != codexAuthManager.isAuthenticated {
            isAuthenticated = codexAuthManager.isAuthenticated
        }
        if accountLabel != codexAuthManager.accountEmail {
            accountLabel = codexAuthManager.accountEmail
        }
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
