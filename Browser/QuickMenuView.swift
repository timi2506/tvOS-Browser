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
    @State private var showingFavoriteSheet = false
    @State private var showingHistorySheet = false
    @State private var showingCustomUASheet = false
    
    init(manager: WebViewManager) {
        self.manager = manager
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Picker("Control Mode", selection: $manager.controlMode) {
                    ForEach(RemoteControlMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                HStack {
                    Text("User Agent")
                    Spacer()
                    Picker("User Agent", selection: $manager.currentUserAgent) {
                        ForEach(UserAgentType.allCases) { agent in
                            Text(agent.rawValue)
                                .tag(agent)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Button("Add Custom User Agent", systemImage: "plus.circle") {
                    showingCustomUASheet = true
                }
                
                Section("Navigation") {
                    Button("Go Back", systemImage: "arrow.backward") {
                        manager.goBack()
                        dismiss()
                    }
                    .disabled(!manager.canGoBack)
                    
                    Button("Go Forward", systemImage: "arrow.forward") {
                        manager.goForward()
                        dismiss()
                    }
                    .disabled(!manager.canGoForward)
                    
                    Button("Reload Page", systemImage: "arrow.clockwise") {
                        manager.reload()
                        dismiss()
                    }
                }
                
                Section("Quick Actions") {
                    Button("Add to Favorites", systemImage: "star.badge.plus") {
                        showingFavoriteSheet = true
                    }
                    
                    Button("History", systemImage: "clock") {
                        showingHistorySheet = true
                    }
                    
                    Button("Show Sidebar", systemImage: "sidebar.leading") {
                        withAnimation {
                            dismiss()
                            manager.presentMenu = true
                        }
                    }
                }
            }
            .labelReservedIconWidth(35)
            .scrollClipDisabled()
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
        .sheet(isPresented: $showingCustomUASheet) {
            CustomUserAgentSheet(manager: manager)
        }
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
            Form {
                Section(header: Text("Custom User Agent")) {
                    TextField("User Agent String", text: $userAgentString)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                
                Section {
                    Button("Save and Apply") {
                        saveUserAgent()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Custom User Agent")
            .onAppear {
                userAgentString = manager.customUserAgentString
            }
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
            Form {
                Section(header: Text("Website Information")) {
                    TextField("Title", text: $title)
                    TextField("URL", text: $urlString)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                
                Section {
                    Button("Save Favorite") {
                        saveFavorite()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Add to Favorites")
            .onAppear {
                let currentTitle = manager.activeTab?.title ?? ""
                let currentUrl = manager.url?.absoluteString ?? ""
                self.title = currentTitle.isEmpty ? (manager.url?.host() ?? "") : currentTitle
                self.urlString = currentUrl
            }
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
            List {
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
                    Section(header: HStack {
                        Text("Recent History (\(historyManager.history.count))")
                        Spacer()
                        Button("Clear History", role: .destructive) {
                            historyManager.clearHistory()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }) {
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
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
