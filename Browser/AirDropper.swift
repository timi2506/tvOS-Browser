//
//  AirDropper.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import UIKit
import ObjectiveC

final class AirDropper {
    static let shared = AirDropper()
    
    private var isPatched = false
    private var discoveryController: AnyObject?
    
    private init() {}
    
    func airDropFile(_ filePath: String) {
        if openViaBreezy(filePath) {
            return
        }
        openViaInAppSharing(filePath)
    }
    
    private func patchAirDropAvailabilityIfNeeded() {
        guard !isPatched else { return }
        isPatched = true
        
        Bundle(path: "/System/Library/PrivateFrameworks/Sharing.framework")?.load()
        Bundle(path: "/System/Library/PrivateFrameworks/SharingUI.framework")?.load()
        
        if let actClass = NSClassFromString("SFAirDropActivityViewController") {
            let sel = NSSelectorFromString("isAirDropAvailable")
            if let origMethod = class_getClassMethod(actClass, sel) {
                let swizzledBlock: @convention(block) (AnyObject) -> Bool = { _ in true }
                let swizzledImp = imp_implementationWithBlock(swizzledBlock)
                method_setImplementation(origMethod, swizzledImp)
            }
        }
        
        if let discClass = NSClassFromString("SFAirDropDiscoveryController") {
            let sel = NSSelectorFromString("isNearbySharingSupported")
            if let origMethod = class_getInstanceMethod(discClass, sel) {
                let swizzledBlock: @convention(block) (AnyObject) -> Bool = { _ in true }
                let swizzledImp = imp_implementationWithBlock(swizzledBlock)
                method_setImplementation(origMethod, swizzledImp)
            }
        }
    }
    
    private func openViaBreezy(_ filePath: String) -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.timi2506.funTV"
        let encodedPath = filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath
        guard let url = URL(string: "airdropper://\(encodedPath)?sender=\(bundleID)") else { return false }
        
        Bundle(path: "/System/Library/Frameworks/MobileCoreServices.framework")?.load()
        if let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type {
            let defaultSel = NSSelectorFromString("defaultWorkspace")
            if workspaceClass.responds(to: defaultSel),
               let workspace = workspaceClass.perform(defaultSel)?.takeUnretainedValue() as? NSObject {
                let openSel = NSSelectorFromString("openURL:")
                if workspace.responds(to: openSel) {
                    typealias OpenFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
                    let method = workspace.method(for: openSel)
                    let callable = unsafeBitCast(method, to: OpenFunc.self)
                    if callable(workspace, openSel, url as AnyObject) {
                        return true
                    }
                }
            }
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return true
        }
        
        let legacySel = NSSelectorFromString("openURL:")
        if UIApplication.shared.responds(to: legacySel) {
            typealias LegacyOpenFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
            let m = UIApplication.shared.method(for: legacySel)
            let f = unsafeBitCast(m, to: LegacyOpenFunc.self)
            if f(UIApplication.shared, legacySel, url as AnyObject) {
                return true
            }
        }
        
        return false
    }
    
    private func openViaInAppSharing(_ filePath: String) {
        patchAirDropAvailabilityIfNeeded()
        ensureDiscoverableModeEveryone()
        
        guard let sharingClass = NSClassFromString("SFAirDropSharingViewControllerTV") as? NSObject.Type else {
            return
        }
        
        guard let root = rootViewController() else {
            return
        }
        
        let allocSel = NSSelectorFromString("alloc")
        let initSel = NSSelectorFromString("initWithSharingItems:")
        guard let allocObj = (sharingClass as AnyObject).perform(allocSel)?.takeUnretainedValue() else {
            return
        }
        
        let fileURL = URL(fileURLWithPath: filePath)
        typealias InitFunc = @convention(c) (AnyObject, Selector, NSArray) -> AnyObject?
        guard let method = allocObj.method(for: initSel) else {
            return
        }
        let callable = unsafeBitCast(method, to: InitFunc.self)
        guard let sharingView = callable(allocObj, initSel, [fileURL] as NSArray) as? UIViewController else {
            return
        }
        
        let setItemsSel = NSSelectorFromString("setItemsToShare:")
        if sharingView.responds(to: setItemsSel) {
            _ = (sharingView as AnyObject).perform(setItemsSel, with: [fileURL] as NSArray)
        }
        
        _ = sharingView.view
        
        let bundleID = Bundle.main.bundleIdentifier ?? "com.timi2506.funTV"
        if let actVC = (sharingView as AnyObject).value(forKey: "airDropActivityControllerViewController") as? UIViewController {
            _ = actVC.view
            let setUrlsSel = NSSelectorFromString("setUrlsBeingShared:")
            if actVC.responds(to: setUrlsSel) {
                _ = (actVC as AnyObject).perform(setUrlsSel, with: [fileURL] as NSArray)
            }
            if let browser = (actVC as AnyObject).value(forKey: "browser") as? NSObject {
                if browser.responds(to: setUrlsSel) {
                    _ = browser.perform(setUrlsSel, with: [fileURL] as NSArray)
                }
                let setBundleSel = NSSelectorFromString("setSendingAppBundleID:")
                if browser.responds(to: setBundleSel) {
                    _ = browser.perform(setBundleSel, with: bundleID as NSString)
                }
            }
        }
        
        let setHandlerSel = NSSelectorFromString("setCompletionHandler:")
        if sharingView.responds(to: setHandlerSel) {
            typealias HandlerBlock = @convention(block) (NSError?) -> Void
            let block: HandlerBlock = { [weak sharingView, weak root] error in
                DispatchQueue.main.async {
                    if let sv = sharingView, sv.presentingViewController != nil {
                        sv.dismiss(animated: true)
                    } else {
                        root?.dismiss(animated: true)
                    }
                }
            }
            typealias SetHandlerFunc = @convention(c) (AnyObject, Selector, AnyObject) -> Void
            let setMethod = sharingView.method(for: setHandlerSel)
            let setCallable = unsafeBitCast(setMethod, to: SetHandlerFunc.self)
            let blockObj = unsafeBitCast(block, to: AnyObject.self)
            setCallable(sharingView, setHandlerSel, blockObj)
        }
        
        root.present(sharingView, animated: true)
    }
    
    private func ensureDiscoverableModeEveryone() {
        if let discoveryClass = NSClassFromString("SFAirDropDiscoveryController") as? NSObject.Type {
            let controller = discoveryClass.init()
            self.discoveryController = controller
            let setModeSel = NSSelectorFromString("setDiscoverableMode:")
            if controller.responds(to: setModeSel) {
                typealias SetModeFunc = @convention(c) (AnyObject, Selector, Int) -> Void
                let m = controller.method(for: setModeSel)
                let callable = unsafeBitCast(m, to: SetModeFunc.self)
                callable(controller, setModeSel, 2)
            }
        }
    }
    
    private func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first,
              var top = window.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
