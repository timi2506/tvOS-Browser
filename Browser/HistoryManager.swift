//
//  HistoryManager.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import Foundation
import SwiftUI
import Combine

struct HistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var url: URL
    var date: Date
    
    init(id: UUID = UUID(), title: String, url: URL, date: Date = Date()) {
        self.id = id
        self.title = title.isEmpty ? (url.host ?? url.absoluteString) : title
        self.url = url
        self.date = date
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    @Published private(set) var history: [HistoryItem] = []
    private let userDefaultsKey = "BrowserHistory"
    
    private init() {
        loadHistory()
    }
    
    func addEntry(title: String, url: URL) {
        let urlStr = url.absoluteString
        guard !urlStr.isEmpty, urlStr != "about:blank" else { return }
        
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (url.host ?? urlStr) : title
        
        if let first = history.first, first.url == url {
            return
        }
        
        let item = HistoryItem(title: displayTitle, url: url, date: Date())
        withAnimation {
            self.history.insert(item, at: 0)
            if self.history.count > 200 {
                self.history.removeLast()
            }
        }
        saveHistory()
    }
    
    func clearHistory() {
        withAnimation {
            self.history.removeAll()
        }
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let items = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            self.history = items
        }
    }
}
