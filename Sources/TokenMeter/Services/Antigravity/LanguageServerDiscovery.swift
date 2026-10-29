import Foundation

/// Finds the Codeium-derived language server that Antigravity (or the `agy` CLI) runs locally.
/// The process advertises its CSRF token and HTTP fallback port in its own argv, and its RPC
/// ports show up as listening sockets owned by its pid.
enum LanguageServerDiscovery {
    struct Candidate: Equatable {
        let pid: Int32
        let command: String
    }

    private struct Search {
        let processName: String
        let markers: [String]
        let csrfFlag: String?
        let portFlag: String?
    }

    // The agy CLI embeds its language server in-process and generates its CSRF token there, so
    // only the app's language server, which carries the token in its arguments, is reachable
    private static let searches = [
        Search(processName: "language_server", markers: ["antigravity", "antigravity-ide"], csrfFlag: "--csrf_token", portFlag: "--extension_server_port"),
    ]

    /// Locates the Antigravity app's language server by running `ps` and `lsof`. Blocking
    /// subprocess work, so callers run it off the main actor.
    static func discover() -> [LanguageServerLocation] {
        guard let ps = ProcessRunner.run("/bin/ps", ["-ax", "-o", "pid=,command="]), ps.status == 0 else { return [] }
        var locations: [LanguageServerLocation] = []
        for search in searches {
            for candidate in candidates(psOutput: ps.stdout, processName: search.processName, markers: search.markers) {
                var csrf = ""
                if let flag = search.csrfFlag {
                    guard let value = extractFlag(command: candidate.command, flag: flag) else { continue }
                    csrf = value
                }
                let extensionPort = search.portFlag
                    .flatMap { extractFlag(command: candidate.command, flag: $0) }
                    .flatMap { Int($0) }
                let lsof = ProcessRunner.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(candidate.pid)])
                let ports = lsof.map { parseListeningPorts($0.stdout) } ?? []
                guard !ports.isEmpty || extensionPort != nil else { continue }
                locations.append(LanguageServerLocation(csrf: csrf, ports: ports, extensionPort: extensionPort))
            }
        }
        return locations
    }

    /// Parses `ps -ax -o pid=,command=` output into the processes matching `processName`, ranked
    /// with exact IDE flag matches before `/marker/` path matches. Empty `markers` matches any
    /// instance of the process.
    static func candidates(psOutput: String, processName: String, markers: [String]) -> [Candidate] {
        let name = processName.lowercased()
        let markers = markers.map { $0.lowercased() }.filter { !$0.isEmpty }
        var ranked: [(rank: Int, candidate: Candidate)] = []
        for rawLine in psOutput.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let separator = line.firstIndex(where: { $0 == " " || $0 == "\t" }),
                  let pid = Int32(line[..<separator]) else { continue }
            let command = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard commandMatches(command, processName: name),
                  let rank = markerRank(command, markers: markers) else { continue }
            ranked.append((rank, Candidate(pid: pid, command: command)))
        }
        return ranked.sorted { $0.rank < $1.rank }.map(\.candidate)
    }

    /// Value of `--flag value` or `--flag=value` in a command line.
    static func extractFlag(command: String, flag: String) -> String? {
        let parts = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for (index, part) in parts.enumerated() {
            if part == flag {
                return index + 1 < parts.count ? parts[index + 1] : nil
            }
            if part.hasPrefix(flag + "=") {
                return String(part.dropFirst(flag.count + 1))
            }
        }
        return nil
    }

    /// Listening ports from `lsof -nP -iTCP -sTCP:LISTEN` output, ascending.
    static func parseListeningPorts(_ output: String) -> [Int] {
        var ports = Set<Int>()
        for line in output.split(whereSeparator: \.isNewline) where line.contains("LISTEN") {
            for token in line.split(separator: " ").reversed() {
                if let colon = token.lastIndex(of: ":"),
                   let port = Int(token[token.index(after: colon)...]),
                   (1..<65536).contains(port) {
                    ports.insert(port)
                    break
                }
            }
        }
        return ports.sorted()
    }

    private static func markerRank(_ command: String, markers: [String]) -> Int? {
        if markers.isEmpty { return 0 }
        let flagged = ["--ide_name", "--override_ide_name", "--app_data_dir"]
            .compactMap { extractFlag(command: command, flag: $0)?.lowercased() }
        if !flagged.isEmpty {
            return markers.contains(where: flagged.contains) ? 0 : nil
        }
        let lower = command.lowercased()
        return markers.contains { lower.contains("/\($0)/") } ? 1 : nil
    }

    private static func commandMatches(_ command: String, processName: String) -> Bool {
        let executable = (String(command.split(separator: " ", maxSplits: 1).first ?? "") as NSString)
            .lastPathComponent.lowercased()
        if executable == processName { return true }
        let lower = command.lowercased()
        if processName.count >= 8 {
            return executable.hasPrefix(processName + "_") || lower.contains(processName)
        }
        return lower.hasSuffix("/\(processName)") || lower.contains("/\(processName) ")
    }
}
