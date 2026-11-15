//
//  KeyboardInputSheet.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import SwiftUI

struct KeyboardInputSheet: View {
    @ObservedObject var manager: WebViewManager
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                Text(text.isEmpty ? (manager.keyboardPlaceholder.isEmpty ? "Enter text..." : manager.keyboardPlaceholder) : text)
                    .font(.title2)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .minimumScaleFactor(0.25)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .searchable(text: $text, prompt: manager.keyboardPlaceholder.isEmpty ? "Enter text..." : manager.keyboardPlaceholder)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 20) {
                    Button("Submit", systemImage: "return") {
                        manager.submitKeyboardText(text, pressEnter: true)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Just Type", systemImage: "text.cursor") {
                        manager.submitKeyboardText(text, pressEnter: false)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Clear", systemImage: "trash") {
                        text = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(text.isEmpty)
                    
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .contentShape(.rect)
                .focusSection()
            }
            .onSubmit(of: .search) {
                manager.submitKeyboardText(text, pressEnter: true)
                dismiss()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            text = manager.keyboardInputText
        }
    }
}
