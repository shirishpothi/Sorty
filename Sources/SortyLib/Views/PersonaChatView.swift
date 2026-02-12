//
//  PersonaChatView.swift
//  Sorty
//
//  Interactive chat interface for testing persona prompts with sample files
//

import SwiftUI

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role {
        case user, assistant, system
    }

    init(role: Role, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

struct PersonaChatView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    let promptModifier: String

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Test Persona")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button("Clear Chat") {
                    messages.removeAll()
                    errorMessage = nil
                }
                .buttonStyle(.bordered)
                .disabled(messages.isEmpty)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text("Describe some sample files to see how this persona would organize them.")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Text("Example: \"I have report.pdf, vacation.jpg, budget.xlsx\"")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                            .padding(.vertical, 40)
                        }

                        ForEach(messages) { message in
                            chatBubble(for: message)
                                .id(message.id)
                        }

                        if isLoading {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: isLoading) {
                    if isLoading {
                        withAnimation {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }

            if let errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        self.errorMessage = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }

            Divider()

            // Input area
            HStack(spacing: 8) {
                TextField("Describe sample files...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sendMessage()
                    }
                    .disabled(isLoading)

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 550, height: 400)
    }

    @ViewBuilder
    private func chatBubble(for message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer()
                Text(message.content)
                    .padding(10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .frame(maxWidth: 380, alignment: .trailing)
            }
        case .assistant:
            HStack {
                Text(message.content)
                    .padding(10)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(12)
                    .frame(maxWidth: 380, alignment: .leading)
                    .textSelection(.enabled)
                Spacer()
            }
        case .system:
            Text(message.content)
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
                .frame(maxWidth: .infinity)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        errorMessage = nil
        isLoading = true

        Task {
            do {
                let client = try AIClientFactory.createClient(config: settingsViewModel.config)

                let systemPrompt = """
                You are testing a file organization persona. The user will describe files they have, \
                and you should explain how this persona would organize them.

                Persona instructions:
                \(promptModifier)

                Respond concisely. Suggest folder structures and organization strategies based on the persona's rules. \
                Use short bullet points or a folder tree format.
                """

                let conversationContext = messages
                    .filter { $0.role != .system }
                    .map { msg in
                        let prefix = msg.role == .user ? "User" : "Assistant"
                        return "\(prefix): \(msg.content)"
                    }
                    .joined(separator: "\n")

                let response = try await client.generateText(
                    prompt: conversationContext,
                    systemPrompt: systemPrompt
                )

                let assistantMessage = ChatMessage(role: .assistant, content: response.trimmingCharacters(in: .whitespacesAndNewlines))
                messages.append(assistantMessage)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    PersonaChatView(promptModifier: "Organize files by project, keeping related assets together.")
        .environmentObject(SettingsViewModel())
}
