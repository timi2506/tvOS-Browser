//
//  OnboardingView.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    var onFinish: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 22) {
                    ShortcutRow(icon: "circle.inset.filled", title: "Clickpad", description: "Move, Scroll or Navigate Website")
                    ShortcutRow(icon: "hand.tap", title: "Middle Button", description: "Click at the Cursor")
                    ShortcutRow(icon: "playpause", title: "Play/Pause Button", description: "Open Quick Menu (Hold to toggle Sidebar)")
                    ShortcutRow(icon: "sidebar.leading", title: "Back/Menu Button (Hold)", description: "Press and hold to open Sidebar")
                    ShortcutRow(icon: "arrow.backward", title: "Back/Menu Button (Tap)", description: "Go back to previous page")
                }
                
                Divider()
                
                HStack {
                    Spacer()
                    Button("Got it", systemImage: "checkmark") {
                        onFinish()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                
                Spacer()
            }
            .padding(40)
            .navigationTitle("Remote Shortcuts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onFinish()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 1200, height: 900)
    }
}

struct ShortcutRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 75)
                .foregroundStyle(.tint)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .bold()
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}
