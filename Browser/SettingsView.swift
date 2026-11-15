//
//  SettingsView.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import SwiftUI

enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case google = "Google"
    case duckDuckGo = "DuckDuckGo"
    case bing = "Bing"
    case yahoo = "Yahoo"
    case ecosia = "Ecosia"
    case brave = "Brave"
    
    var id: String { rawValue }
    
    func searchURL(for query: String) -> URL? {
        let baseURLString: String
        switch self {
        case .google:
            baseURLString = "https://www.google.com/search"
        case .duckDuckGo:
            baseURLString = "https://duckduckgo.com/"
        case .bing:
            baseURLString = "https://www.bing.com/search"
        case .yahoo:
            baseURLString = "https://search.yahoo.com/search"
        case .ecosia:
            baseURLString = "https://www.ecosia.org/search"
        case .brave:
            baseURLString = "https://search.brave.com/search"
        }
        
        var components = URLComponents(string: baseURLString)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

struct SettingsView: View {
    @ObservedObject var manager: WebViewManager
    @ObservedObject var historyManager = HistoryManager.shared
    @ObservedObject var fileServer = FileServerManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingCustomUASheet = false
    @State private var showingOnboarding = false

    init(manager: WebViewManager) {
        self.manager = manager
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Text("Search Provider")
                            .bold()
                        Spacer()
                        Picker("Search Provider", selection: $manager.searchEngine) {
                            ForEach(SearchEngine.allCases) { engine in
                                Text(engine.rawValue).tag(engine)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Divider()
                    HStack {
                        Text("User Agent")
                            .bold()
                        Spacer()
                        Picker("User Agent", selection: $manager.currentUserAgent) {
                            ForEach(UserAgentType.allCases) { agent in
                                Text(agent.rawValue)
                                    .tag(agent)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    Button(action: {
                        showingCustomUASheet = true
                    }) {
                        HStack {
                            Label("Add Custom User Agent", systemImage: "plus.circle")
                            Spacer()
                        }
                    }
                    Divider()
                    HStack {
                        Text("Touchpad Sensitivity")
                            .bold()
                        Spacer()
                        Picker("Touchpad Sensitivity", selection: $manager.touchpadSensitivity) {
                            ForEach(TouchpadSensitivity.allCases) { sens in
                                Text(sens.rawValue).tag(sens)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Divider()
                    HStack {
                        Text("Google Search Suggestions")
                            .bold()
                        Spacer()
                        Toggle("", isOn: $manager.enableSearchSuggestions)
                            .labelsHidden()
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Auto-Detect Keyboard")
                            .bold()
                        Spacer()
                        Toggle("", isOn: $manager.autoKeyboardDetection)
                            .labelsHidden()
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Keep Tabs Open")
                            .bold()
                        Spacer()
                        Toggle("", isOn: $manager.keepTabsOpen)
                            .labelsHidden()
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Save History Across Launches")
                            .bold()
                        Spacer()
                        Toggle("", isOn: $historyManager.saveHistoryAcrossLaunches)
                            .labelsHidden()
                    }
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Wi-Fi File Sharing Server")
                                .bold()
                            if fileServer.isRunning, let url = fileServer.serverURL {
                                Text(url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("Stopped")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { fileServer.isRunning },
                            set: { newValue in
                                if newValue {
                                    fileServer.start()
                                } else {
                                    fileServer.stop()
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    
                    Divider()
                    
                    Button(action: {
                        showingOnboarding = true
                    }) {
                        HStack {
                            Label("Remote Shortcuts Guide", systemImage: "questionmark.circle")
                            Spacer()
                        }
                    }
                    
                    Divider()
                    
                    Spacer()
                }
                .modify {
                    if #available(tvOS 26.0, *) {
                        $0.labelReservedIconWidth(35)
                    } else {
                        $0
                    }
                }
                .padding()
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 1200, height: 900)
        .sheet(isPresented: $showingCustomUASheet) {
            CustomUserAgentSheet(manager: manager)
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "HasSeenOnboarding")
            }
        }
    }
}
