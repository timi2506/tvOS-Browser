//
//  FileServerManager.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import Foundation
import Network
import Combine

final class FileServerManager: ObservableObject {
    static let shared = FileServerManager()
    
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var serverURL: URL?
    @Published private(set) var ipAddress: String?
    
    let defaultPort: UInt16 = 8080
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.timi2506.Browser.FileServer", qos: .userInitiated)
    
    private init() {
        if UserDefaults.standard.bool(forKey: "BrowserWiFiServerAutoStart") {
            start()
        }
    }
    
    func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }
    
    func start() {
        guard !isRunning else { return }
        guard let ip = getLocalIPAddress() else {
            return
        }
        
        let port = NWEndpoint.Port(rawValue: defaultPort) ?? 8080
        let parameters = NWParameters.tcp
        
        guard let nwListener = try? NWListener(using: parameters, on: port) else {
            return
        }
        
        self.listener = nwListener
        self.ipAddress = ip
        self.serverURL = URL(string: "http://\(ip):\(port.rawValue)/")
        
        nwListener.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isRunning = true
                    UserDefaults.standard.set(true, forKey: "BrowserWiFiServerAutoStart")
                case .failed, .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }
        
        nwListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        nwListener.start(queue: queue)
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.serverURL = nil
            self.ipAddress = nil
            UserDefaults.standard.set(false, forKey: "BrowserWiFiServerAutoStart")
        }
    }
    
    func urlForFile(_ item: DownloadItem) -> URL? {
        guard let ip = ipAddress ?? getLocalIPAddress() else { return nil }
        let port = defaultPort
        let idString = item.id.uuidString
        return URL(string: "http://\(ip):\(port)/download?id=\(idString)")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self = self, error == nil, let data = data,
                  let requestString = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            self.processRequest(requestString, connection: connection)
        }
    }
    
    private func processRequest(_ request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendResponse(connection: connection, status: "400 Bad Request", headers: [:], body: Data())
            return
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendResponse(connection: connection, status: "405 Method Not Allowed", headers: [:], body: Data())
            return
        }
        
        let target = parts[1]
        guard let urlComponents = URLComponents(string: target) else {
            sendResponse(connection: connection, status: "400 Bad Request", headers: [:], body: Data())
            return
        }
        
        let path = urlComponents.path
        if path == "/" || path == "/index.html" {
            let html = generateHTML()
            let bodyData = html.data(using: .utf8) ?? Data()
            sendResponse(connection: connection, status: "200 OK", headers: [
                "Content-Type": "text/html; charset=utf-8",
                "Content-Length": "\(bodyData.count)"
            ], body: bodyData)
            return
        }
        
        if path == "/download" {
            let queryItems = urlComponents.queryItems ?? []
            let fileID = queryItems.first(where: { $0.name == "id" })?.value
            let fileName = queryItems.first(where: { $0.name == "file" })?.value
            
            let downloads = DownloadManager.shared.downloads
            let match = downloads.first { item in
                if let id = fileID, item.id.uuidString == id { return true }
                if let name = fileName, item.filename == name { return true }
                return false
            }
            
            guard let item = match, FileManager.default.fileExists(atPath: item.localURL.path),
                  let fileData = try? Data(contentsOf: item.localURL) else {
                let notFound = "<h1>File Not Found</h1>".data(using: .utf8) ?? Data()
                sendResponse(connection: connection, status: "404 Not Found", headers: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Content-Length": "\(notFound.count)"
                ], body: notFound)
                return
            }
            
            let ext = item.localURL.pathExtension
            let mime = mimeType(for: ext)
            let safeName = item.filename.replacingOccurrences(of: "\"", with: "")
            
            sendResponse(connection: connection, status: "200 OK", headers: [
                "Content-Type": mime,
                "Content-Length": "\(fileData.count)",
                "Content-Disposition": "attachment; filename=\"\(safeName)\""
            ], body: fileData)
            return
        }
        
        let notFound = "<h1>Not Found</h1>".data(using: .utf8) ?? Data()
        sendResponse(connection: connection, status: "404 Not Found", headers: [
            "Content-Type": "text/html; charset=utf-8",
            "Content-Length": "\(notFound.count)"
        ], body: notFound)
    }
    
    private func sendResponse(connection: NWConnection, status: String, headers: [String: String], body: Data) {
        var headerString = "HTTP/1.1 \(status)\r\n"
        for (k, v) in headers {
            headerString += "\(k): \(v)\r\n"
        }
        headerString += "Connection: close\r\n\r\n"
        
        var responseData = headerString.data(using: .utf8) ?? Data()
        responseData.append(body)
        
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func generateHTML() -> String {
        let items = DownloadManager.shared.downloads
        if items.isEmpty {
            return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>body { font-family: system-ui, sans-serif; margin: 24px; }</style>
            </head>
            <body>
            <p>No downloads available.</p>
            </body>
            </html>
            """
        }
        
        var listItems = ""
        for item in items {
            let safeName = item.filename.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            let downloadURL = "/download?id=\(item.id.uuidString)"
            listItems += "<li><a href=\"\(downloadURL)\" download=\"\(safeName)\">\(safeName)</a> (\(item.formattedSize))</li>\n"
        }
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { font-family: system-ui, sans-serif; margin: 24px; font-size: 16px; }
        ul { padding-left: 20px; line-height: 1.8; }
        a { color: #0066cc; }
        </style>
        </head>
        <body>
        <ul>
        \(listItems)</ul>
        </body>
        </html>
        """
    }
    
    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "tar": return "application/x-tar"
        case "gz": return "application/gzip"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            if (flags & (IFF_UP | IFF_RUNNING)) != 0 && (flags & IFF_LOOPBACK) == 0 {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    var sa = ptr.pointee.ifa_addr.pointee
                    if getnameinfo(&sa, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        break
                    }
                }
            }
        }
        return address
    }
}
