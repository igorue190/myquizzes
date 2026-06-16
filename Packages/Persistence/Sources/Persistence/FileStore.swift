//
//  FileStore.swift
//  Persistence
//
//  The managed store for raw .md bytes. On import a file is COPIED here so the
//  library is self-contained and offline (plan §4.3). Keyed by an opaque file
//  name; the database holds only that name, never the bytes.
//

import Foundation

public struct FileStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `Application Support/Markwise/Library` — the production location.
    public static func defaultRoot() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Markwise/Library", isDirectory: true)
    }

    /// A throwaway store under the temp directory (tests/previews).
    public static func temporary() -> FileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkwiseTests/\(UUID().uuidString)", isDirectory: true)
        return FileStore(root: dir)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func url(for name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: false)
    }

    public func write(_ contents: String, name: String) throws {
        try ensureDirectory()
        try contents.write(to: url(for: name), atomically: true, encoding: .utf8)
    }

    public func read(name: String) throws -> String {
        try String(contentsOf: url(for: name), encoding: .utf8)
    }

    public func delete(name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}
