//
//  NativeInputManager.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import Foundation
import UIKit
import GameController
import Combine
import SwiftUI

private typealias IOHIDEventType = UInt32
private typealias IOHIDEventRef = UnsafeMutableRawPointer
private typealias IOHIDEventGetTypeFn = @convention(c) (IOHIDEventRef) -> IOHIDEventType
private typealias IOHIDEventGetFloatValueFn = @convention(c) (IOHIDEventRef, UInt32) -> Double
private typealias IOHIDEventGetIntegerValueFn = @convention(c) (IOHIDEventRef, UInt32) -> Int
private typealias IOHIDEventGetChildrenFn = @convention(c) (IOHIDEventRef) -> CFArray?
private typealias HIDBlock = @convention(block) (IOHIDEventRef) -> Void
private typealias SetHIDObserverFn = @convention(c) (AnyObject, Selector, @escaping HIDBlock, DispatchQueue) -> Void

private let kIOHIDEventTypeButton: UInt32 = 2
private let kIOHIDEventTypeKeyboard: UInt32 = 3
private let kIOHIDEventTypeScroll: UInt32 = 6
private let kIOHIDEventTypePointer: UInt32 = 17

private let kIOHIDEventFieldButtonMask: UInt32 = (2 << 16) | 0
private let kIOHIDEventFieldButtonNumber: UInt32 = (2 << 16) | 1
private let kIOHIDEventFieldButtonState: UInt32 = (2 << 16) | 4
private let kIOHIDEventFieldScrollX: UInt32 = (6 << 16) | 0
private let kIOHIDEventFieldScrollY: UInt32 = (6 << 16) | 1
private let kIOHIDEventFieldPointerX: UInt32 = (17 << 16) | 0
private let kIOHIDEventFieldPointerY: UInt32 = (17 << 16) | 1
private let kIOHIDEventFieldPointerButtonMask: UInt32 = (17 << 16) | 3

final class NativeInputManager: ObservableObject {
    static let shared = NativeInputManager()
    
    @Published private(set) var isMouseConnected = false
    @Published private(set) var isKeyboardConnected = false
    
    private var hasDetectedMouseInput = false
    private var hasDetectedKeyboardInput = false
    private var configuredMice: [ObjectIdentifier: GCMouse] = [:]
    private var checkTimer: Timer?
    
    private var iohidGetType: IOHIDEventGetTypeFn?
    private var iohidGetFloat: IOHIDEventGetFloatValueFn?
    private var iohidGetInt: IOHIDEventGetIntegerValueFn?
    private var iohidGetChildren: IOHIDEventGetChildrenFn?
    private var isHIDObserverConfigured = false
    private var lastButtonMask: Int = 0
    
    var hasHardwareKeyboard: Bool {
        return isKeyboardConnected || GCKeyboard.coalesced != nil
    }
    
    var hardwareStatusDescription: String {
        var items: [String] = []
        if isMouseConnected {
            #if targetEnvironment(simulator)
            items.append("Mouse connected (Simulator)")
            #else
            items.append("Mouse connected")
            #endif
        }
        if hasHardwareKeyboard {
            #if targetEnvironment(simulator)
            items.append("Keyboard connected (Simulator)")
            #else
            items.append("Keyboard connected")
            #endif
        }
        if items.isEmpty {
            return "No keyboard or mouse connected"
        }
        return items.joined(separator: ", ")
    }
    
    private var isStarted = false
    
    private init() {
        loadHIDFunctions()
        setupObservers()
        GCController.startWirelessControllerDiscovery()
        checkForConnectedDevices()
        startPeriodicCheck()
        setupHIDObserver()
    }
    
    deinit {
        checkTimer?.invalidate()
    }
    
    func start(with manager: WebViewManager) {
        if !isStarted {
            isStarted = true
            setupHIDObserver()
            checkForConnectedDevices()
        }
    }
    
    func markMouseConnected() {
        if !hasDetectedMouseInput {
            hasDetectedMouseInput = true
        }
        if !isMouseConnected {
            DispatchQueue.main.async {
                self.isMouseConnected = true
            }
        }
    }
    
    func markKeyboardConnected() {
        if !hasDetectedKeyboardInput {
            hasDetectedKeyboardInput = true
        }
        if !isKeyboardConnected {
            DispatchQueue.main.async {
                self.isKeyboardConnected = true
            }
        }
    }
    
    private func loadHIDFunctions() {
        let handle = dlopen(nil, RTLD_NOW)
        if let sym = dlsym(handle, "IOHIDEventGetType") {
            iohidGetType = unsafeBitCast(sym, to: IOHIDEventGetTypeFn.self)
        }
        if let sym = dlsym(handle, "IOHIDEventGetFloatValue") {
            iohidGetFloat = unsafeBitCast(sym, to: IOHIDEventGetFloatValueFn.self)
        }
        if let sym = dlsym(handle, "IOHIDEventGetIntegerValue") {
            iohidGetInt = unsafeBitCast(sym, to: IOHIDEventGetIntegerValueFn.self)
        }
        if let sym = dlsym(handle, "IOHIDEventGetChildren") {
            iohidGetChildren = unsafeBitCast(sym, to: IOHIDEventGetChildrenFn.self)
        }
    }
    
    private func setupHIDObserver() {
        guard !isHIDObserverConfigured else { return }
        guard iohidGetType != nil else { return }
        let app = UIApplication.shared
        let sel = NSSelectorFromString("_setHIDEventObserver:onQueue:")
        guard app.responds(to: sel),
              let methodImp = class_getMethodImplementation(UIApplication.self, sel) else { return }
        let setObserver = unsafeBitCast(methodImp, to: SetHIDObserverFn.self)
        let block: HIDBlock = { [weak self] event in
            self?.handleRawHIDEvent(event)
        }
        setObserver(app, sel, block, DispatchQueue.main)
        isHIDObserverConfigured = true
    }
    
    private func handleRawHIDEvent(_ event: IOHIDEventRef) {
        guard let getType = iohidGetType else { return }
        let type = getType(event)
        processSingleHIDEvent(event, type: type)
        if let getChildren = iohidGetChildren,
           let children = getChildren(event) {
            let count = CFArrayGetCount(children)
            for i in 0..<count {
                if let child = CFArrayGetValueAtIndex(children, i) {
                    handleRawHIDEvent(UnsafeMutableRawPointer(mutating: child))
                }
            }
        }
    }
    
    private func processSingleHIDEvent(_ event: IOHIDEventRef, type: UInt32) {
        if type == kIOHIDEventTypePointer {
            guard let getFloat = iohidGetFloat, let getInt = iohidGetInt else { return }
            let deltaX = getFloat(event, kIOHIDEventFieldPointerX)
            let deltaY = getFloat(event, kIOHIDEventFieldPointerY)
            let buttonMask = getInt(event, kIOHIDEventFieldPointerButtonMask)
            
            if abs(deltaX) > 0.0001 || abs(deltaY) > 0.0001 {
                markMouseConnected()
                let mgr = WebViewManager.shared
                if mgr.presentMenu {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        mgr.presentMenu = false
                    }
                }
                if mgr.controlMode != .cursor {
                    mgr.controlMode = .cursor
                }
                let sens = mgr.touchpadSensitivity.cursorMultiplier
                let speed: CGFloat = 2.0 * sens
                let dx = CGFloat(deltaX) * speed
                let dy = CGFloat(deltaY) * speed
                mgr.moveCursor(by: CGSize(width: dx, height: dy))
                let isDragging = (buttonMask & 1) != 0 || (lastButtonMask & 1) != 0
                mgr.activeTab?.mouseMoved(to: mgr.cursorPosition, buttons: isDragging ? 1 : 0)
            }
            
            handleButtonMask(buttonMask)
        } else if type == kIOHIDEventTypeScroll {
            guard let getFloat = iohidGetFloat else { return }
            let scrollX = getFloat(event, kIOHIDEventFieldScrollX)
            let scrollY = getFloat(event, kIOHIDEventFieldScrollY)
            if abs(scrollX) > 0.0001 || abs(scrollY) > 0.0001 {
                markMouseConnected()
                let mgr = WebViewManager.shared
                let scrollSpeed: CGFloat = 40.0
                let dx = CGFloat(-scrollX) * scrollSpeed
                let dy = CGFloat(-scrollY) * scrollSpeed
                mgr.scrollActiveTab(dx: dx, dy: dy)
            }
        } else if type == kIOHIDEventTypeButton {
            guard let getInt = iohidGetInt else { return }
            var buttonMask = getInt(event, kIOHIDEventFieldButtonMask)
            if buttonMask == 0 {
                let number = getInt(event, kIOHIDEventFieldButtonNumber)
                let state = getInt(event, kIOHIDEventFieldButtonState)
                if number > 0 && number <= 32 {
                    let bit: Int = 1 << (number - 1)
                    if state != 0 {
                        buttonMask = lastButtonMask | bit
                    } else {
                        buttonMask = lastButtonMask & ~bit
                    }
                }
            }
            handleButtonMask(buttonMask)
        } else if type == kIOHIDEventTypeKeyboard {
            markKeyboardConnected()
        }
    }
    
    private func handleButtonMask(_ buttonMask: Int) {
        guard buttonMask != lastButtonMask else { return }
        markMouseConnected()
        let mgr = WebViewManager.shared
        let changed = buttonMask ^ lastButtonMask
        
        if (changed & 1) != 0 {
            let pressed = (buttonMask & 1) != 0
            if pressed {
                mgr.activeTab?.mouseDown(at: mgr.cursorPosition, button: 0)
            } else {
                mgr.activeTab?.mouseUp(at: mgr.cursorPosition, button: 0, isHardwareMouse: true)
            }
        }
        
        if (changed & 2) != 0 {
            let pressed = (buttonMask & 2) != 0
            if pressed {
                mgr.activeTab?.contextMenu(at: mgr.cursorPosition)
            }
        }
        
        if (changed & 4) != 0 {
            let pressed = (buttonMask & 4) != 0
            if pressed {
                mgr.activeTab?.middleClick(at: mgr.cursorPosition)
            }
        }
        
        lastButtonMask = buttonMask
    }
    
    private func startPeriodicCheck() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForConnectedDevices()
        }
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            if let mouse = note.object as? GCMouse {
                self?.configureMouse(mouse)
            }
            self?.updateConnectedState()
        }
        
        NotificationCenter.default.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { [weak self] note in
            if let mouse = note.object as? GCMouse {
                self?.configuredMice.removeValue(forKey: ObjectIdentifier(mouse))
            }
            self?.updateConnectedState()
        }
        
        NotificationCenter.default.addObserver(forName: .GCMouseDidBecomeCurrent, object: nil, queue: .main) { [weak self] note in
            if let mouse = note.object as? GCMouse {
                self?.configureMouse(mouse)
            } else if let currentMouse = GCMouse.current {
                self?.configureMouse(currentMouse)
            }
            self?.updateConnectedState()
        }
        
        NotificationCenter.default.addObserver(forName: .GCMouseDidStopBeingCurrent, object: nil, queue: .main) { [weak self] _ in
            self?.updateConnectedState()
        }
        
        NotificationCenter.default.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            self?.updateConnectedState()
        }
        
        NotificationCenter.default.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.updateConnectedState()
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setupHIDObserver()
            self?.checkForConnectedDevices()
        }
    }
    
    func checkForConnectedDevices() {
        let allMice = GCMouse.mice()
        for mouse in allMice {
            configureMouse(mouse)
        }
        if let currentMouse = GCMouse.current {
            configureMouse(currentMouse)
        }
        updateConnectedState()
    }
    
    private func updateConnectedState() {
        let hasMice = !GCMouse.mice().isEmpty || GCMouse.current != nil || hasDetectedMouseInput
        #if targetEnvironment(simulator)
        isMouseConnected = true
        #else
        isMouseConnected = hasMice
        #endif
        
        let hasKeyboard = GCKeyboard.coalesced != nil || hasDetectedKeyboardInput
        #if targetEnvironment(simulator)
        isKeyboardConnected = true
        #else
        isKeyboardConnected = hasKeyboard
        #endif
    }
    
    private func configureMouse(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }
        mouse.handlerQueue = .main
        configuredMice[ObjectIdentifier(mouse)] = mouse
        
        input.mouseMovedHandler = { [weak self] (_, deltaX, deltaY) in
            guard let self = self else { return }
            self.markMouseConnected()
            let mgr = WebViewManager.shared
            if mgr.presentMenu {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    mgr.presentMenu = false
                }
            }
            if mgr.controlMode != .cursor {
                mgr.controlMode = .cursor
            }
            let sens = mgr.touchpadSensitivity.cursorMultiplier
            let speed: CGFloat = 2.0 * sens
            let dx = CGFloat(deltaX) * speed
            let dy = CGFloat(-deltaY) * speed
            mgr.moveCursor(by: CGSize(width: dx, height: dy))
            let isDragging = input.leftButton.isPressed
            mgr.activeTab?.mouseMoved(to: mgr.cursorPosition, buttons: isDragging ? 1 : 0)
        }
        
        input.leftButton.pressedChangedHandler = { [weak self] (_, _, pressed) in
            guard let self = self else { return }
            self.markMouseConnected()
            let mgr = WebViewManager.shared
            if pressed {
                mgr.activeTab?.mouseDown(at: mgr.cursorPosition, button: 0)
            } else {
                mgr.activeTab?.mouseUp(at: mgr.cursorPosition, button: 0, isHardwareMouse: true)
            }
        }
        
        input.rightButton?.pressedChangedHandler = { [weak self] (_, _, pressed) in
            guard let self = self else { return }
            self.markMouseConnected()
            let mgr = WebViewManager.shared
            if pressed {
                mgr.activeTab?.contextMenu(at: mgr.cursorPosition)
            }
        }
        
        input.middleButton?.pressedChangedHandler = { [weak self] (_, _, pressed) in
            guard let self = self else { return }
            self.markMouseConnected()
            let mgr = WebViewManager.shared
            if pressed {
                mgr.activeTab?.middleClick(at: mgr.cursorPosition)
            }
        }
        
        input.scroll.valueChangedHandler = { [weak self] (_, x, y) in
            guard let self = self else { return }
            self.markMouseConnected()
            let mgr = WebViewManager.shared
            let scrollSpeed: CGFloat = 40.0
            let dx = CGFloat(-x) * scrollSpeed
            let dy = CGFloat(-y) * scrollSpeed
            mgr.scrollActiveTab(dx: dx, dy: dy)
        }
    }
}
