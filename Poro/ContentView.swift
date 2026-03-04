//
//  ContentView.swift
//  Poro
//
//  Created by Andrew Vong on 4/17/26.
//

import SwiftUI

struct ContentView: View {
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "Ready.")
    ]
    @State private var draftMessage = ""

    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        Text("\(message.role.label): \(message.text)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }

            HStack {
                TextField("Message", text: $draftMessage)
                .textFieldStyle(.roundedBorder)
                .onSubmit(sendMessage)

                Button("Send", action: sendMessage)
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

        messages.append(ChatMessage(role: .user, text: text))
        draftMessage = ""
        messages.append(ChatMessage(role: .assistant, text: "Not connected yet."))
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
