//
//  DownloadManager.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import Foundation
import SwiftUI
import Combine

struct DownloadItem: Identifiable, Hashable {
    let id: UUID
    var filename: String
    var localURL: URL
    var fileSize: Int64
    var downloadDate: Date
    var originalURL: URL?
    
    init(id: UUID = UUID(), filename: String, localURL: URL, fileSize: Int64, downloadDate: Date = Date(), originalURL: URL? = nil) {
        self.id = id
        self.filename = filename
        self.localURL = localURL
        self.fileSize = fileSize
        self.downloadDate = downloadDate
        self.originalURL = originalURL
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: downloadDate)
    }
    
    var iconName: String {
        let ext = localURL.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "svg":
            return "photo.fill"
        case "mp4", "mov", "m4v", "mkv", "webm", "avi":
            return "film.fill"
        case "mp3", "m4a", "wav", "aac", "flac":
            return "music.note"
        case "zip", "tar", "gz", "rar", "7z":
            return "archivebox.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "html", "htm", "js", "css", "json", "xml":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc.fill"
        }
    }
}

final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    @Published private(set) var downloads: [DownloadItem] = []
    @Published private(set) var activeDownloads: [UUID: Double] = [:]
    
    private var downloadDirectory: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var session: URLSession!
    private var tasks: [Int: (UUID, URL, String?)] = [:]
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        loadExistingDownloads()
    }
    
    func loadExistingDownloads() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: downloadDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: .skipsHiddenFiles) else {
            return
        }
        
        var loaded: [DownloadItem] = []
        for file in files {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let date = values?.contentModificationDate ?? Date()
            loaded.append(DownloadItem(filename: file.lastPathComponent, localURL: file, fileSize: size, downloadDate: date))
        }
        
        self.downloads = loaded.sorted { $0.downloadDate > $1.downloadDate }
    }
    
    func startDownload(from url: URL, suggestedFilename: String? = nil) {
        let id = UUID()
        activeDownloads[id] = 0.0
        
        let task = session.downloadTask(with: url)
        tasks[task.taskIdentifier] = (id, url, suggestedFilename)
        task.resume()
    }
    
    func deleteDownload(_ item: DownloadItem) {
        try? FileManager.default.removeItem(at: item.localURL)
        downloads.removeAll { $0.id == item.id }
    }
    
    func clearAllDownloads() {
        for item in downloads {
            try? FileManager.default.removeItem(at: item.localURL)
        }
        downloads.removeAll()
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let info = tasks[downloadTask.taskIdentifier] else { return }
        let (id, originalURL, suggestedName) = info
        tasks.removeValue(forKey: downloadTask.taskIdentifier)
        activeDownloads.removeValue(forKey: id)
        
        let filename: String
        if let s = suggestedName, !s.isEmpty {
            filename = s
        } else if let responseFilename = downloadTask.response?.suggestedFilename, !responseFilename.isEmpty {
            filename = responseFilename
        } else {
            filename = originalURL.lastPathComponent.isEmpty ? "downloaded_file_\(Int(Date().timeIntervalSince1970))" : originalURL.lastPathComponent
        }
        
        var destination = downloadDirectory.appendingPathComponent(filename)
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: destination.path) {
            let ext = destination.pathExtension
            let name = destination.deletingPathExtension().lastPathComponent
            destination = downloadDirectory.appendingPathComponent("\(name)_\(Int(Date().timeIntervalSince1970)).\(ext)")
        }
        
        do {
            try fileManager.moveItem(at: location, to: destination)
            let values = try? destination.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(values?.fileSize ?? 0)
            let item = DownloadItem(id: id, filename: destination.lastPathComponent, localURL: destination, fileSize: size, downloadDate: Date(), originalURL: originalURL)
            
            withAnimation {
                self.downloads.insert(item, at: 0)
            }
        } catch {
            print("[DownloadManager] Failed to save downloaded file: \(error)")
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let info = tasks[downloadTask.taskIdentifier] else { return }
        let (id, _, _) = info
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            DispatchQueue.main.async {
                self.activeDownloads[id] = progress
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let info = tasks[task.taskIdentifier] {
            let (id, _, _) = info
            tasks.removeValue(forKey: task.taskIdentifier)
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: id)
            }
            if let error = error {
                print("[DownloadManager] Download error: \(error)")
            }
        }
    }
}
