//
//  TVWebViewRepresentable.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import UIKit
import SwiftUI
import GameController

struct TVWebViewRepresentable: UIViewControllerRepresentable {
    @ObservedObject var manager: WebViewManager
    
    init(manager: WebViewManager) {
        self.manager = manager
    }
    
    func makeUIViewController(context: Context) -> TVWebViewController {
        NativeInputManager.shared.start(with: manager)
        let controller = TVWebViewController(manager: manager)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: TVWebViewController, context: Context) {
        uiViewController.updateActiveTab()
        uiViewController.updatePanGestureState()
    }
}

final class TVWebViewController: GCEventViewController, UIGestureRecognizerDelegate {
    private let manager: WebViewManager
    private var currentWebView: UIView?
    private var panGesture: UIPanGestureRecognizer?
    
    private var directionalTimer: Timer?
    private var activeDirection: (dx: CGFloat, dy: CGFloat)?
    
    private var backTimer: Timer?
    private var handledLongPress = false
    
    private var playPauseTimer: Timer?
    private var handledPlayPauseLongPress = false
    
    init(manager: WebViewManager) {
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var isWebInteractionActive: Bool {
        if manager.presentMenu || manager.presentQuickMenu || manager.presentKeyboard {
            return false
        }
        if presentedViewController != nil || view.window?.rootViewController?.presentedViewController != nil {
            return false
        }
        if let focusedView = UIFocusSystem.focusSystem(for: view)?.focusedItem as? UIView {
            if !focusedView.isDescendant(of: view) && !view.isDescendant(of: focusedView) && focusedView !== view {
                return false
            }
        }
        return true
    }
    
    override var canBecomeFirstResponder: Bool {
        return isWebInteractionActive
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NativeInputManager.shared.start(with: manager)
        controllerUserInteractionEnabled = false
        view.backgroundColor = .black
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        view.addGestureRecognizer(pan)
        self.panGesture = pan
        
        updateActiveTab()
        updatePanGestureState()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        manager.updateViewSize(view.bounds.size)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updatePanGestureState()
        manager.updateViewSize(view.bounds.size)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDirectionalMovement()
        if isFirstResponder {
            resignFirstResponder()
        }
    }
    
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        updatePanGestureState()
    }
    
    func updateActiveTab() {
        guard let tab = manager.activeTab else { return }
        if currentWebView !== tab.webView {
            currentWebView?.removeFromSuperview()
            currentWebView = tab.webView
            
            tab.webView.frame = view.bounds
            tab.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(tab.webView)
            GameControllerManager.shared.updateActiveWebView(tab.webView)
        }
    }
    
    func updatePanGestureState() {
        controllerUserInteractionEnabled = !isWebInteractionActive
        if !isWebInteractionActive {
            stopDirectionalMovement()
            panGesture?.isEnabled = false
            if isFirstResponder {
                resignFirstResponder()
            }
        } else {
            panGesture?.isEnabled = true
            if !isFirstResponder && canBecomeFirstResponder {
                becomeFirstResponder()
            }
        }
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGesture && !isWebInteractionActive {
            return false
        }
        return true
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isWebInteractionActive else { return }
        let translation = gesture.translation(in: view)
        gesture.setTranslation(.zero, in: view)
        
        switch manager.controlMode {
        case .cursor:
            let sens = manager.touchpadSensitivity.cursorMultiplier
            manager.moveCursor(by: CGSize(width: translation.x * sens, height: translation.y * sens))
        case .scroll:
            let sens = manager.touchpadSensitivity.scrollMultiplier
            manager.scrollActiveTab(dx: -translation.x * sens, dy: -translation.y * sens)
        case .tvRemote:
            if abs(translation.y) > 25 {
                if translation.y < 0 {
                    manager.sendRemoteKey(key: "ArrowUp", code: "ArrowUp", keyCode: 38)
                } else {
                    manager.sendRemoteKey(key: "ArrowDown", code: "ArrowDown", keyCode: 40)
                }
            } else if abs(translation.x) > 25 {
                if translation.x < 0 {
                    manager.sendRemoteKey(key: "ArrowLeft", code: "ArrowLeft", keyCode: 37)
                } else {
                    manager.sendRemoteKey(key: "ArrowRight", code: "ArrowRight", keyCode: 39)
                }
            }
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isWebInteractionActive, let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }
        #if targetEnvironment(simulator)
        let isPointer = true
        #else
        let isPointer = (touch.type == .indirectPointer)
        #endif
        if isPointer {
            NativeInputManager.shared.markMouseConnected()
            let loc = touch.location(in: view)
            manager.cursorPosition = loc
            if manager.controlMode != .cursor {
                manager.controlMode = .cursor
            }
            manager.activeTab?.mouseDown(at: loc, button: 0)
            return
        }
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isWebInteractionActive, let touch = touches.first else {
            super.touchesMoved(touches, with: event)
            return
        }
        #if targetEnvironment(simulator)
        let isPointer = true
        #else
        let isPointer = (touch.type == .indirectPointer)
        #endif
        if isPointer {
            NativeInputManager.shared.markMouseConnected()
            let loc = touch.location(in: view)
            manager.cursorPosition = loc
            manager.activeTab?.mouseMoved(to: loc, buttons: 1)
            return
        }
        super.touchesMoved(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isWebInteractionActive, let touch = touches.first else {
            super.touchesEnded(touches, with: event)
            return
        }
        #if targetEnvironment(simulator)
        let isPointer = true
        #else
        let isPointer = (touch.type == .indirectPointer)
        #endif
        if isPointer {
            let loc = touch.location(in: view)
            manager.cursorPosition = loc
            manager.activeTab?.mouseUp(at: loc, button: 0, isHardwareMouse: true)
            return
        }
        super.touchesEnded(touches, with: event)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isWebInteractionActive, let touch = touches.first else {
            super.touchesCancelled(touches, with: event)
            return
        }
        #if targetEnvironment(simulator)
        let isPointer = true
        #else
        let isPointer = (touch.type == .indirectPointer)
        #endif
        if isPointer {
            let loc = touch.location(in: view)
            manager.cursorPosition = loc
            manager.activeTab?.mouseUp(at: loc, button: 0, isHardwareMouse: true)
            return
        }
        super.touchesCancelled(touches, with: event)
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isWebInteractionActive else {
            super.pressesBegan(presses, with: event)
            return
        }
        
        var unhandledPresses: Set<UIPress> = []
        for press in presses {
            if let key = press.key {
                NativeInputManager.shared.markKeyboardConnected()
                if handleHardwareKeyPress(key, isKeyUp: false) {
                    continue
                }
            } else {
                switch press.type {
                case .select:
                    if manager.controlMode != .scroll {
                        continue
                    }
                case .upArrow:
                    startDirectionalMovement(dx: 0, dy: -1)
                    continue
                case .downArrow:
                    startDirectionalMovement(dx: 0, dy: 1)
                    continue
                case .leftArrow:
                    startDirectionalMovement(dx: -1, dy: 0)
                    continue
                case .rightArrow:
                    startDirectionalMovement(dx: 1, dy: 0)
                    continue
                case .playPause:
                    handledPlayPauseLongPress = false
                    playPauseTimer?.invalidate()
                    playPauseTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                        guard let self = self else { return }
                        self.handledPlayPauseLongPress = true
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                self.manager.presentMenu.toggle()
                            }
                        }
                    }
                    continue
                case .menu:
                    handledLongPress = false
                    backTimer?.invalidate()
                    backTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                        guard let self = self else { return }
                        self.handledLongPress = true
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                self.manager.presentMenu.toggle()
                            }
                        }
                    }
                    continue
                default:
                    break
                }
            }
            unhandledPresses.insert(press)
        }
        if !unhandledPresses.isEmpty {
            super.pressesBegan(unhandledPresses, with: event)
        }
    }
    
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isWebInteractionActive else {
            super.pressesEnded(presses, with: event)
            return
        }
        
        var unhandledPresses: Set<UIPress> = []
        for press in presses {
            if let key = press.key {
                if handleHardwareKeyPress(key, isKeyUp: true) {
                    continue
                }
            } else {
                switch press.type {
                case .upArrow, .downArrow, .leftArrow, .rightArrow:
                    stopDirectionalMovement()
                    continue
                case .select:
                    switch manager.controlMode {
                    case .cursor:
                        manager.tapAtCursor()
                        continue
                    case .scroll:
                        break
                    case .tvRemote:
                        manager.sendRemoteKey(key: "Enter", code: "Enter", keyCode: 13)
                        continue
                    }
                case .playPause:
                    playPauseTimer?.invalidate()
                    playPauseTimer = nil
                    if handledPlayPauseLongPress {
                        handledPlayPauseLongPress = false
                        continue
                    }
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            self.manager.presentQuickMenu.toggle()
                        }
                    }
                    continue
                case .menu:
                    backTimer?.invalidate()
                    backTimer = nil
                    if handledLongPress {
                        handledLongPress = false
                        continue
                    }
                    
                    if manager.presentQuickMenu {
                        withAnimation { manager.presentQuickMenu = false }
                        continue
                    }
                    if manager.presentMenu {
                        withAnimation { manager.presentMenu = false }
                        continue
                    }
                    
                    if manager.controlMode == .tvRemote {
                        manager.sendRemoteBackKey()
                        continue
                    }
                    
                    if let tab = manager.activeTab, tab.canGoBack {
                        tab.goBack()
                        continue
                    }
                    
                    unhandledPresses.insert(press)
                    continue
                default:
                    break
                }
            }
            unhandledPresses.insert(press)
        }
        if !unhandledPresses.isEmpty {
            super.pressesEnded(unhandledPresses, with: event)
        }
    }
    
    private func mapUIKey(_ key: UIKey) -> (key: String, code: String, keyCode: Int) {
        switch key.keyCode {
        case .keyboardReturnOrEnter:
            return ("Enter", "Enter", 13)
        case .keyboardDeleteOrBackspace:
            return ("Backspace", "Backspace", 8)
        case .keyboardDeleteForward:
            return ("Delete", "Delete", 46)
        case .keyboardTab:
            return ("Tab", "Tab", 9)
        case .keyboardEscape:
            return ("Escape", "Escape", 27)
        case .keyboardSpacebar:
            return (" ", "Space", 32)
        case .keyboardUpArrow:
            return ("ArrowUp", "ArrowUp", 38)
        case .keyboardDownArrow:
            return ("ArrowDown", "ArrowDown", 40)
        case .keyboardLeftArrow:
            return ("ArrowLeft", "ArrowLeft", 37)
        case .keyboardRightArrow:
            return ("ArrowRight", "ArrowRight", 39)
        case .keyboardPageUp:
            return ("PageUp", "PageUp", 33)
        case .keyboardPageDown:
            return ("PageDown", "PageDown", 34)
        case .keyboardHome:
            return ("Home", "Home", 36)
        case .keyboardEnd:
            return ("End", "End", 35)
        default:
            let char = key.characters
            let raw = key.charactersIgnoringModifiers.uppercased()
            let code: String
            let keyCode: Int
            if let scalar = raw.unicodeScalars.first, scalar.value >= 65 && scalar.value <= 90 {
                code = "Key" + raw
                keyCode = Int(scalar.value)
            } else if let scalar = raw.unicodeScalars.first, scalar.value >= 48 && scalar.value <= 57 {
                code = "Digit" + raw
                keyCode = Int(scalar.value)
            } else {
                code = raw
                keyCode = Int(raw.unicodeScalars.first?.value ?? 0)
            }
            return (char.isEmpty ? raw : char, code, keyCode)
        }
    }
    
    private func handleHardwareKeyPress(_ key: UIKey, isKeyUp: Bool) -> Bool {
        let mods = key.modifierFlags
        let isCmd = mods.contains(.command)
        
        if isKeyUp {
            let mapped = mapUIKey(key)
            manager.activeTab?.handlePhysicalKey(
                key: mapped.key,
                code: mapped.code,
                keyCode: mapped.keyCode,
                isShift: mods.contains(.shift),
                isCtrl: mods.contains(.control),
                isAlt: mods.contains(.alternate),
                isMeta: isCmd,
                isKeyUp: true
            )
            return true
        }
        
        if isCmd {
            let raw = key.charactersIgnoringModifiers.lowercased()
            switch raw {
            case "r":
                manager.reload()
                return true
            case "l":
                manager.presentSearchSheet = true
                return true
            case "t":
                manager.addNewTab()
                return true
            case "w":
                if let tabId = manager.activeTabId {
                    manager.closeTab(id: tabId)
                }
                return true
            case "[":
                if let tab = manager.activeTab, tab.canGoBack {
                    tab.goBack()
                }
                return true
            case "]":
                if let tab = manager.activeTab, tab.canGoForward {
                    tab.goForward()
                }
                return true
            case "+", "=":
                manager.zoomIn()
                return true
            case "-":
                manager.zoomOut()
                return true
            case "0":
                manager.resetZoom()
                return true
            case "d":
                manager.addActiveTabToFavorites()
                return true
            default:
                break
            }
            
            if key.keyCode == .keyboardUpArrow {
                manager.activeTab?.scrollToTop()
                return true
            } else if key.keyCode == .keyboardDownArrow {
                manager.activeTab?.scrollToBottom()
                return true
            } else if key.keyCode == .keyboardLeftArrow {
                if let tab = manager.activeTab, tab.canGoBack {
                    tab.goBack()
                }
                return true
            } else if key.keyCode == .keyboardRightArrow {
                if let tab = manager.activeTab, tab.canGoForward {
                    tab.goForward()
                }
                return true
            }
        }
        
        let mapped = mapUIKey(key)
        manager.activeTab?.handlePhysicalKey(
            key: mapped.key,
            code: mapped.code,
            keyCode: mapped.keyCode,
            isShift: mods.contains(.shift),
            isCtrl: mods.contains(.control),
            isAlt: mods.contains(.alternate),
            isMeta: isCmd,
            isKeyUp: false
        )
        return true
    }
    
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        stopDirectionalMovement()
        backTimer?.invalidate()
        backTimer = nil
        playPauseTimer?.invalidate()
        playPauseTimer = nil
        super.pressesCancelled(presses, with: event)
    }
    
    private func startDirectionalMovement(dx: CGFloat, dy: CGFloat) {
        guard isWebInteractionActive else { return }
        stopDirectionalMovement()
        activeDirection = (dx, dy)
        stepDirectionalMovement()
        
        let interval: TimeInterval
        switch manager.controlMode {
        case .cursor:
            interval = 0.03
        case .scroll:
            interval = 0.06
        case .tvRemote:
            interval = 0.18
        }
        
        directionalTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.stepDirectionalMovement()
        }
    }
    
    private func stepDirectionalMovement() {
        guard let dir = activeDirection else { return }
        
        switch manager.controlMode {
        case .cursor:
            let step: CGFloat = 20.0 * (manager.touchpadSensitivity.cursorMultiplier / 1.5)
            manager.moveCursor(by: CGSize(width: dir.dx * step, height: dir.dy * step))
        case .scroll:
            let step: CGFloat = 160.0 * (manager.touchpadSensitivity.scrollMultiplier / 2.0)
            manager.scrollActiveTab(dx: dir.dx * step, dy: dir.dy * step)
        case .tvRemote:
            if dir.dy < 0 {
                manager.sendRemoteKey(key: "ArrowUp", code: "ArrowUp", keyCode: 38)
            } else if dir.dy > 0 {
                manager.sendRemoteKey(key: "ArrowDown", code: "ArrowDown", keyCode: 40)
            } else if dir.dx < 0 {
                manager.sendRemoteKey(key: "ArrowLeft", code: "ArrowLeft", keyCode: 37)
            } else if dir.dx > 0 {
                manager.sendRemoteKey(key: "ArrowRight", code: "ArrowRight", keyCode: 39)
            }
        }
    }
    
    private func stopDirectionalMovement() {
        directionalTimer?.invalidate()
        directionalTimer = nil
        activeDirection = nil
    }
}
