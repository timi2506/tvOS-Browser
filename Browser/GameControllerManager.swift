//
//  GameControllerManager.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import Foundation
import UIKit
import SwiftUI
import GameController
import Combine

final class GameControllerManager: ObservableObject {
    static let shared = GameControllerManager()
    
    @Published private(set) var connectedControllers: [GCController] = []
    @Published var controllerNavigationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(controllerNavigationEnabled, forKey: "ControllerBrowserNavigation")
        }
    }
    
    var connectedNamesDescription: String {
        if connectedControllers.isEmpty {
            return "No controller connected"
        }
        let names = connectedControllers.compactMap { $0.vendorName ?? "Controller" }
        return "\(connectedControllers.count) connected: " + names.joined(separator: ", ")
    }
    
    private var displayLink: CADisplayLink?
    private weak var activeWebView: UIView?
    private var isPagePollingGamepad = false
    private var lastPollCheck = Date.distantPast
    
    private var prevButtonA: [Int: Bool] = [:]
    private var prevButtonB: [Int: Bool] = [:]
    private var prevL1: [Int: Bool] = [:]
    private var prevR1: [Int: Bool] = [:]
    private var prevMenu: [Int: Bool] = [:]
    private var prevOptions: [Int: Bool] = [:]
    
    var polyfillScript: String {
        return """
        (function() {
            if (window.__tvosGamepadPolyfillLoaded) return;
            window.__tvosGamepadPolyfillLoaded = true;

            var connectedGamepads = {};
            var lastPollTime = 0;

            function createGamepad(index, id) {
                var buttons = [];
                for (var i = 0; i < 17; i++) {
                    buttons.push({ pressed: false, touched: false, value: 0 });
                }
                return {
                    id: id || "Wireless Controller (STANDARD GAMEPAD)",
                    index: index,
                    connected: true,
                    timestamp: performance.now(),
                    mapping: "standard",
                    axes: [0, 0, 0, 0],
                    buttons: buttons,
                    vibrationActuator: {
                        type: "dual-rumble",
                        playEffect: function() { return Promise.resolve("complete"); },
                        reset: function() { return Promise.resolve("complete"); }
                    }
                };
            }

            window.__gamepadConnected = function(index, id) {
                var gp = connectedGamepads[index] || createGamepad(index, id);
                gp.id = id || gp.id;
                gp.connected = true;
                gp.timestamp = performance.now();
                connectedGamepads[index] = gp;
                try {
                    var event = new Event('gamepadconnected', { bubbles: true, cancelable: false });
                    Object.defineProperty(event, 'gamepad', { value: gp, enumerable: true });
                    window.dispatchEvent(event);
                } catch(e) {
                    try {
                        var evt = document.createEvent('CustomEvent');
                        evt.initCustomEvent('gamepadconnected', true, false, { gamepad: gp });
                        evt.gamepad = gp;
                        window.dispatchEvent(evt);
                    } catch(err) {}
                }
            };

            window.__gamepadDisconnected = function(index) {
                var gp = connectedGamepads[index];
                if (gp) {
                    gp.connected = false;
                    gp.timestamp = performance.now();
                    try {
                        var event = new Event('gamepaddisconnected', { bubbles: true, cancelable: false });
                        Object.defineProperty(event, 'gamepad', { value: gp, enumerable: true });
                        window.dispatchEvent(event);
                    } catch(e) {
                        try {
                            var evt = document.createEvent('CustomEvent');
                            evt.initCustomEvent('gamepaddisconnected', true, false, { gamepad: gp });
                            evt.gamepad = gp;
                            window.dispatchEvent(evt);
                        } catch(err) {}
                    }
                    delete connectedGamepads[index];
                }
            };

            window.__gamepadUpdate = function(index, id, axes, buttons) {
                var gp = connectedGamepads[index];
                if (!gp) {
                    window.__gamepadConnected(index, id);
                    gp = connectedGamepads[index];
                }
                if (!gp) return;
                gp.timestamp = performance.now();
                if (axes && axes.length >= 4) {
                    gp.axes[0] = axes[0];
                    gp.axes[1] = axes[1];
                    gp.axes[2] = axes[2];
                    gp.axes[3] = axes[3];
                }
                if (buttons) {
                    for (var i = 0; i < buttons.length && i < gp.buttons.length; i++) {
                        var val = buttons[i];
                        var isTrigger = (i === 6 || i === 7);
                        var isPressed = isTrigger ? (val > 0.15) : (val > 0.5);
                        gp.buttons[i].value = val;
                        gp.buttons[i].pressed = isPressed;
                        gp.buttons[i].touched = val > 0;
                    }
                }
            };

            window.__isGamepadPolling = function() {
                return (performance.now() - lastPollTime) < 2000;
            };

            try {
                Object.defineProperty(navigator, 'getGamepads', {
                    value: function() {
                        lastPollTime = performance.now();
                        var result = [];
                        for (var i = 0; i < 4; i++) {
                            result.push(connectedGamepads[i] || null);
                        }
                        return result;
                    },
                    writable: true,
                    configurable: true,
                    enumerable: true
                });
                if (typeof navigator.webkitGetGamepads === 'undefined') {
                    navigator.webkitGetGamepads = navigator.getGamepads;
                }
            } catch(e) {
                navigator.getGamepads = function() {
                    lastPollTime = performance.now();
                    var result = [];
                    for (var i = 0; i < 4; i++) {
                        result.push(connectedGamepads[i] || null);
                    }
                    return result;
                };
            }
        })();
        """
    }
    
    private init() {
        if UserDefaults.standard.object(forKey: "ControllerBrowserNavigation") != nil {
            self.controllerNavigationEnabled = UserDefaults.standard.bool(forKey: "ControllerBrowserNavigation")
        } else {
            self.controllerNavigationEnabled = true
        }
        
        setupNotificationObservers()
        refreshConnectedControllers()
        startDisplayLink()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(controllerConnected(_:)), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDisconnected(_:)), name: .GCControllerDidDisconnect, object: nil)
        GCController.startWirelessControllerDiscovery()
    }
    
    private func refreshConnectedControllers() {
        connectedControllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        syncAllControllers()
    }
    
    @objc private func controllerConnected(_ notification: Notification) {
        refreshConnectedControllers()
    }
    
    @objc private func controllerDisconnected(_ notification: Notification) {
        refreshConnectedControllers()
    }
    
    private func startDisplayLink() {
        displayLink?.invalidate()
        let dl = CADisplayLink(target: self, selector: #selector(tick))
        dl.add(to: .main, forMode: .common)
        self.displayLink = dl
    }
    
    func updateActiveWebView(_ webView: UIView?) {
        self.activeWebView = webView
        syncAllControllers()
    }
    
    func syncAllControllers() {
        guard let wv = activeWebView else { return }
        for (index, controller) in connectedControllers.prefix(4).enumerated() {
            let id = formattedId(for: controller)
            let js = "window.__gamepadConnected && window.__gamepadConnected(\(index), '\(id)');"
            WebKitBridge.evaluateJavaScript(js, on: wv)
        }
    }
    
    private func formattedId(for controller: GCController) -> String {
        let name = controller.vendorName ?? "Wireless Controller"
        return "\(name) (STANDARD GAMEPAD)"
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
    
    @objc private func tick() {
        guard let wv = activeWebView, !connectedControllers.isEmpty else { return }
        
        let now = Date()
        if now.timeIntervalSince(lastPollCheck) > 1.5 {
            lastPollCheck = now
            WebKitBridge.evaluateJavaScript("window.__isGamepadPolling ? window.__isGamepadPolling() : false", on: wv) { [weak self] res, _ in
                if let isPolling = res as? Bool {
                    self?.isPagePollingGamepad = isPolling
                }
            }
        }
        
        for (index, controller) in connectedControllers.prefix(4).enumerated() {
            guard let profile = controller.extendedGamepad else { continue }
            
            let ax0 = Double(profile.leftThumbstick.xAxis.value)
            let ax1 = Double(-profile.leftThumbstick.yAxis.value)
            let ax2 = Double(profile.rightThumbstick.xAxis.value)
            let ax3 = Double(-profile.rightThumbstick.yAxis.value)
            
            let b0 = Double(profile.buttonA.value)
            let b1 = Double(profile.buttonB.value)
            let b2 = Double(profile.buttonX.value)
            let b3 = Double(profile.buttonY.value)
            let b4 = Double(profile.leftShoulder.value)
            let b5 = Double(profile.rightShoulder.value)
            let b6 = Double(profile.leftTrigger.value)
            let b7 = Double(profile.rightTrigger.value)
            let b8 = Double(profile.buttonOptions?.value ?? 0)
            let b9 = Double(profile.buttonMenu.value)
            let b10 = Double(profile.leftThumbstickButton?.value ?? 0)
            let b11 = Double(profile.rightThumbstickButton?.value ?? 0)
            let b12 = Double(profile.dpad.up.value)
            let b13 = Double(profile.dpad.down.value)
            let b14 = Double(profile.dpad.left.value)
            let b15 = Double(profile.dpad.right.value)
            let b16 = Double(profile.buttonHome?.value ?? 0)
            
            let id = formattedId(for: controller)
            let axesStr = "[\(ax0),\(ax1),\(ax2),\(ax3)]"
            let buttonsStr = "[\(b0),\(b1),\(b2),\(b3),\(b4),\(b5),\(b6),\(b7),\(b8),\(b9),\(b10),\(b11),\(b12),\(b13),\(b14),\(b15),\(b16)]"
            let js = "window.__gamepadUpdate && window.__gamepadUpdate(\(index), '\(id)', \(axesStr), \(buttonsStr));"
            WebKitBridge.evaluateJavaScript(js, on: wv)
            
            if index == 0 && controllerNavigationEnabled && !isPagePollingGamepad {
                handleNavigation(profile: profile)
            }
        }
    }
    
    private func handleNavigation(profile: GCExtendedGamepad) {
        let manager = WebViewManager.shared
        guard !manager.presentMenu && !manager.presentQuickMenu && !manager.presentKeyboard else { return }
        
        let lx = CGFloat(profile.leftThumbstick.xAxis.value)
        let ly = CGFloat(profile.leftThumbstick.yAxis.value)
        if abs(lx) > 0.08 || abs(ly) > 0.08 {
            let sens = manager.touchpadSensitivity.cursorMultiplier
            manager.moveCursor(by: CGSize(width: lx * 18.0 * sens, height: -ly * 18.0 * sens))
        }
        
        let rx = CGFloat(profile.rightThumbstick.xAxis.value)
        let ry = CGFloat(profile.rightThumbstick.yAxis.value)
        if abs(ry) > 0.08 || abs(rx) > 0.08 {
            let sens = manager.touchpadSensitivity.scrollMultiplier
            manager.scrollActiveTab(dx: -rx * 25.0 * sens, dy: -ry * 25.0 * sens)
        }
        
        let aPressed = profile.buttonA.isPressed
        if aPressed && !(prevButtonA[0] ?? false) {
            manager.tapAtCursor()
        }
        prevButtonA[0] = aPressed
        
        let bPressed = profile.buttonB.isPressed
        if bPressed && !(prevButtonB[0] ?? false) {
            if let tab = manager.activeTab, tab.canGoBack {
                tab.goBack()
            }
        }
        prevButtonB[0] = bPressed
        
        let l1Pressed = profile.leftShoulder.isPressed
        if l1Pressed && !(prevL1[0] ?? false) {
            manager.selectPreviousTab()
        }
        prevL1[0] = l1Pressed
        
        let r1Pressed = profile.rightShoulder.isPressed
        if r1Pressed && !(prevR1[0] ?? false) {
            manager.selectNextTab()
        }
        prevR1[0] = r1Pressed
        
        let menuPressed = profile.buttonMenu.isPressed
        if menuPressed && !(prevMenu[0] ?? false) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                manager.presentQuickMenu.toggle()
            }
        }
        prevMenu[0] = menuPressed
        
        if let opt = profile.buttonOptions {
            let optPressed = opt.isPressed
            if optPressed && !(prevOptions[0] ?? false) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    manager.presentMenu.toggle()
                }
            }
            prevOptions[0] = optPressed
        }
    }
}
