//
//  BrowserTab.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import UIKit
import SwiftUI
import Combine
import FaviconFinder

final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String = "New Tab"
    @Published var url: URL?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var estimatedProgress: Double = 0.0
    @Published var currentColor: Color?
    @Published var favicon: UIImage?
    
    private(set) var webView: UIView!
    private var navDelegate: TabNavigationDelegate?
    private var kvoHelper: TabKVOHelper?
    private var colorTask: Task<Void, Never>?
    private var faviconTask: Task<Void, Never>?
    
    init(id: UUID = UUID(), initialURL: URL? = nil) {
        self.id = id
        super.init()
        
        self.webView = WebKitBridge.shared.makeWebView() ?? UIView()
        setupDelegatesAndObservers()
        
        if let initialURL = initialURL {
            load(url: initialURL)
        }
    }
    
    private func setupDelegatesAndObservers() {
        let delegate = TabNavigationDelegate(tab: self)
        self.navDelegate = delegate
        webView.setValue(delegate, forKey: "navigationDelegate")
        self.kvoHelper = TabKVOHelper(tab: self, webView: webView)
    }
    
    func syncFromWebView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let newURL = WebKitBridge.currentURL(on: self.webView)
            let newTitle = WebKitBridge.title(on: self.webView) ?? ""
            let loading = WebKitBridge.isLoading(on: self.webView)
            let back = WebKitBridge.canGoBack(on: self.webView)
            let forward = WebKitBridge.canGoForward(on: self.webView)
            let progress = WebKitBridge.estimatedProgress(on: self.webView)
            
            if self.url != newURL {
                self.url = newURL
                if let newURL = newURL {
                    self.fetchColorAndFavicon(for: newURL)
                }
            }
            if !newTitle.isEmpty && self.title != newTitle {
                self.title = newTitle
            }
            if progress >= 0.95 || !loading {
                self.isLoading = false
                self.estimatedProgress = 1.0
            } else {
                self.isLoading = loading
                self.estimatedProgress = progress
            }
            self.canGoBack = back
            self.canGoForward = forward
        }
    }
    
    func load(url: URL) {
        self.url = url
        self.isLoading = true
        self.estimatedProgress = 0.15
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        WebKitBridge.loadRequest(request, on: webView)
        fetchColorAndFavicon(for: url)
    }
    
    func setUserAgent(_ userAgent: String) {
        WebKitBridge.setUserAgent(userAgent, on: webView)
    }
    
    func reload() {
        self.isLoading = true
        self.estimatedProgress = 0.15
        WebKitBridge.reload(on: webView)
    }
    
    func goBack() {
        WebKitBridge.goBack(on: webView)
    }
    
    func goForward() {
        WebKitBridge.goForward(on: webView)
    }
    
    func clickAt(point: CGPoint) {
        WebKitBridge.tapAtPoint(x: point.x, y: point.y, on: webView)
    }
    
    func scrollBy(dx: CGFloat, dy: CGFloat) {
        WebKitBridge.scrollBy(dx: dx, dy: dy, on: webView)
    }
    
    func sendRemoteKey(_ key: String, code: String, keyCode: Int) {
        WebKitBridge.sendTVRemoteKey(key, code: code, keyCode: keyCode, on: webView)
    }
    
    func fetchColorAndFavicon(for url: URL) {
        colorTask?.cancel()
        colorTask = Task { [weak self] in
            if let nativeColor = try? await WebsiteColorParser.getColor(for: url.absoluteString) {
                await MainActor.run {
                    self?.currentColor = Color(uiColor: nativeColor)
                }
            }
        }
        
        faviconTask?.cancel()
        faviconTask = Task { [weak self] in
            if let urls = try? await FaviconFinder(url: url).fetchFaviconURLs(),
               let first = urls.first,
               let download = try? await first.download(),
               let img = download.image?.image {
                await MainActor.run {
                    self?.favicon = img
                }
            }
        }
    }
    
    deinit {
        kvoHelper = nil
        colorTask?.cancel()
        faviconTask?.cancel()
        webView?.setValue(nil, forKey: "navigationDelegate")
    }
}

final class TabKVOHelper: NSObject {
    private weak var tab: BrowserTab?
    private weak var webView: UIView?
    private let observedKeys = ["loading", "estimatedProgress", "title", "URL", "canGoBack", "canGoForward"]
    
    init(tab: BrowserTab, webView: UIView) {
        self.tab = tab
        self.webView = webView
        super.init()
        for key in observedKeys {
            webView.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tab = self.tab else { return }
            guard let keyPath = keyPath else { return }
            
            switch keyPath {
            case "loading":
                if let isLoading = change?[.newKey] as? Bool {
                    if !isLoading || tab.estimatedProgress >= 0.95 {
                        tab.isLoading = false
                        tab.estimatedProgress = 1.0
                    } else {
                        tab.isLoading = true
                    }
                }
            case "estimatedProgress":
                if let progress = change?[.newKey] as? Double {
                    tab.estimatedProgress = progress
                    if progress >= 0.95 {
                        tab.isLoading = false
                        tab.estimatedProgress = 1.0
                    }
                }
            case "title":
                if let title = change?[.newKey] as? String, !title.isEmpty {
                    tab.title = title
                }
            case "URL":
                if let url = change?[.newKey] as? URL {
                    if tab.url != url {
                        tab.url = url
                        tab.fetchColorAndFavicon(for: url)
                    }
                }
            case "canGoBack":
                if let canGoBack = change?[.newKey] as? Bool {
                    tab.canGoBack = canGoBack
                }
            case "canGoForward":
                if let canGoForward = change?[.newKey] as? Bool {
                    tab.canGoForward = canGoForward
                }
            default:
                break
            }
        }
    }
    
    deinit {
        for key in observedKeys {
            webView?.removeObserver(self, forKeyPath: key)
        }
    }
}

final class TabNavigationDelegate: NSObject {
    private weak var tab: BrowserTab?
    private var loadTimeoutTask: Task<Void, Never>?
    
    init(tab: BrowserTab) {
        self.tab = tab
    }
    
    @objc func webView(_ webView: AnyObject, didStartProvisionalNavigation navigation: AnyObject?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tab = self.tab else { return }
            tab.isLoading = true
            tab.estimatedProgress = 0.15
            tab.syncFromWebView()
            
            self.loadTimeoutTask?.cancel()
            self.loadTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let tab = self?.tab, tab.isLoading {
                        tab.isLoading = false
                        tab.estimatedProgress = 1.0
                    }
                }
            }
        }
    }
    
    @objc func webView(_ webView: AnyObject, didCommit navigation: AnyObject?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tab = self.tab else { return }
            tab.estimatedProgress = max(tab.estimatedProgress, 0.4)
            tab.syncFromWebView()
        }
    }
    
    @objc func webView(_ webView: AnyObject, didFinish navigation: AnyObject?) {
        loadTimeoutTask?.cancel()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tab = self.tab else { return }
            tab.isLoading = false
            tab.estimatedProgress = 1.0
            let newURL = WebKitBridge.currentURL(on: tab.webView)
            let newTitle = WebKitBridge.title(on: tab.webView) ?? ""
            if let newURL = newURL, tab.url != newURL {
                tab.url = newURL
                tab.fetchColorAndFavicon(for: newURL)
            }
            if !newTitle.isEmpty && tab.title != newTitle {
                tab.title = newTitle
            }
            tab.canGoBack = WebKitBridge.canGoBack(on: tab.webView)
            tab.canGoForward = WebKitBridge.canGoForward(on: tab.webView)
            if let url = tab.url {
                HistoryManager.shared.addEntry(title: tab.title, url: url)
            }
        }
    }
    
    @objc func webView(_ webView: AnyObject, didFail navigation: AnyObject?, withError error: Error) {
        loadTimeoutTask?.cancel()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tab = self.tab else { return }
            tab.isLoading = false
            tab.estimatedProgress = 1.0
        }
    }
    
    @objc func webView(_ webView: AnyObject, didFailProvisionalNavigation navigation: AnyObject?, withError error: Error) {
        loadTimeoutTask?.cancel()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tab = self.tab else { return }
            tab.isLoading = false
            tab.estimatedProgress = 1.0
        }
    }
    
    @objc func webView(_ webView: AnyObject, decidePolicyForNavigationResponse response: AnyObject, decisionHandler: @escaping (Int) -> Void) {
        if let httpResponse = response.value(forKey: "response") as? HTTPURLResponse,
           let url = httpResponse.url {
            let mimeType = httpResponse.mimeType ?? ""
            let canShow = (response.value(forKey: "canShowMIMEType") as? Bool) ?? true
            let contentDisposition = httpResponse.allHeaderFields["Content-Disposition"] as? String ?? ""
            
            let isAttachment = contentDisposition.lowercased().contains("attachment")
            let isDownloadableExt = ["zip", "dmg", "pkg", "tar", "gz", "7z", "iso", "rar"].contains(url.pathExtension.lowercased())
            
            if (!canShow && !mimeType.isEmpty) || isAttachment || isDownloadableExt {
                decisionHandler(0)
                let filename = httpResponse.suggestedFilename ?? url.lastPathComponent
                DownloadManager.shared.startDownload(from: url, suggestedFilename: filename)
                return
            }
        }
        decisionHandler(1)
    }
}
