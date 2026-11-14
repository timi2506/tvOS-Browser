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

struct ContentView: View {
    @StateObject var manager = WebViewManager.shared
    @FocusState var focusMenu: Bool
    @State var urlBarURL = ""
    @State var wrongURLPrompt = false
    
    var body: some View {
        NavigationStack {
            HStack {
                if manager.presentMenu {
                    VStack {
                        HStack {
                            HStack(spacing: 15) {
                                NavigationLink(destination: {
                                    SearchView(urlBarURL: urlBarURL) {
                                        manager.loadURL($0)
                                    }
                                }) {
                                    HStack {
                                        Text(manager.url?.host() ?? "URL or Search")
                                            .foregroundStyle(manager.url == nil ? .secondary : .primary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.bordered)
                                Button("Reload", systemImage: "arrow.clockwise") {}
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
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) {
                                ForEach($manager.favorites) { favorite in
                                    FavoriteButton(favorite: favorite)
                                }
                            }
                        }
                        .scrollClipDisabled()
                        .frame(maxWidth: 500)
                        Spacer()
                    }
                    .padding()
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 50))
                    .frame(maxWidth: 500)
                    .clipShape(RoundedRectangle(cornerRadius: 50))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .focused($focusMenu)
                }
                ZStack {
                    WebViewContent()
                    Circle()
                        .frame(width: 50, height: 50)
                        .foregroundStyle(.regularMaterial)
                        .opacity(0.75)
                        .overlay {
                            Circle()
                                .frame(width: 10, height: 10)
                                .foregroundStyle(.white)
                                .blur(radius: 5)
                        }
                        .overlay {
                            Circle()
                                .stroke(.gray.opacity(0.25), lineWidth: 1.5)
                                .frame(width: 50, height: 50)
                        }
                        .offset(manager.cursorOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: manager.presentMenu) {
            withAnimation {
                focusMenu = manager.presentMenu
            }
        }
        .onChange(of: manager.url) {
            if let url = manager.url {
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
}

import SwiftUI

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
    private init() {
        Task {
            await self.favorites.append(Favorite(title: "Google", url: URL(string: "https://google.com")!))
            await self.favorites.append(Favorite(title: "MyPayIndia", url: URL(string: "https://mypayindia.com")!))
            await self.favorites.append(Favorite(title: "YouTube", url: URL(string: "https://youtube.com")!))

        }
    }
    static let shared = WebViewManager()
    
    @Published private(set) var url: URL?
    @Published private(set) var isLoading = false
    @Published var cursorOffset: CGSize = .zero
    @Published var presentMenu = false
    @Published var favorites: [Favorite] = []
    @Published var currentColor: Color?
    
    var urlUpdateTask: Task<Void, Never>?
    func loadURL(_ url: URL) {
        // PLACEHOLDER
        onURLUpdate(url)
    }
    func onURLUpdate(_ newURL: URL) {
        urlUpdateTask?.cancel()
        urlUpdateTask = nil
        urlUpdateTask = Task {
            withAnimation {
                url = newURL
            }
            if url?.host() == newURL.host(), let color = try? await WebsiteColorParser.getColor(for: newURL.absoluteString) {
                withAnimation {
                    self.currentColor = Color(uiColor: color)
                }
            }
        }
    }
}

struct WebViewContent: View {
    @StateObject var manager = WebViewManager.shared
    var body: some View {
        VStack {
            Button("Up") {
                withAnimation {
                    manager.cursorOffset.removing(CGSize(width: 0, height: 5))
                }
            }
            HStack {
                Button("Left") {
                    withAnimation {
                        manager.cursorOffset.removing(CGSize(width: 5, height: 0))
                    }
                }
                Button("Right") {
                    withAnimation {
                        manager.cursorOffset.adding(CGSize(width: 5, height: 0))
                    }
                }
            }
            Button("Down") {
                withAnimation {
                    manager.cursorOffset.adding(CGSize(width: 0, height: 5))
                }
            }
            Button("Menu") {
                withAnimation {
                    manager.presentMenu.toggle()
                }
            }
           
            Text("Placeholder, replace !!!")
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
                        .frame(width: 50, height: 50)
                } else {
                    Circle()
                        .foregroundStyle(.gray.opacity(0.25))
                        .frame(width: 50, height: 50)
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
