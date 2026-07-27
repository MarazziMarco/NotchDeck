import Foundation

/// A line emitted by a managed subprocess, tagged by stream.
enum ProcessLine: Equatable {
    case stdout(String)
    case stderr(String)
    case terminated(Int32)
}

/// Safely launches and supervises a subprocess with separate stdin/stdout/stderr
/// pipes. Arguments are passed as an array (never through `/bin/sh -c`). Access
/// to the process and its streams is serialized through an actor.
actor ManagedProcess {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private var outBuffer = LineBuffer()
    private var errBuffer = LineBuffer()
    private var continuation: AsyncStream<ProcessLine>.Continuation?
    private var isRunning = false

    /// Launch the process and return a stream of tagged output lines.
    /// - Throws: `NotchDeckError.processLaunchFailed` if the process can't start.
    func launch(executablePath: String,
                arguments: [String],
                workingDirectory: URL?,
                environment: [String: String]) throws -> AsyncStream<ProcessLine> {
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }

        // Inherit a sane PATH plus caller-supplied overrides.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ExecutableResolver.defaultSearchPaths.joined(separator: ":")
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
        for (k, v) in environment { env[k] = v }
        process.environment = env

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stream = AsyncStream<ProcessLine> { continuation in
            self.continuation = continuation
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.ingest(data, stream: .out) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.ingest(data, stream: .err) }
        }
        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task { await self?.handleTermination(status) }
        }

        do {
            try process.run()
            isRunning = true
        } catch {
            continuation?.finish()
            throw NotchDeckError.processLaunchFailed(
                tool: (executablePath as NSString).lastPathComponent,
                underlying: error.localizedDescription)
        }
        return stream
    }

    private enum StreamTag { case out, err }

    private func ingest(_ data: Data, stream: StreamTag) {
        let lines: [String]
        switch stream {
        case .out: lines = outBuffer.append(data)
        case .err: lines = errBuffer.append(data)
        }
        for line in lines {
            continuation?.yield(stream == .out ? .stdout(line) : .stderr(line))
        }
    }

    private func handleTermination(_ status: Int32) {
        isRunning = false
        if let last = outBuffer.flush() { continuation?.yield(.stdout(last)) }
        if let last = errBuffer.flush() { continuation?.yield(.stderr(last)) }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        continuation?.yield(.terminated(status))
        continuation?.finish()
    }

    /// Write a line to stdin (adds a trailing newline).
    func writeLine(_ text: String) {
        guard isRunning, let data = (text + "\n").data(using: .utf8) else { return }
        stdinPipe.fileHandleForWriting.write(data)
    }

    func closeStdin() {
        try? stdinPipe.fileHandleForWriting.close()
    }

    /// Terminate gently (SIGTERM) then forcibly (SIGKILL) after a grace period.
    /// Only ever kills the process this instance launched.
    func terminate(graceSeconds: Double = 2.0) async {
        guard isRunning else { return }
        process.terminate() // SIGTERM
        try? await Task.sleep(nanoseconds: UInt64(graceSeconds * 1_000_000_000))
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    var running: Bool { isRunning }
    var pid: Int32 { process.processIdentifier }
    var livePID: Int32? { isRunning ? process.processIdentifier : nil }
}
