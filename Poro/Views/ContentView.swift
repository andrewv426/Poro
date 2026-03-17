//
//  ContentView.swift
//  Poro
//
//  Created by Andrew Vong on 4/17/26.
//

import SwiftUI

struct ContentView: View {
    @State private var chatController = ChatController()
    @State private var draftMessage = ""

    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(chatController.session.messages) { message in
                        Text("\(message.role.label): \(message.text)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }

            if case let .failed(message) = chatController.requestState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                TextField("Message", text: $draftMessage)
                .textFieldStyle(.roundedBorder)
                .onSubmit(sendMessage)
                .disabled(chatController.requestState.isSending)

                Button(chatController.requestState.isSending ? "Waiting..." : "Send", action: sendMessage)
                    .disabled(chatController.requestState.isSending)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 520)
    }

    private func sendMessage() {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            return
        }

        draftMessage = ""
        chatController.send(text)
    }
}

private extension ChatMessage.Role {
    var label: String {
        switch self {
        case .user:
            return "You"
        case .assistant:
            return "Poro"
        }
    }
}

#Preview {
    ContentView()
}
