import AppKit

enum MainMenu {
    static func build(target: AppDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("YT Music", [
            item("About YT Music", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide YT Music", #selector(NSApplication.hide(_:)), key: "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit YT Music", #selector(NSApplication.terminate(_:)), key: "q"),
        ]))

        menu.addItem(menuItem("Edit", [
            item("Undo", Selector(("undo:")), key: "z"),
            item("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), key: "x"),
            item("Copy", #selector(NSText.copy(_:)), key: "c"),
            item("Paste", #selector(NSText.paste(_:)), key: "v"),
            item("Select All", #selector(NSText.selectAll(_:)), key: "a"),
        ]))

        menu.addItem(menuItem("View", [
            item("Reload", #selector(AppDelegate.reloadPage(_:)), key: "r", target: target),
            item("Back", #selector(AppDelegate.goBack(_:)), key: "[", target: target),
            item("Forward", #selector(AppDelegate.goForward(_:)), key: "]", target: target),
            item("Home", #selector(AppDelegate.goHome(_:)), key: "H", modifiers: [.command, .shift], target: target),
            .separator(),
            item("Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.control, .command]),
        ]))

        // Arrow keys are deliberately paired with Option: bare ⌘← and ⌘→ belong to text editing.
        let slackItem = item("Slack Status", #selector(AppDelegate.toggleSlackStatus(_:)), target: target)
        slackItem.state = UserDefaults.standard.bool(forKey: PlayerBridge.slackStatusKey) ? .on : .off
        menu.addItem(menuItem("Controls", [
            item("Play/Pause", #selector(AppDelegate.togglePlayPause(_:)), key: "p", target: target),
            item("Next", #selector(AppDelegate.nextTrack(_:)), key: "\u{F703}", modifiers: [.command, .option], target: target),
            item("Previous", #selector(AppDelegate.previousTrack(_:)), key: "\u{F702}", modifiers: [.command, .option], target: target),
            .separator(),
            slackItem,
        ]))

        let windowMenu = menuItem("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), key: "w"),
            item("Show Main Window", #selector(AppDelegate.showMainWindow(_:)), key: "0", target: target),
        ])
        menu.addItem(windowMenu)
        NSApp.windowsMenu = windowMenu.submenu

        return menu
    }

    private static func menuItem(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        items.forEach { submenu.addItem($0) }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        // nil target sends the action down the responder chain (Edit items, window actions).
        item.target = target
        return item
    }
}
