import Foundation

// Helper executable that runs blueutil with arguments and enforces a timeout.
// Usage: SwitchMacBTHelper <blueutil-args...>

let blueutilPaths = ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]
let timeout: TimeInterval = 15.0

func blueutilPath() -> String? {
    for p in blueutilPaths where FileManager.default.fileExists(atPath: p) {
        return p
    }
    return nil
}

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty {
    fputs("No arguments provided.\n", stderr)
    exit(1)
}

guard let blue = blueutilPath() else {
    fputs("blueutil not found\n", stderr)
    exit(2)
}

let proc = Process()
let outPipe = Pipe()
let errPipe = Pipe()
proc.executableURL = URL(fileURLWithPath: blue)
proc.arguments = args
proc.standardOutput = outPipe
proc.standardError = errPipe

let sem = DispatchSemaphore(value: 0)
proc.terminationHandler = { _ in sem.signal() }

do {
    try proc.run()
} catch {
    fputs("Failed to run blueutil: \(error)\n", stderr)
    exit(3)
}

let waitResult = sem.wait(timeout: .now() + timeout)
if waitResult == .timedOut {
    // timed out - terminate and exit with special code
    proc.terminate()
    _ = sem.wait(timeout: .now() + 2.0)
    fputs("blueutil timed out after \(timeout)s\n", stderr)
    exit(253)
}

// forward stdout and stderr
let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
if !outData.isEmpty {
    FileHandle.standardOutput.write(outData)
}
let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
if !errData.isEmpty {
    FileHandle.standardError.write(errData)
}

let status = proc.terminationStatus
exit(Int32(status))
