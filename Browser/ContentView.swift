//
//  ContentView.swift
//  Browser
//
//  Created by Tim on 14.11.26.
//

import SwiftUI
import Combine
import FaviconFinder
import SwiftSoup

enum RemoteControlMode: String, CaseIterable, Identifiable {
    case cursor = "Cursor"
    case scroll = "Scroll"
    case tvRemote = "Remote"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .cursor: return "circle.inset.filled"
        case .scroll: return "arrow.up.and.down"
        case .tvRemote: return "tv"
        }
    }
}

enum UserAgentType: String, CaseIterable, Identifiable {
    case desktopSafari = "Safari on macOS"
    case mobileSafari = "Safari on iPhone)"
    case iPadSafari = "Safari on iPad"
    case smartTV = "Apple TV"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var value: String {
        switch self {
        case .desktopSafari:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_8_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Safari/605.1.15"
        case .mobileSafari:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7_12 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1"
        case .iPadSafari:
            return "Mozilla/5.0 (iPad; CPU OS 18_7_12 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1"
        case .smartTV:
            return "AppleCoreMedia/1.0.0.24J5325d (Apple TV; U; CPU OS 27_0 like Mac OS X; en_us)"
        case .custom:
            return UserDefaults.standard.string(forKey: "CustomUserAgentString") ?? WebViewManager.defaultCustomUserAgent
        }
    }
}

enum TouchpadSensitivity: String, CaseIterable, Identifiable, Codable {
    case verySlow = "Very Slow"
    case slow = "Slow"
    case medium = "Medium"
    case fast = "Fast"
    case veryFast = "Very Fast"
    
    var id: String { rawValue }
    
    var cursorMultiplier: CGFloat {
        switch self {
        case .verySlow: return 0.6
        case .slow: return 0.9
        case .medium: return 1.2
        case .fast: return 1.5
        case .veryFast: return 2.0
        }
    }
    
    var scrollMultiplier: CGFloat {
        switch self {
        case .verySlow: return 0.8
        case .slow: return 1.3
        case .medium: return 1.6
        case .fast: return 2.0
        case .veryFast: return 2.6
        }
    }
}

struct ContentView: View {
    @StateObject var manager = WebViewManager.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @FocusState var focusMenu: Bool
    @State var urlBarURL = ""
    @State var wrongURLPrompt = false
    @State var showingSettings = false
    @State private var showingOnboarding = !UserDefaults.standard.bool(forKey: "HasSeenOnboarding")
    
    private var urlHostTitle: String {
        manager.url?.host() ?? "URL or Search"
    }
    
    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if manager.presentMenu {
                    sidebarView
                }
                
                webContentView
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .sheet(isPresented: $manager.presentQuickMenu) {
            QuickMenuView(manager: manager, showingSettings: $showingSettings)
                .frame(width: 1200, height: 900)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(manager: manager)
        }
        .fullScreenCover(isPresented: $manager.presentKeyboard) {
            KeyboardInputSheet(manager: manager)
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "HasSeenOnboarding")
            }
        }
        .onChange(of: manager.presentMenu) { _, newValue in
            withAnimation {
                focusMenu = newValue
            }
        }
        .onChange(of: manager.url) { _, newURL in
            if let url = newURL {
                withAnimation {
                    urlBarURL = url.absoluteString
                }
            } else {
                withAnimation {
                    urlBarURL = ""
                }
            }
        }
        .alert("Invalid URL", isPresented: $wrongURLPrompt) {
            Button("OK") {
                urlBarURL = ""
                wrongURLPrompt = false
            }
        } message: {
            Text("The URL \"\(urlBarURL)\" is not a valid URL.")
        }
        .alert(
            "Download File?",
            isPresented: Binding(
                get: { downloadManager.pendingDownload != nil },
                set: { if !$0 { downloadManager.pendingDownload = nil } }
            ),
            presenting: downloadManager.pendingDownload
        ) { pending in
            Button("Download") {
                downloadManager.startDownload(from: pending.url, suggestedFilename: pending.filename)
                downloadManager.pendingDownload = nil
            }
            Button("Show QR Code") {
                let item = pending
                downloadManager.pendingDownload = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    downloadManager.activeQRCodeDownload = item
                }
            }
            Button("Cancel", role: .cancel) {
                downloadManager.pendingDownload = nil
            }
        } message: { pending in
            Text("Do you want to download \"\(pending.filename)\"?")
        }
        .sheet(item: $downloadManager.activeQRCodeDownload) { item in
            DownloadQRCodeSheet(download: item)
                .frame(minWidth: 1000, minHeight: 800)
        }
    }
    
    @ViewBuilder
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                HStack(spacing: 15) {
                    NavigationLink(destination: {
                        SearchView(urlBarURL: urlBarURL) {
                            manager.loadURL($0)
                        }
                    }) {
                        HStack {
                            Text(urlHostTitle)
                                .foregroundStyle(manager.url == nil ? .secondary : .primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Reload", systemImage: "arrow.clockwise") {
                        manager.reload()
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                }
                .padding(10)
                .background {
                    if let currentColor = manager.currentColor {
                        Capsule()
                            .foregroundStyle(currentColor)
                    }
                }
            }
            if !manager.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("FAVORITES")
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12.5) {
                            ForEach($manager.favorites) { $favorite in
                                FavoriteButton(favorite: $favorite)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .scrollClipDisabled()
                }
                .frame(maxWidth: 520)
            }
            Divider()
                .padding(.vertical, 5)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TABS (\(manager.tabs.count))")
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("New Tab", systemImage: "plus") {
                        withAnimation {
                            manager.addNewTab()
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .labelStyle(.iconOnly)
                }
                .padding(.horizontal, 5)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(manager.tabs) { tab in
                            TabRowView(tab: tab, isActive: tab.id == manager.activeTabId) {
                                withAnimation {
                                    manager.selectTab(id: tab.id)
                                }
                            } onClose: {
                                withAnimation {
                                    manager.closeTab(id: tab.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
                .scrollClipDisabled()
                .frame(maxHeight: .infinity)
            }
            
            Spacer()
            
            Divider()
                .padding(.vertical, 5)
            
            HStack(spacing: 10) {
                Spacer()
                Button("Settings", systemImage: "gear") {
                    withAnimation {
                        showingSettings = true
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                NavigationLink(destination: {
                    DownloadsView()
                }) {
                    Label("Downloads", systemImage: "arrow.down.circle")
                        .lineLimit(1)
                        .minimumScaleFactor(0.25)
                }
                .buttonStyle(.bordered)
                Button("Close", systemImage: "xmark") {
                    withAnimation {
                        manager.presentMenu = false
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                Spacer()
            }
        }
        .padding(15)
        .frame(maxWidth: 550)
        .transition(.move(edge: .leading).combined(with: .opacity))
        .focused($focusMenu)
#if os(tvOS)
        .onExitCommand {
            withAnimation {
                manager.presentMenu = false
            }
        }
        #endif
    }
    
    @ViewBuilder
    private var webContentView: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                TVWebViewRepresentable(manager: manager)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                
                if manager.isLoading && manager.estimatedProgress < 1.0 {
                    ProgressView(value: max(0.05, manager.estimatedProgress))
                        .progressViewStyle(.linear)
                        .tint(manager.currentColor ?? .blue)
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
                
                if manager.controlMode == .cursor {
                    Circle()
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.regularMaterial)
                        .opacity(0.85)
                        .scaleEffect(manager.isTapping ? 0.75 : 1.0)
                        .overlay {
                            Circle()
                                .frame(width: 8, height: 8)
                                .foregroundStyle(manager.isTapping ? Color.accentColor : Color.white)
                                .blur(radius: manager.isTapping ? 1 : 3)
                        }
                        .overlay {
                            Circle()
                                .stroke(manager.isTapping ? Color.accentColor : Color.white.opacity(0.4), lineWidth: 1.5)
                                .frame(width: 44, height: 44)
                        }
                        .animation(.easeOut(duration: 0.12), value: manager.isTapping)
                        .position(manager.cursorPosition)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !downloadManager.activeDownloads.isEmpty {
                    downloadIndicatorOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .onAppear {
                manager.updateViewSize(geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                manager.updateViewSize(newSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var downloadIndicatorOverlay: some View {
        let progressValues = Array(downloadManager.activeDownloads.values)
        let avgProgress = progressValues.isEmpty ? 0.0 : (progressValues.reduce(0.0, +) / Double(progressValues.count))
        
        HStack(spacing: 10) {
            ZStack {
                if avgProgress > 0.0 {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3.5)
                        .frame(width: 38, height: 38)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(avgProgress))
                        .stroke(manager.currentColor ?? Color.accentColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 38, height: 38)
                        .animation(.easeInOut(duration: 0.2), value: avgProgress)
                    
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .bold))
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 38, height: 38)
                }
            }
            
            if downloadManager.activeDownloads.count > 1 {
                Text("\(downloadManager.activeDownloads.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        .padding(.trailing, 50)
        .padding(.bottom, 50)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: downloadManager.activeDownloads.isEmpty)
    }
}

struct TabRowView: View {
    @ObservedObject var tab: BrowserTab
    var isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
    @State private var showingActionSheet = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 15) {
                if let fav = tab.favicon {
                    Image(uiImage: fav)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 35, height: 35)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else if isActive {
                    Image(systemName: "globe")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 35, height: 35)
                } else {
                    Image(systemName: "globe")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 35, height: 35)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title.isEmpty ? (tab.url?.host() ?? "New Tab") : tab.title)
                        .font(.callout)
                        .bold(isActive)
                        .lineLimit(1)
                    
                    if let host = tab.url?.host() {
                        Text(host)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if tab.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                } else if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 7.5)
            .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    onClose()
                }
            } label: {
                Label("Close Tab", systemImage: "xmark")
            }
            
            Button {
                tab.reload()
            } label: {
                Label("Reload Tab", systemImage: "arrow.clockwise")
            }
            
            Button {
                WebViewManager.shared.addNewTab(url: tab.url)
            } label: {
                Label("Duplicate Tab", systemImage: "plus.square.on.square")
            }
        }
#if os(tvOS)
        .onPlayPauseCommand {
            showingActionSheet.toggle()
        }
        #endif
        .confirmationDialog("Tab Options", isPresented: $showingActionSheet, titleVisibility: .visible) {
            Button("Close Tab", role: .destructive) {
                withAnimation {
                    onClose()
                }
            }
            Button("Reload") {
                tab.reload()
            }
            Button("Duplicate Tab") {
                WebViewManager.shared.addNewTab(url: tab.url)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SearchView: View {
    @Environment(\.dismiss) var dismiss
    @State var urlBarURL: String
    var onSubmit: (URL) -> Void
    
    @State private var suggestions: [String] = []
    @State private var fetchTask: Task<Void, Never>?
    @ObservedObject private var manager = WebViewManager.shared
    
    var body: some View {
        NavigationStack {
            VStack {
                Text(urlBarURL)
                    .font(.title)
                    .minimumScaleFactor(0.25)
            }
            .searchable(text: $urlBarURL, prompt: "Type URL or Search")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 20) {
                    Button("Go") {
                        handleSubmit(query: urlBarURL)
                    }
                    .disabled(urlBarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button("Clear") {
                        urlBarURL = ""
                        suggestions = []
                    }
                    .disabled(urlBarURL.isEmpty)
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    Spacer()
                }
                .contentShape(.rect)
                .focusSection()
            }
            .onSubmit(of: .search) {
                handleSubmit(query: urlBarURL)
            }
            .searchSuggestions {
                if manager.enableSearchSuggestions {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            urlBarURL = suggestion
                            handleSubmit(query: suggestion)
                        }
                    }
                }
            }
            .onChange(of: urlBarURL) { newValue in
                guard manager.enableSearchSuggestions else {
                    suggestions = []
                    return
                }
                fetchTask?.cancel()
                
                fetchTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: 300_000_000)
                        await fetchSuggestions(for: newValue)
                    } catch {
                        
                    }
                }
            }
        }
    }
    
    private func handleSubmit(query: String) {
        guard !query.isEmpty else { return }
        if let url = processQuery(query) {
            onSubmit(url)
            dismiss()
        }
    }
    
    private func processQuery(_ query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.contains(" ") {
            return manager.searchEngine.searchURL(for: trimmed)
        }
        
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        
        if trimmed.contains("."), let url = URL(string: "https://\(trimmed)") {
            return url
        }
        
        return manager.searchEngine.searchURL(for: trimmed)
    }
    
    private func fetchSuggestions(for query: String) async {
        guard manager.enableSearchSuggestions else {
            await MainActor.run { suggestions = [] }
            return
        }
        guard !query.isEmpty else {
            await MainActor.run { suggestions = [] }
            return
        }
        
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=chrome&q=\(encodedQuery)") else {
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any],
               jsonArray.count > 1,
               let fetchedSuggestions = jsonArray[1] as? [String] {
                await MainActor.run {
                    self.suggestions = fetchedSuggestions
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run { suggestions = [] }
        }
    }
}

struct SavedTab: Codable {
    let id: UUID
    let urlString: String
    let title: String
}

class WebViewManager: ObservableObject {
    public static let shared = WebViewManager()
    
    @Published public var tabs: [BrowserTab] = []
    @Published public var activeTabId: UUID?
    
    @Published public var controlMode: RemoteControlMode = .cursor
    public static let defaultCustomUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    
    @Published public var customUserAgentString: String = UserDefaults.standard.string(forKey: "CustomUserAgentString") ?? defaultCustomUserAgent {
        didSet {
            UserDefaults.standard.set(customUserAgentString, forKey: "CustomUserAgentString")
            if currentUserAgent == .custom {
                activeTab?.setUserAgent(currentUserAgent.value)
                activeTab?.reload()
            }
        }
    }
    
    @Published public var currentUserAgent: UserAgentType = .smartTV {
        didSet {
            activeTab?.setUserAgent(currentUserAgent.value)
            activeTab?.reload()
        }
    }
    @Published public var viewSize: CGSize = CGSize(width: 1920, height: 1080)
    @Published public var cursorPosition: CGPoint = CGPoint(x: 960, y: 540)
    @Published public var isTapping: Bool = false
    
    @Published public var presentMenu = true
    @Published public var presentQuickMenu = false
    
    private let touchpadSensitivityKey = "BrowserTouchpadSensitivity"
    
    @Published public var touchpadSensitivity: TouchpadSensitivity = {
        if let raw = UserDefaults.standard.string(forKey: "BrowserTouchpadSensitivity"),
           let sens = TouchpadSensitivity(rawValue: raw) {
            return sens
        }
        return .medium
    }() {
        didSet {
            UserDefaults.standard.set(touchpadSensitivity.rawValue, forKey: touchpadSensitivityKey)
        }
    }
    
    private let searchEngineKey = "BrowserSearchEngine"
    private let enableSearchSuggestionsKey = "BrowserEnableSearchSuggestions"
    
    @Published public var searchEngine: SearchEngine = {
        if let raw = UserDefaults.standard.string(forKey: "BrowserSearchEngine"),
           let engine = SearchEngine(rawValue: raw) {
            return engine
        }
        return .google
    }() {
        didSet {
            UserDefaults.standard.set(searchEngine.rawValue, forKey: searchEngineKey)
        }
    }
    
    @Published public var enableSearchSuggestions: Bool = {
        if UserDefaults.standard.object(forKey: "BrowserEnableSearchSuggestions") != nil {
            return UserDefaults.standard.bool(forKey: "BrowserEnableSearchSuggestions")
        }
        return true
    }() {
        didSet {
            UserDefaults.standard.set(enableSearchSuggestions, forKey: enableSearchSuggestionsKey)
        }
    }
    
    private let autoKeyboardDetectionKey = "BrowserAutoKeyboardDetection"
    
    @Published public var autoKeyboardDetection: Bool = {
        if UserDefaults.standard.object(forKey: "BrowserAutoKeyboardDetection") != nil {
            return UserDefaults.standard.bool(forKey: "BrowserAutoKeyboardDetection")
        }
        return true
    }() {
        didSet {
            UserDefaults.standard.set(autoKeyboardDetection, forKey: autoKeyboardDetectionKey)
        }
    }
    
    @Published public var presentKeyboard: Bool = false
    @Published public var keyboardInputText: String = ""
    @Published public var keyboardPlaceholder: String = ""
    
    @Published public var favorites: [Favorite] = []
    
    private let keepTabsOpenKey = "BrowserKeepTabsOpen"
    private let savedTabsKey = "BrowserSavedTabs"
    private let activeTabKey = "BrowserActiveTabId"
    
    @Published public var keepTabsOpen: Bool = {
        if UserDefaults.standard.object(forKey: "BrowserKeepTabsOpen") != nil {
            return UserDefaults.standard.bool(forKey: "BrowserKeepTabsOpen")
        }
        return true
    }() {
        didSet {
            UserDefaults.standard.set(keepTabsOpen, forKey: keepTabsOpenKey)
            if keepTabsOpen {
                saveTabsState()
            } else {
                UserDefaults.standard.removeObject(forKey: savedTabsKey)
                UserDefaults.standard.removeObject(forKey: activeTabKey)
            }
        }
    }
    
    private var activeTabCancellable: AnyCancellable?
    private let favoritesKey = "BrowserFavorites"
    
    public var activeTab: BrowserTab? {
        guard let id = activeTabId else { return tabs.first }
        return tabs.first { $0.id == id }
    }
    
    public var url: URL? { activeTab?.url }
    public var isLoading: Bool { activeTab?.isLoading ?? false }
    public var canGoBack: Bool { activeTab?.canGoBack ?? false }
    public var canGoForward: Bool { activeTab?.canGoForward ?? false }
    public var currentColor: Color? { activeTab?.currentColor }
    public var estimatedProgress: Double { activeTab?.estimatedProgress ?? 0.0 }
    
    private init() {
        loadFavorites()
        loadTabs()
    }
    
    private func setupTab(_ tab: BrowserTab) {
        tab.onStateChanged = { [weak self] in
            self?.saveTabsState()
        }
        tab.onTextInputFocused = { [weak self] placeholder, value in
            guard let self = self, self.autoKeyboardDetection else { return }
            self.keyboardPlaceholder = placeholder
            self.keyboardInputText = value
            self.presentKeyboard = true
        }
    }
    
    private func loadTabs() {
        if keepTabsOpen,
           let data = UserDefaults.standard.data(forKey: savedTabsKey),
           let savedTabs = try? JSONDecoder().decode([SavedTab].self, from: data),
           !savedTabs.isEmpty {
            var loadedTabs: [BrowserTab] = []
            for saved in savedTabs {
                let url = URL(string: saved.urlString)
                let tab = BrowserTab(id: saved.id, initialURL: url)
                tab.title = saved.title
                tab.setUserAgent(currentUserAgent.value)
                setupTab(tab)
                loadedTabs.append(tab)
            }
            self.tabs = loadedTabs
            if let activeStr = UserDefaults.standard.string(forKey: activeTabKey),
               let activeUUID = UUID(uuidString: activeStr),
               loadedTabs.contains(where: { $0.id == activeUUID }) {
                self.activeTabId = activeUUID
            } else {
                self.activeTabId = loadedTabs.first?.id
            }
        } else {
            let defaultTab = BrowserTab(initialURL: URL(string: "https://google.com"))
            defaultTab.setUserAgent(currentUserAgent.value)
            setupTab(defaultTab)
            self.tabs = [defaultTab]
            self.activeTabId = defaultTab.id
        }
        observeActiveTab()
    }
    
    public func saveTabsState() {
        guard keepTabsOpen else { return }
        let savedTabs = tabs.compactMap { tab -> SavedTab? in
            guard let url = tab.url else { return nil }
            return SavedTab(id: tab.id, urlString: url.absoluteString, title: tab.title)
        }
        if !savedTabs.isEmpty, let data = try? JSONEncoder().encode(savedTabs) {
            UserDefaults.standard.set(data, forKey: savedTabsKey)
            if let activeId = activeTabId {
                UserDefaults.standard.set(activeId.uuidString, forKey: activeTabKey)
            }
        }
    }
    
    private func observeActiveTab() {
        activeTabCancellable?.cancel()
        if let current = activeTab {
            activeTabCancellable = current.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.saveTabsState()
            }
        }
    }
    
    public func addNewTab(url: URL? = URL(string: "https://google.com")) {
        let newTab = BrowserTab(initialURL: url)
        newTab.setUserAgent(currentUserAgent.value)
        setupTab(newTab)
        tabs.append(newTab)
        activeTabId = newTab.id
        observeActiveTab()
        saveTabsState()
    }
    
    public func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        
        if tabs.isEmpty {
            addNewTab()
        } else if activeTabId == id {
            let nextIndex = min(index, tabs.count - 1)
            activeTabId = tabs[nextIndex].id
            observeActiveTab()
        }
        saveTabsState()
    }
    
    public func selectTab(id: UUID) {
        activeTabId = id
        observeActiveTab()
        saveTabsState()
    }
    
    public func selectPreviousTab() {
        guard tabs.count > 1, let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        let prevIndex = (currentIndex - 1 + tabs.count) % tabs.count
        selectTab(id: tabs[prevIndex].id)
    }
    
    public func selectNextTab() {
        guard tabs.count > 1, let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        selectTab(id: tabs[nextIndex].id)
    }
    
    public func loadURL(_ url: URL) {
        if let tab = activeTab {
            tab.load(url: url)
        } else {
            addNewTab(url: url)
        }
        saveTabsState()
    }
    
    public func reload() {
        activeTab?.reload()
    }
    
    public func goBack() {
        activeTab?.goBack()
    }
    
    public func goForward() {
        activeTab?.goForward()
    }
    
    public func updateViewSize(_ size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        let previousSize = viewSize
        viewSize = size
        
        if cursorPosition == .zero || (previousSize.width == 1920 && previousSize.height == 1080 && size != previousSize) {
            cursorPosition = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        } else {
            cursorPosition.x = min(max(20, cursorPosition.x), size.width - 20)
            cursorPosition.y = min(max(20, cursorPosition.y), size.height - 20)
        }
    }
    
    public func moveCursor(by delta: CGSize) {
        var newX = cursorPosition.x + delta.width
        var newY = cursorPosition.y + delta.height
        
        let padding: CGFloat = 20.0
        let minX = padding
        let maxX = max(padding, viewSize.width - padding)
        let minY = padding
        let maxY = max(padding, viewSize.height - padding)
        
        if delta.height > 0 && cursorPosition.y >= maxY - 1.0 {
            scrollActiveTab(dx: 0, dy: max(45, delta.height * 2.5))
        } else if delta.height < 0 && cursorPosition.y <= minY + 1.0 {
            scrollActiveTab(dx: 0, dy: min(-45, delta.height * 2.5))
        }
        
        newX = min(max(minX, newX), maxX)
        newY = min(max(minY, newY), maxY)
        
        cursorPosition = CGPoint(x: newX, y: newY)
    }
    
    public func tapAtCursor() {
        isTapping = true
        activeTab?.clickAt(point: cursorPosition)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.isTapping = false
        }
    }
    
    public func scrollActiveTab(dx: CGFloat, dy: CGFloat) {
        activeTab?.scrollBy(dx: dx, dy: dy)
    }
    
    public func sendRemoteKey(key: String, code: String, keyCode: Int) {
        activeTab?.sendRemoteKey(key, code: code, keyCode: keyCode)
    }
    
    public func sendRemoteBackKey() {
        activeTab?.sendRemoteBackKey()
    }
    
    public func presentKeyboardPrompt() {
        activeTab?.fetchActiveElementInfo { [weak self] placeholder, currentValue in
            DispatchQueue.main.async {
                self?.keyboardPlaceholder = placeholder
                self?.keyboardInputText = currentValue
                self?.presentKeyboard = true
            }
        }
    }
    
    public func submitKeyboardText(_ text: String, pressEnter: Bool = true) {
        activeTab?.submitKeyboardText(text, pressEnter: pressEnter)
    }
    
    public func simulateEnter() {
        activeTab?.simulateEnter()
    }
    
    public func addFavorite(title: String, url: URL) {
        Task {
            let fav = await Favorite(title: title, url: url)
            await MainActor.run {
                self.favorites.append(fav)
                self.saveFavorites()
            }
        }
    }
    
    public func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        saveFavorites()
    }
    
    public func updateFavorite(id: UUID, title: String, url: URL) {
        guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }
        favorites[index].title = title
        let urlChanged = favorites[index].url != url
        favorites[index].url = url
        if urlChanged {
            favorites[index].cachedIcon = nil
            favorites[index].color = nil
            Task {
                if let nativeColor = try? await WebsiteColorParser.getColor(for: url.absoluteString) {
                    await MainActor.run {
                        self.favorites[index].color = Color(uiColor: nativeColor)
                        self.saveFavorites()
                    }
                }
            }
        }
        saveFavorites()
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let saved = try? JSONDecoder().decode([Favorite].self, from: data) {
            self.favorites = saved
        } else {
            Task {
                let google = await Favorite(title: "Google", url: URL(string: "https://google.com")!)
                let youtube = await Favorite(title: "YouTube", url: URL(string: "https://youtube.com/tv")!)
                let apple = await Favorite(title: "Apple", url: URL(string: "https://apple.com")!)
                await MainActor.run {
                    self.favorites = [google, youtube, apple]
                    self.saveFavorites()
                }
            }
        }
    }
}

struct Favorite: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var url: URL
    var cachedIcon: Data?
    var color: Color?
    
    init(id: UUID = UUID(), title: String, url: URL, cachedIcon: Data? = nil, color: Color? = nil) async {
        self.id = id
        self.title = title
        self.url = url
        self.cachedIcon = cachedIcon
        if let color {
            self.color = color
        } else if let nativeColor = try? await WebsiteColorParser.getColor(for: url.absoluteString) {
#if canImport(UIKit)
            self.color = Color(uiColor: nativeColor)
#elseif canImport(AppKit)
            self.color = Color(nsColor: nativeColor)
#else
            self.color = nil
#endif
        } else {
            self.color = nil
        }
    }
}

struct FavoriteButton: View {
    @Binding var favorite: Favorite
    @State var loadTask: Task<Void, Never>?
    @State private var showingEditSheet = false
    
    var body: some View {
        Button(action: {
            WebViewManager.shared.loadURL(favorite.url)
        }) {
            HStack {
                Spacer()
                if let data = favorite.cachedIcon, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                } else {
                    Circle()
                        .foregroundStyle(.gray.opacity(0.25))
                        .frame(width: 48, height: 48)
                        .overlay {
                            if let firstLetter = favorite.title.first {
                                Text(String(firstLetter))
                                    .bold()
                            } else {
                                Image(systemName: "globe")
                                    .bold()
                            }
                        }
                }
                Spacer()
            }
            .padding(.vertical, 2.5)
        }
        .buttonBorderShape(.roundedRectangle(radius: 17.5))
        .background {
            if let color = favorite.color {
                RoundedRectangle(cornerRadius: 17.5)
                    .foregroundStyle(color)
            }
        }
        .contextMenu {
            Button {
                showingEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                withAnimation {
                    WebViewManager.shared.removeFavorite(favorite)
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditFavoriteSheet(favorite: $favorite, manager: WebViewManager.shared)
        }
        .onChange(of: favorite.url) {
            loadTask?.cancel()
            loadTask = nil
            loadTask = Task {
                await load()
            }
        }
        .task {
            await load()
        }
    }
    
    func load() async {
        if let urls = try? await FaviconFinder(url: favorite.url).fetchFaviconURLs() {
            let urls = urls.sorted { one, two in
                func priority(for format: FaviconFormatType) -> Int {
                    switch format {
                    case .icon: return 0
                    case .appleTouchIcon: return 1
                    default: return 2
                    }
                }
                
                return priority(for: one.format) < priority(for: two.format)
            }
            if let download = try? await urls.first?.download() {
                withAnimation {
                    favorite.cachedIcon = download.image?.data
                }
            }
        }
    }
}

struct EditFavoriteSheet: View {
    @Binding var favorite: Favorite
    @ObservedObject var manager: WebViewManager
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String = ""
    @State private var urlString: String = ""
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
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
                    Button("Save Changes", systemImage: "pencil") {
                        saveChanges()
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
            .navigationTitle("Edit Favorite")
        }
        .frame(width: 1200, height: 900)
        .onAppear {
            title = favorite.title
            urlString = favorite.url.absoluteString
        }
    }
    
    private func saveChanges() {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let validURL = URL(string: trimmedURL), validURL.scheme != nil else {
            errorMessage = "Please enter a valid URL with http:// or https://"
            return
        }
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? (validURL.host ?? trimmedURL) : trimmedTitle
        
        manager.updateFavorite(id: favorite.id, title: displayTitle, url: validURL)
        dismiss()
    }
}

extension CGSize {
    mutating func adding(_ new: CGSize) {
        self.width = self.width + new.width
        self.height = self.height + new.height
    }
    mutating func removing(_ new: CGSize) {
        self.width = self.width - new.width
        self.height = self.height - new.height
    }
}

#Preview {
    ContentView()
}
