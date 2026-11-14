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
    case desktopSafari = "Desktop (Mac Safari)"
    case mobileSafari = "Mobile (iPhone)"
    case iPadSafari = "Tablet (iPad)"
    case smartTV = "Apple TV"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var value: String {
        switch self {
        case .desktopSafari:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        case .mobileSafari:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
        case .iPadSafari:
            return "Mozilla/5.0 (iPad; CPU OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
        case .smartTV:
            return "Mozilla/5.0 (AppleTV; CPU OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        case .custom:
            return UserDefaults.standard.string(forKey: "CustomUserAgentString") ?? WebViewManager.defaultCustomUserAgent
        }
    }
}

struct ContentView: View {
    @StateObject var manager = WebViewManager.shared
    @FocusState var focusMenu: Bool
    @State var urlBarURL = ""
    @State var wrongURLPrompt = false
    
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
            QuickMenuView(manager: manager)
                .frame(width: 1200, height: 900)
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
            
            HStack(spacing: 15) {
                Spacer()
                NavigationLink(destination: {
                    DownloadsView()
                }) {
                    Label("Downloads", systemImage: "arrow.down.circle")
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
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 36))
        .frame(maxWidth: 520)
        .clipShape(RoundedRectangle(cornerRadius: 36))
        .transition(.move(edge: .leading).combined(with: .opacity))
        .focused($focusMenu)
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
        .onPlayPauseCommand {
            showingActionSheet.toggle()
        }
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
    
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    Spacer()
                }
            }
            .searchable(text: $urlBarURL, prompt: "Type URL or Search")
            .onSubmit(of: .search) {
                handleSubmit(query: urlBarURL)
            }
            .searchSuggestions {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        urlBarURL = suggestion
                        handleSubmit(query: suggestion)
                    }
                }
            }
            .onChange(of: urlBarURL) { newValue in
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
            return createGoogleSearchURL(for: trimmed)
        }
        
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        
        if trimmed.contains("."), let url = URL(string: "https://\(trimmed)") {
            return url
        }
        
        return createGoogleSearchURL(for: trimmed)
    }
    
    private func createGoogleSearchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
    
    private func fetchSuggestions(for query: String) async {
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
    
    @Published public var currentUserAgent: UserAgentType = .desktopSafari {
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
    
    @Published public var favorites: [Favorite] = []
    
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
        
        let defaultTab = BrowserTab(initialURL: URL(string: "https://google.com"))
        defaultTab.setUserAgent(currentUserAgent.value)
        self.tabs = [defaultTab]
        self.activeTabId = defaultTab.id
        observeActiveTab()
    }
    
    private func observeActiveTab() {
        activeTabCancellable?.cancel()
        if let current = activeTab {
            activeTabCancellable = current.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
    
    public func addNewTab(url: URL? = URL(string: "https://google.com")) {
        let newTab = BrowserTab(initialURL: url)
        newTab.setUserAgent(currentUserAgent.value)
        tabs.append(newTab)
        activeTabId = newTab.id
        observeActiveTab()
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
    }
    
    public func selectTab(id: UUID) {
        activeTabId = id
        observeActiveTab()
    }
    
    public func loadURL(_ url: URL) {
        if let tab = activeTab {
            tab.load(url: url)
        } else {
            addNewTab(url: url)
        }
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
           let saved = try? JSONDecoder().decode([Favorite].self, from: data), !saved.isEmpty {
            self.favorites = saved
        } else {
            Task {
                let google = await Favorite(title: "Google", url: URL(string: "https://google.com")!)
                let youtube = await Favorite(title: "YouTube", url: URL(string: "https://youtube.com")!)
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
                    Button("Save Changes") {
                        saveChanges()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Favorite")
            .onAppear {
                title = favorite.title
                urlString = favorite.url.absoluteString
            }
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
