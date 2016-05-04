//
//  KeyListener.swift
//  QBlocker
//
//  Created by Stephen Radford on 02/05/2016.
//  Copyright © 2016 Cocoon Development Ltd. All rights reserved.
//

import Foundation

private func keyDownCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, ptr: UnsafeMutablePointer<Void>) -> Unmanaged<CGEvent>? {

    // If the command key wasn't used we can pass the event on
    let flags = CGEventGetFlags(event)
    guard (flags.rawValue & CGEventFlags.MaskCommand.rawValue) != 0 else {
        return Unmanaged<CGEvent>.passUnretained(event)
    }
    
    // If the q key wasn't clicked we can ignore the event too
    guard CGEventGetIntegerValueField(event, .KeyboardEventKeycode) == 12 else {
        return Unmanaged<CGEvent>.passUnretained(event)
    }
    
    guard let app = NSWorkspace.sharedWorkspace().menuBarOwningApplication else {
        return Unmanaged<CGEvent>.passUnretained(event)
    }

    guard app.ownsMenuBar else {
        return Unmanaged<CGEvent>.passUnretained(event)
    }
    
    guard KeyListener.cmdQActiveForApp(app) else {
        return nil
    }
    
    if KeyListener.sharedKeyListener.canQuit && KeyListener.sharedKeyListener.tries <= 4 {
        HUDAlert.sharedHUDAlert.showHUD()
    }
    
    KeyListener.sharedKeyListener.tries += 1
    if KeyListener.sharedKeyListener.tries > 4 && KeyListener.sharedKeyListener.canQuit {
        KeyListener.sharedKeyListener.tries = 0
        KeyListener.sharedKeyListener.canQuit = false
        HUDAlert.sharedHUDAlert.dismissHUD()
        return Unmanaged<CGEvent>.passUnretained(event)
    }
    
    return nil
}

private func keyUpCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, ptr: UnsafeMutablePointer<Void>) -> Unmanaged<CGEvent>? {
    
    // If the command key wasn't used we can pass the event on
    let flags = CGEventGetFlags(event)
    guard (flags.rawValue & CGEventFlags.MaskCommand.rawValue) != 0 else {
        return Unmanaged<CGEvent>.passUnretained(event)
    }
    
    // If the q key wasn't clicked we can ignore the event too
    guard CGEventGetIntegerValueField(event, .KeyboardEventKeycode) == 12 else {
        return Unmanaged<CGEvent>.passUnretained(event)
    }
    
    if KeyListener.sharedKeyListener.tries <= 4 {
        delay(1) {
            HUDAlert.sharedHUDAlert.dismissHUD()
        }
        KeyListener.sharedKeyListener.logAccidentalQuit()
    } else {
        HUDAlert.sharedHUDAlert.dismissHUD()
    }
    
    KeyListener.sharedKeyListener.tries = 0
    KeyListener.sharedKeyListener.canQuit = true
    
    return Unmanaged<CGEvent>.passUnretained(event)
}

func delay(delay:Double, closure:()->()) {
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            Int64(delay * Double(NSEC_PER_SEC))
        ),
        dispatch_get_main_queue(), closure)
}


class KeyListener {
    
    /// Shared instance of the key listener
    static let sharedKeyListener = KeyListener()
    
    /// The CGEvent for key down
    var keyDown: CFMachPort?
    
    /// The run loop for key down
    var keyDownRunLoopSource: CFRunLoopSource?
    
    /// The CG event for key up
    var keyUp: CFMachPort?
    
    /// The run loop for key up
    var keyUpRunLoopSource: CFRunLoopSource?
    
    /// The number of "tries" that CMD + Q have been hit.
    /// This is set when a user holds down the CMD + Q shortcut.
    var tries = 0
    
    /// Can quit is marked as false as soon as an app has just quit.
    /// If this is not checked then subsequent apps will continue to quit behind it.
    var canQuit = true
    
    /// The number of accidental quits that have been saved by QBlocker
    var accidentalQuits: Int {
        return NSUserDefaults.standardUserDefaults().integerForKey("accidentalQuits")
    }
    
    /**
     Start the keyDown and keyUp listeners.
     
     - throws: `KeyListenerError`
     */
    func start() throws {
        
        keyDown = CGEventTapCreate(CGEventTapLocation.CGHIDEventTap,
                                   CGEventTapPlacement.HeadInsertEventTap,
                                   CGEventTapOptions.Default,
                                   CGEventMask((1 << CGEventType.KeyDown.rawValue)),
                                   keyDownCallback,
                                   UnsafeMutablePointer<Void>(Unmanaged.passUnretained(self).toOpaque()))
        
        keyUp = CGEventTapCreate(CGEventTapLocation.CGHIDEventTap,
                                CGEventTapPlacement.HeadInsertEventTap,
                                CGEventTapOptions.Default,
                                CGEventMask((1 << CGEventType.KeyUp.rawValue)),
                                keyUpCallback,
                                UnsafeMutablePointer<Void>(Unmanaged.passUnretained(self).toOpaque()))
        
        guard keyDown != nil else {
            throw KeyListenerError.AccessibilityPermissionDenied
        }

        keyDownRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyDown, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keyDownRunLoopSource, kCFRunLoopCommonModes)
        
        keyUpRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyUp, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keyUpRunLoopSource, kCFRunLoopCommonModes)
        
    }
    
    /**
     Store accidental quits in the user defaults
     */
    func logAccidentalQuit() {
        let quits = accidentalQuits + 1
        NSUserDefaults.standardUserDefaults().setInteger(quits, forKey: "accidentalQuits")
    }
    
    /**
     Checks if CMD+Q is in the menu bar for the current application
     
     - parameter app: The Current App
     */
    class func cmdQActiveForApp(app: NSRunningApplication) -> Bool {
        
        let app = AXUIElementCreateApplication(app.processIdentifier).takeRetainedValue()
        var menuBar: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute, &menuBar)
        
        // If we can't get the menubar then exit
        guard menuBar != nil else {
            return false
        }
        
        // Get the toplevel menu items
        let menu = menuBar as! AXUIElement
        var children: AnyObject?
        AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute, &children)

        guard let items = children as? NSArray where items.count > 0 else {
            return false
        }
        
        // Get the submenus of the first item
        var subMenus: AnyObject?
        let title = items[1] as! AXUIElement // subscript 0 is the apple menu
        AXUIElementCopyAttributeValue(title, kAXChildrenAttribute, &subMenus)
        
        guard let menus = subMenus as? NSArray where menus.count > 0 else {
            return false
        }
        
        // Get the entries of the submenu
        var entries: AnyObject?
        let submenu = menus[0] as! AXUIElement
        AXUIElementCopyAttributeValue(submenu, kAXChildrenAttribute, &entries)
        
        guard let menuItems = entries as? NSArray where menuItems.count > 0 else {
            return false
        }
        
        // Loop through the menu items and check if CMD + Q is the shortcut
        for item in menuItems {
            var cmdChar: AnyObject?
            AXUIElementCopyAttributeValue(item as! AXUIElement, kAXMenuItemCmdCharAttribute, &cmdChar)
            if let char = cmdChar as? String where char == "Q" {
                return true
            }
        }
        
        return false
    }
    
}