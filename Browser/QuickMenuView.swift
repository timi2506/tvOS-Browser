//
//  QuickMenuView.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import SwiftUI
import Combine

struct QuickMenuView: View {
    @ObservedObject var manager: WebViewManager
    @Environment(\.dismiss) private var dismiss
    @Binding var showingSettings: Bool
    @State private var showingFavoriteSheet = false
    @State private var showingHistorySheet = false
    init(manager: WebViewManager, showingSettings: Binding<Bool>) {
        self.manager = manager
        self._showingSettings = showingSettings
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Control Mode")
                    .bold()
                Picker("Control Mode", selection: $manager.controlMode) {
                    ForEach(RemoteControlMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Divider()
                Button(action: {
                    manager.goBack()
                    dismiss()
                }) {
                    HStack {
                        Label("Go Back", systemImage: "arrow.backward")
                        Spacer()
                    }
                }
                .disabled(!manager.canGoBack)
                
                Button(action: {
                    manager.goForward()
                    dismiss()
                }) {
                    HStack {
                        Label("Go Forward", systemImage: "arrow.forward")
                        Spacer()
                    }
                }
                .disabled(!manager.canGoForward)
                
                Button(action: {
                    manager.reload()
                    dismiss()
                }) {
                    HStack {
                        Label("Reload Page", systemImage: "arrow.clockwise")
                        Spacer()
                    }
                }
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 15) {
                        Button("Show Keyboard", systemImage: "keyboard") {
                            dismiss()
                            manager.presentKeyboardPrompt()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Simulate Enter", systemImage: "return") {
                            dismiss()
                            manager.simulateEnter()
                        }
                        .buttonStyle(.bordered)
                        Button("Add to Favorites", systemImage: "star") {
                            showingFavoriteSheet = true
                        }
                        .buttonStyle(.bordered)
                        Button("History", systemImage: "clock") {
                            showingHistorySheet = true
                        }
                        .buttonStyle(.bordered)
                        Button("Show Sidebar", systemImage: "sidebar.leading") {
                            withAnimation {
                                dismiss()
                                manager.presentMenu = true
                            }
                        }
                        .buttonStyle(.bordered)
                        Button("Settings", systemImage: "gear") {
                            dismiss()
                            showingSettings = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .scrollClipDisabled()
            }
            .modify {
                if #available(tvOS 26.0, *) {
                    $0.labelReservedIconWidth(35)
                } else {
                   $0
                }
            }
            .padding()
            .navigationTitle("Quick Menu")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 1200, height: 900)
        .sheet(isPresented: $showingFavoriteSheet) {
            FavoriteSheet(manager: manager)
        }
        .sheet(isPresented: $showingHistorySheet) {
            HistorySheetView(manager: manager)
        }
    }
}

extension View {
    func modify(@ViewBuilder _ content: (Self) -> some View) -> some View{
        content(self)
    }
}

struct CustomUserAgentSheet: View {
    @ObservedObject var manager: WebViewManager
    @Environment(\.dismiss) var dismiss
    
    @State private var userAgentString: String = ""
    @State private var errorMessage: String?
    
    init(manager: WebViewManager) {
        self.manager = manager
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Custom User Agent")
                    .bold()
                
                TextField("User Agent String", text: $userAgentString)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
                
                Spacer()
                Divider()
                
                HStack(spacing: 15) {
                    Spacer()
                    Button("Save and Apply", systemImage: "checkmark") {
                        saveUserAgent()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding()
                
            }
            .padding()
            .navigationTitle("Custom User Agent")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveUserAgent()
                    }
                }
            }
        }
        .frame(width: 1200, height: 900)
        .onAppear {
            userAgentString = manager.customUserAgentString
        }
    }
    
    private func saveUserAgent() {
        let trimmed = userAgentString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errorMessage = "Please enter a valid User Agent string"
            return
        }
        manager.customUserAgentString = trimmed
        manager.currentUserAgent = .custom
        dismiss()
    }
}

struct FavoriteSheet: View {
    @ObservedObject var manager: WebViewManager
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String = ""
    @State private var urlString: String = ""
    @State private var errorMessage: String?
    
    init(manager: WebViewManager) {
        self.manager = manager
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Website Information")
                    .bold()
                
                HStack {
                    Text("Title")
                        .bold()
                    Spacer()
                }
                TextField("Title", text: $title)
                
                HStack {
                    Text("URL")
                        .bold()
                    Spacer()
                }
                TextField("URL", text: $urlString)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
                
                Spacer()
                Divider()
                HStack(spacing: 15) {
                    Spacer()
                    Button("Save Favorite", systemImage: "star.fill") {
                        saveFavorite()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding()
                
            }
            .padding()
            .navigationTitle("Add to Favorites")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveFavorite()
                    }
                }
            }
        }
        .frame(width: 1200, height: 900)
        .onAppear {
            let currentTitle = manager.activeTab?.title ?? ""
            let currentUrl = manager.url?.absoluteString ?? ""
            self.title = currentTitle.isEmpty ? (manager.url?.host() ?? "") : currentTitle
            self.urlString = currentUrl
        }
    }
    
    private func saveFavorite() {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let validURL = URL(string: trimmedURL), validURL.scheme != nil else {
            errorMessage = "Please enter a valid URL with http:// or https://"
            return
        }
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? (validURL.host ?? trimmedURL) : trimmedTitle
        
        manager.addFavorite(title: displayTitle, url: validURL)
        dismiss()
    }
}

struct HistorySheetView: View {
    @ObservedObject var manager: WebViewManager
    @ObservedObject var historyManager = HistoryManager.shared
    @Environment(\.dismiss) var dismiss
    
    init(manager: WebViewManager) {
        self.manager = manager
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Recent History (\(historyManager.history.count))")
                        .bold()
                    Spacer()
                    if !historyManager.history.isEmpty {
                        Button("Clear History", role: .destructive) {
                            historyManager.clearHistory()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Divider()
                
                if historyManager.history.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "clock")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No History")
                            .font(.title3)
                            .bold()
                        Text("Websites you visit will appear here.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 10) {
                            ForEach(historyManager.history) { item in
                                Button(action: {
                                    manager.loadURL(item.url)
                                    dismiss()
                                    manager.presentQuickMenu = false
                                }) {
                                    HStack(spacing: 16) {
                                        Image(systemName: "globe")
                                            .foregroundStyle(.tint)
                                            .frame(width: 32)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title)
                                                .font(.headline)
                                                .lineLimit(1)
                                            Text(item.url.absoluteString)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(item.formattedDate)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 1200, height: 900)
    }
}
