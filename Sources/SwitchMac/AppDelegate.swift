import AppKit

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let bluetooth = BluetoothManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        if bluetooth.keyboardAddress == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.promptKeyboardSelection()
            }
        }
    }

    // MARK: Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "SwitchMac")
            btn.image?.isTemplate = true
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        guard let address = bluetooth.keyboardAddress else {
            let item = NSMenuItem(title: "⚙ Configure keyboard first…", action: #selector(promptKeyboardSelection), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit SwitchMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            return
        }

        let isPaired   = bluetooth.isKeyboardPaired(address)
        let isConnected = bluetooth.isKeyboardConnected(address)

        // ── Status header ──
        let statusText: String
        if isConnected      { statusText = "⌨  Keyboard connected to this Mac" }
        else if isPaired    { statusText = "○  Keyboard paired (not connected)" }
        else                { statusText = "✗  Keyboard not paired with this Mac" }
        let statusItem2 = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem2.isEnabled = false
        menu.addItem(statusItem2)

        menu.addItem(.separator())

        // ── Step 1: Release ──
        let releaseItem = NSMenuItem(
            title: "1️⃣  Release keyboard from this Mac",
            action: #selector(releaseKeyboard),
            keyEquivalent: "r"
        )
        releaseItem.target = self
        releaseItem.isEnabled = isPaired
        menu.addItem(releaseItem)

        // ── Step 2: Connect ──
        let connectItem = NSMenuItem(
            title: "2️⃣  Connect keyboard to this Mac",
            action: #selector(connectKeyboard),
            keyEquivalent: "c"
        )
        connectItem.target = self
        connectItem.isEnabled = !isConnected
        menu.addItem(connectItem)

        menu.addItem(.separator())

        let addrItem = NSMenuItem(title: "Keyboard: \(address)", action: nil, keyEquivalent: "")
        addrItem.isEnabled = false
        menu.addItem(addrItem)

        let setupItem = NSMenuItem(title: "Change Keyboard…", action: #selector(promptKeyboardSelection), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SwitchMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: Actions

    /// Step 1 — run on the Mac that currently HAS the keyboard.
    /// Fully unpairs/forgets the keyboard so the other Mac can claim it.
    @objc private func releaseKeyboard() {
        guard let address = bluetooth.keyboardAddress else { return }
        bluetooth.unpair(address)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.rebuildMenu() }
    }

    /// Step 2 — run on the Mac that WANTS the keyboard.
    /// Keyboard must already be paired; just opens the connection.
    @objc private func connectKeyboard() {
        guard let address = bluetooth.keyboardAddress else { return }
        bluetooth.connect(address)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.rebuildMenu() }
    }

    // MARK: Keyboard picker

    @objc func promptKeyboardSelection() {
        let devices = bluetooth.pairedDevices()

        let alert = NSAlert()
        alert.messageText = "Select Keyboard"
        alert.informativeText = "Choose your Magic Keyboard, or type its MAC address below."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .left
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 80)

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 26))
        popup.addItem(withTitle: "— type MAC address below —")
        for d in devices.sorted(by: { $0.isConnected && !$1.isConnected }) {
            let label = d.isConnected ? "● \(d.displayName)" : "  \(d.displayName)"
            popup.addItem(withTitle: label)
            popup.lastItem?.representedObject = d
        }
        stack.addArrangedSubview(popup)

        let manualLabel = NSTextField(labelWithString: "MAC address (e.g. ac-97-38-68-39-07):")
        stack.addArrangedSubview(manualLabel)

        let manualField = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 22))
        manualField.placeholderString = "xx-xx-xx-xx-xx-xx"
        if let existing = bluetooth.keyboardAddress { manualField.stringValue = existing }
        stack.addArrangedSubview(manualField)

        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let manual = manualField.stringValue.trimmingCharacters(in: .whitespaces)
        if !manual.isEmpty {
            bluetooth.keyboardAddress = manual
        } else if let d = popup.selectedItem?.representedObject as? BluetoothDevice {
            bluetooth.keyboardAddress = d.address
        }
        rebuildMenu()
    }
}

