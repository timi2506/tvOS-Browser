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
    
    init(manager: WebViewManager) {
        self.manager = manager
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(manager.keyboardPlaceholder.isEmpty ? "Webpage Text Input" : manager.keyboardPlaceholder)
                    .bold()
                
                TextField(manager.keyboardPlaceholder.isEmpty ? "Enter text..." : manager.keyboardPlaceholder, text: $text)
                    .autocorrectionDisabled()
                
                Divider()
                
                ScrollView(.horizontal) {
                    HStack(spacing: 15) {
                        Button("Submit & Enter", systemImage: "return") {
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
                        
                        Button("Cancel", systemImage: "xmark") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .scrollClipDisabled()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Keyboard")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        manager.submitKeyboardText(text, pressEnter: true)
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 1200, height: 700)
        .onAppear {
            text = manager.keyboardInputText
        }
    }
}
