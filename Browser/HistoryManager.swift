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
    private let saveHistoryKey = "BrowserSaveHistoryAcrossLaunches"
    
    @Published public var saveHistoryAcrossLaunches: Bool = {
        if UserDefaults.standard.object(forKey: "BrowserSaveHistoryAcrossLaunches") != nil {
            return UserDefaults.standard.bool(forKey: "BrowserSaveHistoryAcrossLaunches")
        }
        return true
    }() {
        didSet {
            UserDefaults.standard.set(saveHistoryAcrossLaunches, forKey: saveHistoryKey)
            if saveHistoryAcrossLaunches {
                saveHistory()
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }
    
    private init() {
        if saveHistoryAcrossLaunches {
            loadHistory()
        }
    }
    
    func addEntry(title: String, url: URL) {
        let urlStr = url.absoluteString
        guard !urlStr.isEmpty, urlStr != "about:blank" else { return }
        
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (url.host ?? urlStr) : title
        
        DispatchQueue.main.async {
            if let index = self.history.firstIndex(where: { $0.url == url }) {
                self.history.remove(at: index)
            }
            let item = HistoryItem(title: displayTitle, url: url, date: Date())
            withAnimation {
                self.history.insert(item, at: 0)
                if self.history.count > 200 {
                    self.history.removeLast()
                }
            }
            if self.saveHistoryAcrossLaunches {
                self.saveHistory()
            }
        }
    }
    
    func updateTitle(_ title: String, for url: URL) {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        DispatchQueue.main.async {
            if let index = self.history.firstIndex(where: { $0.url == url }) {
                self.history[index].title = title
                if self.saveHistoryAcrossLaunches {
                    self.saveHistory()
                }
            }
        }
    }
    
    func clearHistory() {
        withAnimation {
            self.history.removeAll()
        }
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
    
    private func saveHistory() {
        guard saveHistoryAcrossLaunches else { return }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    private func loadHistory() {
        guard saveHistoryAcrossLaunches else { return }
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let items = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            self.history = items
        }
    }
}
