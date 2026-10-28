import Foundation

/// Claude Code keeps its OAuth session in the login keychain, with `~/.claude/.credentials.json`
/// as the fallback location. A rotated token is written back to wherever it was read from.
final class ClaudeCredentialStore: ClaudeCredentialStoring {
    static let service = "Claude Code-credentials"

    private enum Source {
        case keychain
        case file
    }

    private let keychain = Keychain()
    private let credentialsPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json")
    private var source: Source = .keychain

    func load() async -> ClaudeCredentialDocument? {
        let keychain = self.keychain
        let path = credentialsPath
        let loaded: (ClaudeCredentialDocument, Source)? = await Task.detached {
            if let raw = keychain.readGenericPassword(service: Self.service, account: nil),
               let document = ClaudeCredentialDocument(data: Data(raw.utf8)) {
                return (document, .keychain)
            }
            if let data = try? Data(contentsOf: path), let document = ClaudeCredentialDocument(data: data) {
                return (document, .file)
            }
            return nil
        }.value
        guard let loaded else { return nil }
        source = loaded.1
        return loaded.0
    }

    func save(_ document: ClaudeCredentialDocument) async throws {
        let keychain = self.keychain
        let path = credentialsPath
        switch source {
        case .keychain:
            let value = String(decoding: document.data, as: UTF8.self)
            let written = await Task.detached {
                let account = keychain.accountOfGenericPassword(service: Self.service) ?? NSUserName()
                return keychain.writeGenericPassword(service: Self.service, account: account, value: value)
            }.value
            guard written else { throw CocoaError(.fileWriteUnknown) }
        case .file:
            try document.data.write(to: path, options: .atomic)
            // Claude Code keeps the file owner-only; an atomic write replaces it with a fresh file
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        }
    }
}
