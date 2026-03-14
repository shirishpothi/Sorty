import Foundation
import AppKit

@MainActor
final class SubscriptionAuthManager: ObservableObject {
    static let openAI = SubscriptionAuthManager(provider: .openAI)

    let provider: AIProvider

    @Published var isAuthenticated = false
    @Published var accountLabel: String?
    @Published var authError: String?

    init(provider: AIProvider) {
        self.provider = provider
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

        let codex = CodexCLIAuthManager.shared
        codex.checkStatus()
        isAuthenticated = codex.isAuthenticated
        accountLabel = codex.accountEmail
    }

    func signOut() {
        guard provider == .openAI else { return }
        CodexCLIAuthManager.shared.signOut()
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
