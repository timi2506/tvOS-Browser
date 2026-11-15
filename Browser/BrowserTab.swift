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
    private var currentZoom: Double = 1.0
    
    var onStateChanged: (() -> Void)?
    var onTextInputFocused: ((_ placeholder: String, _ value: String) -> Void)?
    
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
        HistoryManager.shared.addEntry(title: self.title, url: url)
        onStateChanged?()
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
        guard let wv = webView else { return }
        WebKitBridge.tapAtPoint(x: point.x, y: point.y, on: wv) { [weak self] isTextInput, value, placeholder in
            if isTextInput {
                DispatchQueue.main.async {
                    self?.onTextInputFocused?(placeholder, value)
                }
            }
        }
    }
    
    func mouseMoved(to point: CGPoint, buttons: Int = 0) {
        guard let wv = webView else { return }
        WebKitBridge.mouseMove(at: point, buttons: buttons, on: wv)
    }
    
    func mouseDown(at point: CGPoint, button: Int = 0) {
        guard let wv = webView else { return }
        WebKitBridge.mouseDown(at: point, button: button, on: wv)
    }
    
    func mouseUp(at point: CGPoint, button: Int = 0, isHardwareMouse: Bool = false) {
        guard let wv = webView else { return }
        WebKitBridge.mouseUp(at: point, button: button, on: wv) { [weak self] isTextInput, value, placeholder in
            if isTextInput && !isHardwareMouse {
                DispatchQueue.main.async {
                    self?.onTextInputFocused?(placeholder, value)
                }
            }
        }
    }
    
    func contextMenu(at point: CGPoint) {
        guard let wv = webView else { return }
        WebKitBridge.contextMenu(at: point, on: wv)
    }
    
    func middleClick(at point: CGPoint) {
        guard let wv = webView else { return }
        WebKitBridge.middleClick(at: point, on: wv)
    }
    
    func handlePhysicalKey(key: String, code: String, keyCode: Int, isShift: Bool, isCtrl: Bool, isAlt: Bool, isMeta: Bool, isKeyUp: Bool) {
        guard let wv = webView else { return }
        WebKitBridge.handlePhysicalKey(key: key, code: code, keyCode: keyCode, isShift: isShift, isCtrl: isCtrl, isAlt: isAlt, isMeta: isMeta, isKeyUp: isKeyUp, on: wv)
    }
    
    func zoomIn() {
        currentZoom = min(currentZoom + 0.15, 3.0)
        applyZoom()
    }
    
    func zoomOut() {
        currentZoom = max(currentZoom - 0.15, 0.5)
        applyZoom()
    }
    
    func resetZoom() {
        currentZoom = 1.0
        applyZoom()
    }
    
    private func applyZoom() {
        guard let wv = webView else { return }
        WebKitBridge.setZoom(currentZoom, on: wv)
    }
    
    func scrollToTop() {
        guard let wv = webView else { return }
        WebKitBridge.scrollToTop(on: wv)
    }
    
    func scrollToBottom() {
        guard let wv = webView else { return }
        WebKitBridge.scrollToBottom(on: wv)
    }
    
    func fetchActiveElementInfo(completion: @escaping (_ placeholder: String, _ currentValue: String) -> Void) {
        guard let wv = webView else {
            completion("", "")
            return
        }
        let js = """
        (function() {
            var el = window.__lastFocusedInput || document.activeElement;
            if (!el || el === document.body || el === document.documentElement) {
                if (window.__lastFocusedInput && document.contains(window.__lastFocusedInput)) {
                    el = window.__lastFocusedInput;
                } else {
                    var inputs = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]), textarea');
                    if (inputs.length > 0) el = inputs[0];
                }
            }
            var placeholder = (el && el.getAttribute('placeholder')) || (el && el.getAttribute('aria-label')) || '';
            var val = (el && (el.value || el.innerText)) || '';
            return JSON.stringify({ placeholder: placeholder, value: val });
        })();
        """
        WebKitBridge.evaluateJavaScript(js, on: wv) { result, _ in
            if let jsonStr = result as? String,
               let data = jsonStr.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                completion(dict["placeholder"] ?? "", dict["value"] ?? "")
            } else {
                completion("", "")
            }
        }
    }
    
    func submitKeyboardText(_ text: String, pressEnter: Bool = true) {
        guard let wv = webView else { return }
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "'", with: "\\'")
                          .replacingOccurrences(of: "\n", with: "\\n")
                          .replacingOccurrences(of: "\r", with: "\\r")
        let js = """
        (function() {
            var el = window.__lastFocusedInput || document.activeElement;
            if (!el || el === document.body || el === document.documentElement) {
                if (window.__lastFocusedInput && document.contains(window.__lastFocusedInput)) {
                    el = window.__lastFocusedInput;
                } else {
                    var inputs = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="reset"]), textarea, [contenteditable="true"]');
                    if (inputs.length > 0) el = inputs[0];
                }
            }
            if (!el) return false;
            if (typeof el.focus === 'function') el.focus();

            var text = '\(escaped)';
            var tag = (el.tagName || '').toUpperCase();

            if (tag === 'INPUT' || tag === 'TEXTAREA') {
                if (typeof el.select === 'function') {
                    try { el.select(); } catch(e) {}
                }
                var inserted = false;
                try {
                    inserted = document.execCommand('insertText', false, text);
                } catch(e) {}

                if (!inserted || el.value !== text) {
                    var proto = Object.getPrototypeOf(el);
                    var setter = Object.getOwnPropertyDescriptor(proto, 'value') ? Object.getOwnPropertyDescriptor(proto, 'value').set : null;
                    if (setter) {
                        setter.call(el, text);
                    } else {
                        el.value = text;
                    }
                    if (el._valueTracker) {
                        el._valueTracker.setValue('');
                    }
                }
                try {
                    el.dispatchEvent(new InputEvent('beforeinput', { bubbles: true, cancelable: true, inputType: 'insertText', data: text }));
                    el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
                } catch(e) {
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                }
                el.dispatchEvent(new Event('change', { bubbles: true }));
            } else if (el.isContentEditable) {
                try {
                    var sel = window.getSelection();
                    var range = document.createRange();
                    range.selectNodeContents(el);
                    sel.removeAllRanges();
                    sel.addRange(range);
                    if (!document.execCommand('insertText', false, text)) {
                        el.innerText = text;
                    }
                } catch(e) {
                    el.innerText = text;
                }
                try {
                    el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
                } catch(e) {
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                }
            }

            if (\(pressEnter)) {
                var down = new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true, view: window });
                try {
                    Object.defineProperty(down, 'keyCode', { get: function() { return 13; } });
                    Object.defineProperty(down, 'which', { get: function() { return 13; } });
                } catch(e) {}
                var notPrevented = el.dispatchEvent(down);

                var press = new KeyboardEvent('keypress', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true, view: window });
                try {
                    Object.defineProperty(press, 'keyCode', { get: function() { return 13; } });
                    Object.defineProperty(press, 'which', { get: function() { return 13; } });
                } catch(e) {}
                el.dispatchEvent(press);

                var up = new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true, view: window });
                try {
                    Object.defineProperty(up, 'keyCode', { get: function() { return 13; } });
                    Object.defineProperty(up, 'which', { get: function() { return 13; } });
                } catch(e) {}
                el.dispatchEvent(up);

                if (notPrevented && el.form) {
                    if (typeof el.form.requestSubmit === 'function') {
                        try {
                            el.form.requestSubmit();
                        } catch(e) {
                            el.form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
                        }
                    } else {
                        var submitEvt = new Event('submit', { bubbles: true, cancelable: true });
                        if (el.form.dispatchEvent(submitEvt)) {
                            if (typeof el.form.submit === 'function') {
                                el.form.submit();
                            }
                        }
                    }
                }
            }
            return true;
        })();
        """
        WebKitBridge.evaluateJavaScript(js, on: wv)
    }
    
    func simulateEnter() {
        guard let wv = webView else { return }
        let js = """
        (function() {
            var el = window.__lastFocusedInput || document.activeElement || document.body;
            var down = new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true, view: window });
            try {
                Object.defineProperty(down, 'keyCode', { get: function() { return 13; } });
                Object.defineProperty(down, 'which', { get: function() { return 13; } });
            } catch(e) {}
            var notPrevented = el.dispatchEvent(down);

            var press = new KeyboardEvent('keypress', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true, view: window });
            try {
                Object.defineProperty(press, 'keyCode', { get: function() { return 13; } });
                Object.defineProperty(press, 'which', { get: function() { return 13; } });
            } catch(e) {}
            el.dispatchEvent(press);

            var up = new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true, view: window });
            try {
                Object.defineProperty(up, 'keyCode', { get: function() { return 13; } });
                Object.defineProperty(up, 'which', { get: function() { return 13; } });
            } catch(e) {}
            el.dispatchEvent(up);

            if (notPrevented && el.form) {
                if (typeof el.form.requestSubmit === 'function') {
                    try {
                        el.form.requestSubmit();
                    } catch(e) {
                        el.form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
                    }
                } else {
                    var submitEvt = new Event('submit', { bubbles: true, cancelable: true });
                    if (el.form.dispatchEvent(submitEvt)) {
                        if (typeof el.form.submit === 'function') {
                            el.form.submit();
                        }
                    }
                }
            }
            return true;
        })();
        """
        WebKitBridge.evaluateJavaScript(js, on: wv)
    }
    
    func scrollBy(dx: CGFloat, dy: CGFloat) {
        WebKitBridge.scrollBy(dx: dx, dy: dy, on: webView)
    }
    
    func sendRemoteKey(_ key: String, code: String, keyCode: Int) {
        WebKitBridge.sendTVRemoteKey(key, code: code, keyCode: keyCode, on: webView)
    }
    
    func sendRemoteBackKey() {
        WebKitBridge.sendTVRemoteBackKey(on: webView)
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
                        GameControllerManager.shared.syncAllControllers()
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
                    if let url = tab.url {
                        HistoryManager.shared.updateTitle(title, for: url)
                        tab.onStateChanged?()
                    }
                }
            case "URL":
                if let url = change?[.newKey] as? URL {
                    if tab.url != url {
                        tab.url = url
                        tab.fetchColorAndFavicon(for: url)
                        HistoryManager.shared.addEntry(title: tab.title, url: url)
                        tab.onStateChanged?()
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
    
    @objc(webView:didStartProvisionalNavigation:)
    func webView(_ webView: AnyObject, didStartProvisionalNavigation navigation: AnyObject?) {
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
    
    @objc(webView:didCommitNavigation:)
    func webView(_ webView: AnyObject, didCommit navigation: AnyObject?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tab = self.tab else { return }
            tab.estimatedProgress = max(tab.estimatedProgress, 0.4)
            tab.syncFromWebView()
        }
    }
    
    @objc(webView:didFinishNavigation:)
    func webView(_ webView: AnyObject, didFinish navigation: AnyObject?) {
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
                tab.onStateChanged?()
            }
        }
    }
    
    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: AnyObject, didFail navigation: AnyObject?, withError error: Error) {
        loadTimeoutTask?.cancel()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tab = self.tab else { return }
            tab.isLoading = false
            tab.estimatedProgress = 1.0
        }
    }
    
    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: AnyObject, didFailProvisionalNavigation navigation: AnyObject?, withError error: Error) {
        loadTimeoutTask?.cancel()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let tab = self.tab else { return }
            tab.isLoading = false
            tab.estimatedProgress = 1.0
        }
    }
    
    @objc(webView:decidePolicyForNavigationResponse:decisionHandler:)
    func webView(_ webView: AnyObject, decidePolicyForNavigationResponse response: AnyObject, decisionHandler: @escaping (Int) -> Void) {
        if let httpResponse = response.value(forKey: "response") as? HTTPURLResponse,
           let url = httpResponse.url {
            let mimeType = httpResponse.mimeType ?? ""
            let canShow = (response.value(forKey: "canShowMIMEType") as? Bool) ?? true
            let contentDisposition = httpResponse.allHeaderFields["Content-Disposition"] as? String ?? ""
            
            let isAttachment = contentDisposition.lowercased().contains("attachment")
            let isDownloadableExt = ["zip", "dmg", "pkg", "tar", "gz", "tgz", "bz2", "7z", "iso", "rar", "apk", "ipa", "deb", "exe", "bin", "torrent", "msi"].contains(url.pathExtension.lowercased())
            
            if (!canShow && !mimeType.isEmpty) || isAttachment || isDownloadableExt {
                decisionHandler(0)
                let filename = httpResponse.suggestedFilename ?? url.lastPathComponent
                DownloadManager.shared.promptDownload(from: url, suggestedFilename: filename)
                return
            }
        }
        decisionHandler(1)
    }
}
