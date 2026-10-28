import Foundation

/// Generic-password access through the `security` tool, the same route Claude Code and the
/// Antigravity CLI use for their own items, so reads reuse the access those tools were granted.
struct Keychain {
    /// Keychain file to operate on. Nil uses the default search list, i.e. the login keychain.
    var path: String? = nil

    // The first access to another tool's item raises the keychain permission dialog, and the
    // call has to outlive the user reading it
    private static let promptTimeout: TimeInterval = 600

    func readGenericPassword(service: String, account: String?) -> String? {
        var arguments = ["find-generic-password", "-s", service]
        if let account {
            arguments += ["-a", account]
        }
        arguments.append("-w")
        if let path {
            arguments.append(path)
        }
        guard let output = ProcessRunner.run("/usr/bin/security", arguments, timeout: Self.promptTimeout),
              output.status == 0 else { return nil }
        let value = output.stdout.trimmingCharacters(in: .newlines)
        return value.isEmpty ? nil : value
    }

    /// The account attribute of the first item for the service, so a rewrite targets the item the
    /// owning tool created rather than adding a second one.
    func accountOfGenericPassword(service: String) -> String? {
        var arguments = ["find-generic-password", "-s", service]
        if let path {
            arguments.append(path)
        }
        guard let output = ProcessRunner.run("/usr/bin/security", arguments, timeout: Self.promptTimeout),
              output.status == 0 else { return nil }
        let prefix = "\"acct\"<blob>=\""
        for line in output.stdout.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }
            let value = trimmed.dropFirst(prefix.count)
            guard let end = value.lastIndex(of: "\"") else { continue }
            return String(value[..<end])
        }
        return nil
    }

    /// Creates or replaces the item.
    func writeGenericPassword(service: String, account: String, value: String) -> Bool {
        var arguments = ["add-generic-password", "-U", "-s", service, "-a", account, "-w", value]
        if let path {
            arguments.append(path)
        }
        return ProcessRunner.run("/usr/bin/security", arguments, timeout: Self.promptTimeout)?.status == 0
    }
}
