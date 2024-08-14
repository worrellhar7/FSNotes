//
//  AppDelegate.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 7/20/17.
//  Copyright © 2017 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa
import FSNotesCore_macOS

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var prefsWindowController: PrefsWindowController?
    var aboutWindowController: AboutWindowController?
    var statusItem: NSStatusItem?

    public var urls: [URL]? = nil
    public var url: URL? = nil
    public var newName: String? = nil
    public var newContent: String? = nil

    public static var mainWindowController: MainWindowController?
    public static var noteWindows = [NSWindowController]()
    
    public static var appTitle: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return name ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
    }
    
    public static var gitProgress: GitProgress?

    func applicationWillFinishLaunching(_ notification: Notification) {
        checkStorageChanges()
        loadDockIcon()
        
        if UserDefaultsManagement.showInMenuBar {
            constructMenu()
        }
        
        if !UserDefaultsManagement.showDockIcon {
            let transformState = ProcessApplicationTransformState(kProcessTransformToUIElementApplication)
            var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
            TransformProcessType(&psn, transformState)

            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Ensure the font panel is closed when the app starts, in case it was
        // left open when the app quit.
        NSFontManager.shared.fontPanel(false)?.orderOut(self)

        applyAppearance()

        #if CLOUD_RELATED_BLOCK
        if let iCloudDocumentsURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").standardized {
            
            if (!FileManager.default.fileExists(atPath: iCloudDocumentsURL.path, isDirectory: nil)) {
                do {
                    try FileManager.default.createDirectory(at: iCloudDocumentsURL, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    print("Home directory creation: \(error)")
                }
            }
        }
        #endif

        if UserDefaultsManagement.storagePath == nil {
            self.requestStorageDirectory()
            return
        }

        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        
        guard let mainWC = storyboard.instantiateController(withIdentifier: "MainWindowController") as? MainWindowController else {
            fatalError("Error getting main window controller")
        }
        
        AppDelegate.mainWindowController = mainWC
        mainWC.window?.makeKeyAndOrderFront(nil)
    }
        
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if (!flag) {
            AppDelegate.mainWindowController?.makeNew()
        }
                
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaultsManagement.crashedLastTime = false
        
        AppDelegate.saveWindowsState()
        
        Storage.shared().saveAPIIds()
        Storage.shared().saveUploadPaths()
        
        let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")
        try? FileManager.default.removeItem(at: webkitPreview)

        let printDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Print")
        try? FileManager.default.removeItem(at: printDir)

        let encryption = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Encryption")
        try? FileManager.default.removeItem(at: encryption)

        var temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        temporary.appendPathComponent("ThumbnailsBig")
        try? FileManager.default.removeItem(at: temporary)

        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        guard let mainWC = storyboard.instantiateController(withIdentifier: "MainWindowController") as? MainWindowController else {
            return
        }

        if let x = mainWC.window?.frame.origin.x, let y = mainWC.window?.frame.origin.y {
            UserDefaultsManagement.lastScreenX = Int(x)
            UserDefaultsManagement.lastScreenY = Int(y)
        }
        
        Storage.shared().saveProjectsCache()
        
        print("Termination end, crash status: \(UserDefaultsManagement.crashedLastTime)")
    }
    
    private static func saveWindowsState() {
        var result = [[String: Any]]()
                
        let noteWindows = self.noteWindows.sorted(by: { $0.window!.orderedIndex > $1.window!.orderedIndex })
        for windowController in noteWindows {
            if let frame = windowController.window?.frame,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: frame, requiringSecureCoding: true),
               let controller = windowController.contentViewController as? NoteViewController,
                   let note = controller.editor.note {


                let key = windowController.window?.isKeyWindow == true

                result.append(["frame": data, "preview": controller.editor.isPreviewEnabled(), "url": note.url, "main": false, "key": key])
            }
        }
        
        // Main frame
        if let vc = ViewController.shared(), let note = vc.editor?.note, let mainFrame = vc.view.window?.frame,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: mainFrame, requiringSecureCoding: true) {

            let key = vc.view.window?.isKeyWindow == true
            
            result.append(["frame": data, "preview": vc.editor.isPreviewEnabled(), "url": note.url, "main": true, "key": key])
        }
    
        let projectsData = try? NSKeyedArchiver.archivedData(withRootObject: result, requiringSecureCoding: true)
        if let documentDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? projectsData?.write(to: documentDir.appendingPathComponent("editors.settings"))
        }
    }
    
    private func applyAppearance() {
        if UserDefaultsManagement.appearanceType != .Custom {
            if UserDefaultsManagement.appearanceType == .Dark {
                NSApp.appearance = NSAppearance.init(named: NSAppearance.Name.darkAqua)
                UserDataService.instance.isDark = true
            }

            if UserDefaultsManagement.appearanceType == .Light {
                NSApp.appearance = NSAppearance.init(named: NSAppearance.Name.aqua)
                UserDataService.instance.isDark = false
            }

            if UserDefaultsManagement.appearanceType == .System, NSAppearance.current.isDark {
                UserDataService.instance.isDark = true
            }
        } else {
            NSApp.appearance = NSAppearance.init(named: NSAppearance.Name.aqua)
        }
    }
    
    private func restartApp() {
        guard let resourcePath = Bundle.main.resourcePath else { return }
        
        let url = URL(fileURLWithPath: resourcePath)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        
        exit(0)
    }
    
    private func requestStorageDirectory() {
        var directoryURL: URL? = nil
        if let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            directoryURL = URL(fileURLWithPath: path)
        }
        
        let panel = NSOpenPanel()
        panel.directoryURL = directoryURL
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Please select default storage directory"
        panel.begin { (result) -> Void in
            if result == .OK {
                guard let url = panel.url else {
                    return
                }
                
                let bookmarks = SandboxBookmark.sharedInstance()
                bookmarks.save(url: url)

                UserDefaultsManagement.storageType = .custom
                UserDefaultsManagement.customStoragePath = url.path
                
                self.restartApp()
            } else {
                exit(EXIT_SUCCESS)
            }
        }
    }
    
    func constructMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button, let image = NSImage(named: "menuBar") {
            image.size.width = 20
            image.size.height = 20
            button.image = image
        }

        statusItem?.button?.action = #selector(AppDelegate.clickStatusBarItem(sender:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    public func attachMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: NSLocalizedString("New", comment: ""), action: #selector(AppDelegate.new(_:)), keyEquivalent: "n"))

        let newWindow = NSMenuItem(title: NSLocalizedString("New Window", comment: ""), action: #selector(AppDelegate.createInNewWindow(_:)), keyEquivalent: "n")
        var modifier = NSEvent.modifierFlags
        modifier.insert(.command)
        modifier.insert(.shift)
        newWindow.keyEquivalentModifierMask = modifier
        menu.addItem(newWindow)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Search and create", comment: ""), action: #selector(AppDelegate.searchAndCreate(_:)), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Settings", comment: ""), action: #selector(AppDelegate.openPreferences(_:)), keyEquivalent: ","))

        let lock = NSMenuItem(title: NSLocalizedString("Lock All Encrypted", comment: ""), action: #selector(ViewController.shared()?.lockAll(_:)), keyEquivalent: "l")
        lock.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(lock)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quit FSNotes", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.delegate = self
        statusItem?.menu = menu
    }

    @objc func clickStatusBarItem(sender: NSStatusItem) {
        let event = NSApp.currentEvent!

        if event.type == NSEvent.EventType.leftMouseUp {
            
            // Hide active not hidden and not miniaturized
            if !NSApp.isHidden && NSApp.isActive {
                if let mainWindow = AppDelegate.mainWindowController?.window, !mainWindow.isMiniaturized {
                    NSApp.hide(nil)
                    return
                }
            }
            
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            AppDelegate.mainWindowController?.window?.makeKeyAndOrderFront(nil)
            ViewController.shared()?.search.becomeFirstResponder()
            
            return
        }

        attachMenu()

        DispatchQueue.main.async {
            if let statusItem = self.statusItem, let button = statusItem.button {
                statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: button.frame.origin.x, y: button.frame.height + 10), in: button)
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }
    
    // MARK: IBActions
    
    @IBAction func openMainWindow(_ sender: Any) {
        AppDelegate.mainWindowController?.makeNew()
    }
    
    @IBAction func openHelp(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://github.com/glushchenko/fsnotes/wiki")!)
    }

    @IBAction func openReportsAndRequests(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://github.com/glushchenko/fsnotes/issues/new/choose")!)
    }

    @IBAction func openSite(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://fsnot.es")!)
    }
    
    @IBAction func openPreferences(_ sender: Any?) {
        if prefsWindowController == nil {
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            
            prefsWindowController = storyboard.instantiateController(withIdentifier: "Preferences") as? PrefsWindowController
        }
        
        guard let prefsWindowController = prefsWindowController else { return }
        
        prefsWindowController.showWindow(nil)
        prefsWindowController.window?.makeKeyAndOrderFront(prefsWindowController)
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func new(_ sender: Any?) {
        AppDelegate.mainWindowController?.makeNew()
        NSApp.activate(ignoringOtherApps: true)
        ViewController.shared()?.fileMenuNewNote(self)
    }
    
    @IBAction func createInNewWindow(_ sender: Any?) {
        AppDelegate.mainWindowController?.makeNew()
        NSApp.activate(ignoringOtherApps: true)
        ViewController.shared()?.createInNewWindow(self)
    }
    
    @IBAction func searchAndCreate(_ sender: Any?) {
        AppDelegate.mainWindowController?.makeNew()
        NSApp.activate(ignoringOtherApps: true)
        
        guard let vc = ViewController.shared() else { return }
        
        DispatchQueue.main.async {
            vc.search.window?.makeFirstResponder(vc.search)
        }
    }
    
    @IBAction func removeMenuBar(_ sender: Any?) {
        guard let statusItem = statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
    
    @IBAction func addMenuBar(_ sender: Any?) {
        constructMenu()
    }

    @IBAction func showAboutWindow(_ sender: AnyObject) {
        if aboutWindowController == nil {
            let storyboard = NSStoryboard(name: "Main", bundle: nil)

            aboutWindowController = storyboard.instantiateController(withIdentifier: "About") as? AboutWindowController
        }

        guard let aboutWindowController = aboutWindowController else { return }

        aboutWindowController.showWindow(nil)
        aboutWindowController.window?.makeKeyAndOrderFront(aboutWindowController)

        NSApp.activate(ignoringOtherApps: true)
    }

    public func loadDockIcon() {
        var image: Image?

        switch UserDefaultsManagement.dockIcon {
        case 0:
            image = NSImage(named: "icon.png")
            break
        case 1:
            image = NSImage(named: "icon_alt.png")
            break
        default:
            break
        }

        guard let im = image else { return }

        let appDockTile = NSApplication.shared.dockTile
        if #available(OSX 10.12, *) {
            appDockTile.contentView = NSImageView(image: im)
        }

        appDockTile.display()
    }

    private func checkStorageChanges() {
        if Storage.shared().shouldMovePrompt,
            let local = UserDefaultsManagement.localDocumentsContainer,
            let iCloudDrive = UserDefaultsManagement.iCloudDocumentsContainer
        {
            let message = NSLocalizedString("We are detect that you are install FSNotes from Mac App Store with default storage in iCloud Drive, do you want to move old database in iCloud Drive?", comment: "")

            promptToMoveDatabase(from: local, to: iCloudDrive, messageText: message)
        }
    }

    public func promptToMoveDatabase(from currentURL: URL, to url : URL, messageText: String) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText =
            NSLocalizedString("Otherwise, the database of your notes will be available at: ", comment: "") + currentURL.path

        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("No", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Yes", comment: ""))

        if alert.runModal() == .alertSecondButtonReturn {
            move(from: currentURL, to: url)

            let localTrash = currentURL.appendingPathComponent("Trash", isDirectory: true)
            let cloudTrash = url.appendingPathComponent("Trash", isDirectory: true)

            move(from: localTrash, to: cloudTrash)
        }
    }

    private func move(from currentURL: URL, to url: URL) {
        if let list = try? FileManager.default.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: nil, options: .init()) {

            if !FileManager.default.fileExists(atPath: currentURL.path) {
                return
            }

            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }

            for item in list {
                let fileName = item.lastPathComponent

                do {
                    let dst = url.appendingPathComponent(fileName)
                    try FileManager.default.moveItem(at: item, to: dst)
                } catch {

                    if ["Trash", "Welcome"].contains(fileName) {
                        continue
                    }

                    let exist = NSAlert()
                    var message = NSLocalizedString("We can not move \"{DST_PATH}\" because this item already exist in selected destination.", comment: "")

                    message = message.replacingOccurrences(of: "{DST_PATH}", with: item.path)

                    exist.messageText = message
                    exist.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                    exist.runModal()
                }
            }
        }
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {

        ViewController.shared()?.restoreUserActivityState(userActivity)

        return true
    }

    func application(_ application: NSApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {

        return true
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    public static func getEditTextViews() -> [EditTextView] {
        var views = [EditTextView]()
        
        for window in noteWindows {
            if let controller = window.contentViewController as? NoteViewController {
                views.append(controller.editor)
            }
        }
        
        if let controller = mainWindowController?.contentViewController as? ViewController {
            views.append(controller.editor)
        }
        
        return views
    }
}
