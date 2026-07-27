import Foundation
import Darwin

/// Best-effort local scanner backed by libproc/BSD APIs. It never invokes a
/// shell, Terminal Automation, Accessibility, or the hook bridge.
struct MacAgentProcessDiscovery: AgentProcessDiscovering {
    private let uid = getuid()
    private let ancestryLimit = 16

    func discover(at timestamp: Date = Date()) -> [AgentProcessSnapshot] {
        let snapshots = enumeratePIDs().compactMap {
            snapshot(pid: $0, timestamp: timestamp)
        }
        return AgentProcessSnapshotNormalizer.preferProviderProcesses(snapshots) {
            readProcessRecord(pid: $0)
        }
    }

    private func snapshot(pid: Int32, timestamp: Date) -> AgentProcessSnapshot? {
        guard pid > 1, let before = readBSDInfo(pid: pid),
              before.pbi_uid == uid || before.pbi_ruid == uid else { return nil }

        let executablePath = readExecutablePath(pid: pid)
        let executable = URL(fileURLWithPath: executablePath).lastPathComponent.lowercased()
        guard AgentProviderClassifier.shouldInspectArguments(
            executableBasename: executable
        ) else {
            return nil
        }
        let arguments = readArguments(pid: pid)
        guard let classification = AgentProviderClassifier.classify(
            executablePath: executablePath,
            arguments: arguments
        ) else { return nil }

        // Re-read identity after the slower path/argv work. A disappearing or
        // reused PID is discarded rather than attached to stale state.
        guard let after = readBSDInfo(pid: pid),
              identity(before) == identity(after) else { return nil }

        let processIdentity = identity(after)
        return AgentProcessSnapshot(
            identity: processIdentity,
            parentPID: Int32(bitPattern: after.pbi_ppid),
            provider: classification.provider,
            classification: classification,
            executableBasename: URL(fileURLWithPath: executablePath).lastPathComponent,
            workingDirectory: readWorkingDirectory(pid: pid),
            controllingTTY: ttyCapture(
                processInfo: after,
                processIdentity: processIdentity,
                timestamp: timestamp
            ),
            discoveredAt: timestamp
        )
    }

    private func enumeratePIDs() -> [Int32] {
        let requiredBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard requiredBytes > 0 else { return [] }
        let initialCount = Int(requiredBytes) / MemoryLayout<Int32>.stride + 64
        var pids = [Int32](repeating: 0, count: initialCount)
        let bytes = pids.withUnsafeMutableBytes {
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                $0.baseAddress,
                Int32($0.count)
            )
        }
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes) / MemoryLayout<Int32>.stride).filter { $0 > 1 }
    }

    private func readBSDInfo(pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
        let actual = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected)
        return actual == expected ? info : nil
    }

    private func identity(_ info: proc_bsdinfo) -> AgentProcessIdentity {
        AgentProcessIdentity(
            pid: Int32(bitPattern: info.pbi_pid),
            startSeconds: UInt64(info.pbi_start_tvsec),
            startMicroseconds: UInt64(info.pbi_start_tvusec)
        )
    }

    private func readProcessRecord(pid: Int32) -> AgentProcessRecord? {
        guard let info = readBSDInfo(pid: pid) else { return nil }
        return AgentProcessRecord(
            identity: identity(info),
            parentPID: Int32(bitPattern: info.pbi_ppid)
        )
    }

    private func readExecutablePath(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard count > 0 else { return "" }
        return String(cString: buffer)
    }

    private func readWorkingDirectory(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let expected = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, expected) == expected else {
            return nil
        }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return path.isEmpty ? nil : path
    }

    /// Reads exactly argc strings and stops before the environment block.
    private func readArguments(pid: Int32) -> [String] {
        var maximum = Int32(0)
        var maximumSize = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.argmax", &maximum, &maximumSize, nil, 0) == 0 else { return [] }
        let capacity = min(max(Int(maximum), 4096), 2 * 1024 * 1024)
        var bytes = [UInt8](repeating: 0, count: capacity)
        var size = bytes.count
        var mib = [CTL_KERN, 49, pid] // KERN_PROCARGS2
        let status = bytes.withUnsafeMutableBytes { raw in
            sysctl(&mib, 3, raw.baseAddress, &size, nil, 0)
        }
        guard status == 0, size >= MemoryLayout<Int32>.size else { return [] }
        bytes.removeSubrange(size..<bytes.count)
        return Self.parseArguments(bytes)
    }

    static func parseArguments(_ bytes: [UInt8]) -> [String] {
        guard bytes.count >= MemoryLayout<Int32>.size else { return [] }
        let argc: Int32 = bytes.withUnsafeBytes { raw in
            raw.loadUnaligned(as: Int32.self)
        }
        guard argc > 0, argc < 10_000 else { return [] }

        var index = MemoryLayout<Int32>.size
        func skipString() {
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            while index < bytes.count, bytes[index] == 0 { index += 1 }
        }
        skipString() // exec path

        var arguments: [String] = []
        for _ in 0..<argc {
            guard index < bytes.count else { break }
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            guard index > start,
                  let value = String(bytes: bytes[start..<index], encoding: .utf8) else { break }
            arguments.append(value)
            while index < bytes.count, bytes[index] == 0 { index += 1 }
        }
        return arguments
    }

    private func ttyCapture(
        processInfo: proc_bsdinfo,
        processIdentity: AgentProcessIdentity,
        timestamp: Date
    ) -> AgentTTYCapture? {
        if let tty = ttyPath(device: processInfo.e_tdev) {
            return AgentTTYCapture(
                device: processInfo.e_tdev,
                canonicalPath: tty,
                source: .process,
                capturedAt: timestamp,
                sourceIdentity: processIdentity
            )
        }

        var visited = Set<Int32>()
        var current = Int32(bitPattern: processInfo.pbi_ppid)
        for _ in 0..<ancestryLimit {
            guard current > 1, visited.insert(current).inserted,
                  let parent = readBSDInfo(pid: current) else { break }
            let parentIdentity = identity(parent)
            if let tty = ttyPath(device: parent.e_tdev) {
                return AgentTTYCapture(
                    device: parent.e_tdev,
                    canonicalPath: tty,
                    source: .ancestor,
                    capturedAt: timestamp,
                    sourceIdentity: parentIdentity
                )
            }
            current = Int32(bitPattern: parent.pbi_ppid)
        }
        return nil
    }

    private func ttyPath(device: UInt32) -> String? {
        guard device != UInt32.max, device != 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 128)
        guard devname_r(dev_t(device), mode_t(S_IFCHR), &buffer, Int32(buffer.count)) != nil else {
            return nil
        }
        let name = String(cString: buffer)
        guard !name.isEmpty else { return nil }
        return TerminalTabMatching.canonical(name)
    }
}

/// Resolves a live helper's ancestry while its socket is still connected. Every
/// node carries PID + start time, so PID reuse cannot create a false match.
enum MacProcessAncestry {
    static func identities(from pid: Int32, maxDepth: Int = 16) -> [AgentProcessIdentity] {
        ProcessAncestryResolver.resolve(from: pid, maxDepth: maxDepth) { current in
            var info = proc_bsdinfo()
            let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, expected) == expected else {
                return nil
            }
            return AgentProcessRecord(
                identity: AgentProcessIdentity(
                    pid: Int32(bitPattern: info.pbi_pid),
                    startSeconds: UInt64(info.pbi_start_tvsec),
                    startMicroseconds: UInt64(info.pbi_start_tvusec)
                ),
                parentPID: Int32(bitPattern: info.pbi_ppid)
            )
        }
    }
}
