import Foundation
import IOBluetooth

// MARK: - BluetoothDevice

struct BluetoothDevice: Hashable {
    let name: String
    let address: String   // format: "xx-xx-xx-xx-xx-xx"
    let isConnected: Bool

    var displayName: String { "\(name)  (\(address))" }
}

// MARK: - BluetoothManager

class BluetoothManager {

    private let defaultsKey = "switchmac.keyboardAddress"

    var keyboardAddress: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    // MARK: Device discovery

    func pairedDevices() -> [BluetoothDevice] {
        if let output = runBlueutil(args: ["--paired"]), !output.isEmpty {
            let parsed = parseBlueutil(output)
            if !parsed.isEmpty { return parsed }
        }
        if let all = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice], !all.isEmpty {
            return all.compactMap { d in
                guard let addr = d.addressString else { return nil }
                return BluetoothDevice(name: d.name ?? "Unknown", address: addr, isConnected: d.isConnected())
            }
        }
        return []
    }

    // MARK: Status queries

    func isKeyboardPaired(_ address: String) -> Bool {
        if let output = runBlueutil(args: ["--paired"]) {
            return parseBlueutil(output).contains { normalise($0.address) == normalise(address) }
        }
        return IOBluetoothDevice(addressString: address) != nil
    }

    func isKeyboardConnected(_ address: String) -> Bool {
        if let output = runBlueutil(args: ["--info", address]) {
            return output.contains(", connected")
        }
        return IOBluetoothDevice(addressString: address)?.isConnected() ?? false
    }

    // MARK: Actions

    /// Fully forgets/unpairs the keyboard from this Mac.
    /// After this the keyboard is free for another Mac to claim.
    func unpair(_ address: String) {
        log("Unpairing \(address)…")
        // Disconnect first, then unpair
        run("--disconnect", address)
        Thread.sleep(forTimeInterval: 1.0)
        run("--unpair", address)
    }

    /// Connects to the keyboard. Keyboard must still be paired with this Mac.
    func connect(_ address: String) {
        log("Connecting to \(address)…")
        let result = run("--connect", address)
        if result != 0 {
            // Fallback: IOBluetooth
            IOBluetoothDevice(addressString: address)?.openConnection()
        }
    }

    // MARK: blueutil

    private let blueutilPaths = ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]

    private func blueutilPath() -> String? {
        blueutilPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    @discardableResult
    private func run(_ args: String...) -> Int32 {
        guard let path = blueutilPath() else {
            log("blueutil not found — brew install blueutil")
            return -1
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        try? proc.run()
        proc.waitUntilExit()
        log("blueutil \(args.joined(separator: " ")) → \(proc.terminationStatus)")
        return proc.terminationStatus
    }

    private func runBlueutil(args: [String]) -> String? {
        guard let path = blueutilPath() else { return nil }
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    // MARK: Parsing

    private func parseBlueutil(_ output: String) -> [BluetoothDevice] {
        var result: [BluetoothDevice] = []
        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("address:") else { continue }
            guard let addrRange = t.range(of: #"address:\s*([0-9a-fA-F\-:]+)"#, options: .regularExpression) else { continue }
            let address = normalise(String(t[addrRange])
                .replacingOccurrences(of: "address:", with: "")
                .trimmingCharacters(in: .whitespaces))
            let isConnected = t.contains(", connected")
            var name = address
            if let r = t.range(of: #"name:\s*"([^"]+)""#, options: .regularExpression) {
                name = String(t[r])
                    .replacingOccurrences(of: #"name:\s*""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            result.append(BluetoothDevice(name: name, address: address, isConnected: isConnected))
        }
        return result
    }

    private func normalise(_ addr: String) -> String {
        addr.lowercased().replacingOccurrences(of: ":", with: "-")
    }

    private func log(_ msg: String) { NSLog("SwitchMac/BT: \(msg)") }
}

