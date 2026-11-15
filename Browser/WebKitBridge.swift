//
//  WebKitBridge.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import UIKit
import Foundation
import ObjectiveC

final class WebKitBridge {
    static let shared = WebKitBridge()
    
    private var webKitLoaded = false
    private var wkWebViewClass: UIView.Type?
    private var wkConfigClass: NSObject.Type?
    
    private init() {
        loadWebKit()
    }
    
    private func loadWebKit() {
        if webKitLoaded { return }
        
        let paths = [
            "/System/Library/Frameworks/WebKit.framework/WebKit",
            "/System/Library/PrivateFrameworks/WebKit.framework/WebKit"
        ]
        
        for path in paths {
            if let handle = dlopen(path, RTLD_NOW) {
                _ = handle
                webKitLoaded = true
                break
            }
        }
        
        if let cls = NSClassFromString("WKWebView") as? UIView.Type {
            self.wkWebViewClass = cls
            self.wkConfigClass = NSClassFromString("WKWebViewConfiguration") as? NSObject.Type
            webKitLoaded = true
        }
    }
    
    func makeWebView(frame: CGRect = .zero) -> UIView? {
        loadWebKit()
        guard let cls = wkWebViewClass else {
            return nil
        }
        
        var view: UIView
        if let configClass = wkConfigClass {
            let config = configClass.init()
            config.setValue(true, forKey: "allowsInlineMediaPlayback")
            config.setValue(0, forKey: "mediaTypesRequiringUserActionForPlayback")
            
            if let ucc = config.value(forKey: "userContentController") as? NSObject,
               let userScriptClass = NSClassFromString("WKUserScript") as? NSObject.Type {
                let source = GameControllerManager.shared.polyfillScript
                let scriptSel = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
                let allocSel = NSSelectorFromString("alloc")
                if let allocObj = (userScriptClass as AnyObject).perform(allocSel)?.takeUnretainedValue() {
                    typealias InitFunc = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject
                    let method = allocObj.method(for: scriptSel)
                    let callable = unsafeBitCast(method, to: InitFunc.self)
                    let scriptObj = callable(allocObj, scriptSel, source as NSString, 0, false)
                    let addSel = NSSelectorFromString("addUserScript:")
                    _ = ucc.perform(addSel, with: scriptObj)
                }
            }
            
            let sel = NSSelectorFromString("initWithFrame:configuration:")
            if let allocSel = NSSelectorFromString("alloc") as Selector?,
               let allocObj = (cls as AnyObject).perform(allocSel)?.takeUnretainedValue() {
                typealias InitFunc = @convention(c) (AnyObject, Selector, CGRect, AnyObject) -> AnyObject
                if let method = allocObj.method(for: sel) {
                    let callable = unsafeBitCast(method, to: InitFunc.self)
                    let initialized = callable(allocObj, sel, frame, config)
                    view = initialized as! UIView
                } else {
                    view = cls.init(frame: frame)
                }
            } else {
                view = cls.init(frame: frame)
            }
        } else {
            view = cls.init(frame: frame)
        }
        
        GameControllerManager.shared.updateActiveWebView(view)
        
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        view.setValue(userAgent, forKey: "customUserAgent")
        
        if let scrollView = view.value(forKey: "scrollView") as? UIScrollView {
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.contentInset = .zero
            scrollView.scrollIndicatorInsets = .zero
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.bounces = true
        }
        
        return view
    }
    
    static func loadRequest(_ request: URLRequest, on webView: UIView) {
        let sel = NSSelectorFromString("loadRequest:")
        if webView.responds(to: sel) {
            _ = webView.perform(sel, with: request)
        }
    }
    
    static func setUserAgent(_ userAgent: String, on webView: UIView?) {
        webView?.setValue(userAgent, forKey: "customUserAgent")
    }
    
    static func reload(on webView: UIView) {
        let sel = NSSelectorFromString("reload")
        if webView.responds(to: sel) {
            _ = webView.perform(sel)
        }
    }
    
    static func goBack(on webView: UIView) {
        let sel = NSSelectorFromString("goBack")
        if webView.responds(to: sel) {
            _ = webView.perform(sel)
        }
    }
    
    static func goForward(on webView: UIView) {
        let sel = NSSelectorFromString("goForward")
        if webView.responds(to: sel) {
            _ = webView.perform(sel)
        }
    }
    
    static func canGoBack(on webView: UIView) -> Bool {
        return (webView.value(forKey: "canGoBack") as? Bool) ?? false
    }
    
    static func canGoForward(on webView: UIView) -> Bool {
        return (webView.value(forKey: "canGoForward") as? Bool) ?? false
    }
    
    static func currentURL(on webView: UIView) -> URL? {
        return webView.value(forKey: "URL") as? URL
    }
    
    static func title(on webView: UIView) -> String? {
        return webView.value(forKey: "title") as? String
    }
    
    static func isLoading(on webView: UIView) -> Bool {
        return (webView.value(forKey: "isLoading") as? Bool) ?? false
    }
    
    static func estimatedProgress(on webView: UIView) -> Double {
        return (webView.value(forKey: "estimatedProgress") as? Double) ?? 0.0
    }
    
    static func evaluateJavaScript(_ script: String, on webView: UIView, completion: ((Any?, Error?) -> Void)? = nil) {
        let sel = NSSelectorFromString("evaluateJavaScript:completionHandler:")
        guard webView.responds(to: sel) else {
            completion?(nil, NSError(domain: "WebKitBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "evaluateJavaScript not available"]))
            return
        }
        
        typealias EvalFunc = @convention(c) (AnyObject, Selector, NSString, (@convention(block) (AnyObject?, NSError?) -> Void)?) -> Void
        let method = webView.method(for: sel)
        let callable = unsafeBitCast(method, to: EvalFunc.self)
        
        callable(webView, sel, script as NSString, { result, error in
            completion?(result, error)
        })
    }
    
    static func tapAtPoint(x: CGFloat, y: CGFloat, on webView: UIView, completion: ((Bool, String, String) -> Void)? = nil) {
        let js = """
        (function() {
            var x = \(x);
            var y = \(y);
            var el = document.elementFromPoint(x, y);
            if (el && el.shadowRoot && typeof el.shadowRoot.elementFromPoint === 'function') {
                var shadowEl = el.shadowRoot.elementFromPoint(x, y);
                if (shadowEl) el = shadowEl;
            }
            if (!el || el === document.body || el === document.documentElement) {
                var searchOffsets = [
                    [0, -8], [0, 8], [-8, 0], [8, 0],
                    [-12, -12], [12, -12], [-12, 12], [12, 12]
                ];
                for (var i = 0; i < searchOffsets.length; i++) {
                    var candidate = document.elementFromPoint(x + searchOffsets[i][0], y + searchOffsets[i][1]);
                    if (candidate && candidate !== document.body && candidate !== document.documentElement) {
                        var cTag = (candidate.tagName || '').toUpperCase();
                        if (cTag !== 'INPUT' && cTag !== 'TEXTAREA' && !candidate.isContentEditable && cTag !== 'LABEL') {
                            el = candidate;
                            break;
                        }
                    }
                }
            }
            if (!el) return JSON.stringify({ isTextInput: false, value: '', placeholder: '' });

            function isInputElem(elem) {
                if (!elem) return false;
                var tag = (elem.tagName || '').toUpperCase();
                if (tag === 'TEXTAREA' || elem.isContentEditable) return true;
                if (tag === 'INPUT') {
                    var type = (elem.getAttribute('type') || 'text').toLowerCase();
                    return !['button', 'submit', 'checkbox', 'radio', 'image', 'reset', 'file', 'hidden'].includes(type);
                }
                return false;
            }

            function findDirectTextInput(elem, px, py) {
                if (!elem) return null;
                var current = elem;
                while (current && current !== document.body && current !== document.documentElement) {
                    if (isInputElem(current)) {
                        var rect = current.getBoundingClientRect();
                        if (px >= rect.left && px <= rect.right && py >= rect.top && py <= rect.bottom) {
                            return current;
                        }
                        return null;
                    }
                    current = current.parentElement;
                }
                return null;
            }

            var directInput = findDirectTextInput(el, x, y);

            var target = (el.closest && el.closest('a, button, input, textarea, select, [role="button"], [role="link"], [role="tab"], [tabindex], label')) || el;
            if (typeof target.focus === 'function') {
                target.focus();
            }
            var eventTypes = ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'];
            for (var t = 0; t < eventTypes.length; t++) {
                var evt = new MouseEvent(eventTypes[t], {
                    view: window,
                    bubbles: true,
                    cancelable: true,
                    clientX: x,
                    clientY: y,
                    screenX: x,
                    screenY: y,
                    buttons: 1
                });
                target.dispatchEvent(evt);
            }
            if (typeof target.click === 'function') {
                target.click();
            }

            if (!directInput && document.activeElement && isInputElem(document.activeElement)) {
                var activeRect = document.activeElement.getBoundingClientRect();
                if (!(x >= activeRect.left && x <= activeRect.right && y >= activeRect.top && y <= activeRect.bottom)) {
                    if (typeof document.activeElement.blur === 'function') {
                        document.activeElement.blur();
                    }
                } else {
                    directInput = document.activeElement;
                }
            }

            var isTextInput = directInput !== null;
            var val = '';
            var placeholder = '';
            if (isTextInput && directInput) {
                window.__lastFocusedInput = directInput;
                val = directInput.value || directInput.innerText || '';
                placeholder = directInput.getAttribute('placeholder') || directInput.getAttribute('aria-label') || '';
            }
            return JSON.stringify({
                isTextInput: isTextInput,
                value: val,
                placeholder: placeholder
            });
        })();
        """
        evaluateJavaScript(js, on: webView) { result, _ in
            if let str = result as? String,
               let data = str.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let isTextInput = (dict["isTextInput"] as? Bool) ?? false
                let val = (dict["value"] as? String) ?? ""
                let placeholder = (dict["placeholder"] as? String) ?? ""
                completion?(isTextInput, val, placeholder)
            } else {
                completion?(false, "", "")
            }
        }
    }
    
    static func sendTVRemoteKey(_ key: String, code: String, keyCode: Int, on webView: UIView) {
        let js = """
        (function() {
            var target = document.activeElement || document.body || document.documentElement || window;
            var downEvent = new KeyboardEvent('keydown', {
                key: '\(key)',
                code: '\(code)',
                keyCode: \(keyCode),
                which: \(keyCode),
                bubbles: true,
                cancelable: true,
                view: window
            });
            try {
                Object.defineProperty(downEvent, 'keyCode', { get: function() { return \(keyCode); } });
                Object.defineProperty(downEvent, 'which', { get: function() { return \(keyCode); } });
            } catch(e) {}
            target.dispatchEvent(downEvent);
            if ('\(key)' === 'Enter') {
                var pressEvent = new KeyboardEvent('keypress', {
                    key: '\(key)',
                    code: '\(code)',
                    keyCode: \(keyCode),
                    which: \(keyCode),
                    bubbles: true,
                    cancelable: true,
                    view: window
                });
                try {
                    Object.defineProperty(pressEvent, 'keyCode', { get: function() { return \(keyCode); } });
                    Object.defineProperty(pressEvent, 'which', { get: function() { return \(keyCode); } });
                } catch(e) {}
                target.dispatchEvent(pressEvent);
            }
            var upEvent = new KeyboardEvent('keyup', {
                key: '\(key)',
                code: '\(code)',
                keyCode: \(keyCode),
                which: \(keyCode),
                bubbles: true,
                cancelable: true,
                view: window
            });
            try {
                Object.defineProperty(upEvent, 'keyCode', { get: function() { return \(keyCode); } });
                Object.defineProperty(upEvent, 'which', { get: function() { return \(keyCode); } });
            } catch(e) {}
            target.dispatchEvent(upEvent);
        })();
        """
        evaluateJavaScript(js, on: webView)
    }
    
    static func sendTVRemoteBackKey(on webView: UIView) {
        let js = """
        (function() {
            var target = document.activeElement || document.body || document.documentElement || window;
            var candidates = [
                { key: 'Escape', code: 'Escape', keyCode: 27 },
                { key: 'GoBack', code: 'BrowserBack', keyCode: 461 },
                { key: 'Return', code: 'Return', keyCode: 10009 },
                { key: 'Backspace', code: 'Backspace', keyCode: 8 }
            ];
            for (var i = 0; i < candidates.length; i++) {
                var c = candidates[i];
                var down = new KeyboardEvent('keydown', {
                    key: c.key,
                    code: c.code,
                    keyCode: c.keyCode,
                    which: c.keyCode,
                    bubbles: true,
                    cancelable: true,
                    view: window
                });
                try {
                    Object.defineProperty(down, 'keyCode', { get: function() { return c.keyCode; } });
                    Object.defineProperty(down, 'which', { get: function() { return c.keyCode; } });
                } catch(e) {}
                var notCancelled = target.dispatchEvent(down);
                var up = new KeyboardEvent('keyup', {
                    key: c.key,
                    code: c.code,
                    keyCode: c.keyCode,
                    which: c.keyCode,
                    bubbles: true,
                    cancelable: true,
                    view: window
                });
                try {
                    Object.defineProperty(up, 'keyCode', { get: function() { return c.keyCode; } });
                    Object.defineProperty(up, 'which', { get: function() { return c.keyCode; } });
                } catch(e) {}
                target.dispatchEvent(up);
                if (!notCancelled || down.defaultPrevented) {
                    break;
                }
            }
        })();
        """
        evaluateJavaScript(js, on: webView)
    }
    
    static func scrollBy(dx: CGFloat, dy: CGFloat, on webView: UIView) {
        if let scrollView = webView.value(forKey: "scrollView") as? UIScrollView {
            var newOffset = scrollView.contentOffset
            newOffset.x += dx
            newOffset.y += dy
            
            let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            
            newOffset.x = min(max(0, newOffset.x), maxOffsetX)
            newOffset.y = min(max(0, newOffset.y), maxOffsetY)
            
            scrollView.setContentOffset(newOffset, animated: true)
        }
        
        let js = "window.scrollBy({ left: \(dx), top: \(dy), behavior: 'smooth' });"
        evaluateJavaScript(js, on: webView)
    }
}
