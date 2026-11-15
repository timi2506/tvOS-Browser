//
//  TVWebViewRepresentable.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import UIKit
import SwiftUI

struct TVWebViewRepresentable: UIViewControllerRepresentable {
    @ObservedObject var manager: WebViewManager
    
    init(manager: WebViewManager) {
        self.manager = manager
    }
    
    func makeUIViewController(context: Context) -> TVWebViewController {
        let controller = TVWebViewController(manager: manager)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: TVWebViewController, context: Context) {
        uiViewController.updateActiveTab()
        uiViewController.updatePanGestureState()
    }
}

final class TVWebViewController: UIViewController, UIGestureRecognizerDelegate {
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
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
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
        becomeFirstResponder()
        manager.updateViewSize(view.bounds.size)
    }
    
    func updateActiveTab() {
        guard let tab = manager.activeTab else { return }
        if currentWebView !== tab.webView {
            currentWebView?.removeFromSuperview()
            currentWebView = tab.webView
            
            tab.webView.frame = view.bounds
            tab.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(tab.webView)
        }
    }
    
    func updatePanGestureState() {
        if manager.presentMenu {
            stopDirectionalMovement()
        }
        panGesture?.isEnabled = !manager.presentMenu
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGesture && manager.presentMenu {
            return false
        }
        return true
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !manager.presentMenu else { return }
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
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .upArrow:
                startDirectionalMovement(dx: 0, dy: -1)
                return
            case .downArrow:
                startDirectionalMovement(dx: 0, dy: 1)
                return
            case .leftArrow:
                startDirectionalMovement(dx: -1, dy: 0)
                return
            case .rightArrow:
                startDirectionalMovement(dx: 1, dy: 0)
                return
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
                return
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
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }
    
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .upArrow, .downArrow, .leftArrow, .rightArrow:
                stopDirectionalMovement()
                return
            case .select:
                switch manager.controlMode {
                case .cursor:
                    manager.tapAtCursor()
                case .scroll:
                    break
                case .tvRemote:
                    manager.sendRemoteKey(key: "Enter", code: "Enter", keyCode: 13)
                }
                return
            case .playPause:
                playPauseTimer?.invalidate()
                playPauseTimer = nil
                if handledPlayPauseLongPress {
                    handledPlayPauseLongPress = false
                    return
                }
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.manager.presentQuickMenu.toggle()
                    }
                }
                return
            case .menu:
                backTimer?.invalidate()
                backTimer = nil
                if handledLongPress {
                    handledLongPress = false
                    return
                }
                
                if manager.presentQuickMenu {
                    withAnimation { manager.presentQuickMenu = false }
                    return
                }
                if manager.presentMenu {
                    withAnimation { manager.presentMenu = false }
                    return
                }
                
                if manager.controlMode == .tvRemote {
                    manager.sendRemoteBackKey()
                    return
                }
                
                if let tab = manager.activeTab, tab.canGoBack {
                    tab.goBack()
                    return
                }
                
                super.pressesEnded(presses, with: event)
                return
            default:
                break
            }
        }
        super.pressesEnded(presses, with: event)
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
