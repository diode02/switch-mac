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

    // A reference to any currently-running helper/blueutil Process so it can be cancelled.
    private var currentProcess: Process?
    private let processQueue = DispatchQueue(label: "SwitchMac.BluetoothManager.processQueue")

    /// Whether a helper/blueutil process is currently running.
    var isBusy: Bool { processQueue.sync { currentProcess != nil } }

    var keyboardAddress: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Cancel any running blueutil/helper operation (safe to call from main thread).
    func cancelCurrentOperation() {
        processQueue.sync {
            if let p = currentProcess {
                p.terminate()
                currentProcess = nil
            }
        }
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
        // Run in background to avoid blocking UI if blueutil hangs
        DispatchQueue.global(qos: .utility).async {
            // Disconnect first, then unpair
            _ = self.run("--disconnect", address)
            Thread.sleep(forTimeInterval: 1.0)
            _ = self.run("--unpair", address)
        }
    }

    /// Connects to the keyboard. Keyboard must still be paired with this Mac.
    func connect(_ address: String) {
        log("Connecting to \(address)…")
        DispatchQueue.global(qos: .utility).async {
            let result = self.run("--connect", address)
            if result != 0 {
                // Fallback: IOBluetooth
                if let dev = IOBluetoothDevice(addressString: address) {
                    dev.openConnection()
                }
            }
        }
    }

    // MARK: blueutil

    private let blueutilPaths = ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]

    private func blueutilPath() -> String? {
        blueutilPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private let blueutilTimeout: TimeInterval = 10.0

    /// Path to the helper executable (if built or bundled alongside the app).
    private func helperPath() -> String? {
        // Look next to the running executable (app bundle or debug build)
        if let exe = Bundle.main.executableURL {
            let candidate = exe.deletingLastPathComponent().appendingPathComponent("SwitchMacBTHelper").path
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        // Common build output when running via `swift run`/`swift build`
        let debugCandidate = FileManager.default.currentDirectoryPath + "/.build/debug/SwitchMacBTHelper"
        if FileManager.default.fileExists(atPath: debugCandidate) { return debugCandidate }
        // Installed location (optional)
        let local = "/usr/local/bin/SwitchMacBTHelper"
        if FileManager.default.fileExists(atPath: local) { return local }
        return nil
    }

    @discardableResult
    private func run(_ args: String...) -> Int32 {
        // Prefer helper executable when available — it isolates blueutil in a separate process.
        if let helper = helperPath() {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: helper)
            proc.arguments = args
            let sem = DispatchSemaphore(value: 0)
            proc.terminationHandler = { p in
                // clear currentProcess and signal semaphore
                self.processQueue.sync { if self.currentProcess === p { self.currentProcess = nil } }
                sem.signal()
            }
            do {
                try proc.run()
            } catch {
                log("Failed to run helper: \(error)")
                return -1
            }
            // record running process so callers can cancel it
            processQueue.sync { currentProcess = proc }
            let waitResult = sem.wait(timeout: .now() + blueutilTimeout)
            if waitResult == .timedOut {
                log("helper \(args.joined(separator: " ")) timed out after \(blueutilTimeout)s — terminating")
                proc.terminate()
                _ = sem.wait(timeout: .now() + 2.0)
                processQueue.sync { if self.currentProcess === proc { self.currentProcess = nil } }
                return -2
            }
            let status = proc.terminationStatus
            // Map helper's special timeout code (253) to local -2
            if status == 253 { return -2 }
            log("helper \(args.joined(separator: " ")) → \(status)")
            return status
        }

        // Fallback: run blueutil directly with an enforced timeout
        guard let path = blueutilPath() else {
            log("blueutil not found — brew install blueutil")
            return -1
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let sem = DispatchSemaphore(value: 0)
        proc.terminationHandler = { p in
            self.processQueue.sync { if self.currentProcess === p { self.currentProcess = nil } }
            sem.signal()
        }
        do {
            try proc.run()
        } catch {
            log("Failed to run blueutil: \(error)")
            return -1
        }
        processQueue.sync { currentProcess = proc }
        let waitResult = sem.wait(timeout: .now() + blueutilTimeout)
        if waitResult == .timedOut {
            log("blueutil \(args.joined(separator: " ")) timed out after \(blueutilTimeout)s — terminating")
            proc.terminate()
            // Give it a short moment to exit cleanly
            _ = sem.wait(timeout: .now() + 2.0)
            processQueue.sync { if self.currentProcess === proc { self.currentProcess = nil } }
            return -2
        }
        log("blueutil \(args.joined(separator: " ")) → \(proc.terminationStatus)")
        return proc.terminationStatus
    }

    private func runBlueutil(args: [String]) -> String? {
        // Prefer helper executable when available — captures output and isolates hangs
        if let helper = helperPath() {
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: helper)
            proc.arguments = args
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            let sem = DispatchSemaphore(value: 0)
            proc.terminationHandler = { _ in sem.signal() }
            do {
                try proc.run()
            } catch {
                log("Failed to run helper: \(error)")
                return nil
            }
            let waitResult = sem.wait(timeout: .now() + blueutilTimeout)
            if waitResult == .timedOut {
                log("helper \(args.joined(separator: " ")) timed out after \(blueutilTimeout)s — terminating")
                proc.terminate()
                _ = sem.wait(timeout: .now() + 2.0)
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        }

        // Fallback: run blueutil directly
        guard let path = blueutilPath() else { return nil }
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        let sem = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in sem.signal() }
        do {
            try proc.run()
        } catch {
            log("Failed to run blueutil: \(error)")
            return nil
        }
        let waitResult = sem.wait(timeout: .now() + blueutilTimeout)
        if waitResult == .timedOut {
            log("blueutil \(args.joined(separator: " ")) timed out after \(blueutilTimeout)s — terminating")
            proc.terminate()
            _ = sem.wait(timeout: .now() + 2.0)
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
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

