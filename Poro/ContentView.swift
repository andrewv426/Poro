//
//  ContentView.swift
//  Poro
//
//  Created by Andrew Vong on 4/17/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        //Vertical stack
        VStack(spacing: 20) {
            Image(systemName: "pawprint.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)

            Text("Poro")
                .font(.headline)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 250)
    }
}

#Preview {
    ContentView()
}
