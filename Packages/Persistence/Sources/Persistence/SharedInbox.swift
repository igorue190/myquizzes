//
//  SharedInbox.swift
//  Persistence
//
//  The hand-off point between the Share extension and the app. When the user
//  shares a `.md` file into Markwise, the extension drops it into the App Group
//  container's "Inbox" folder; the app drains that folder on the next foreground
//  and imports each file into the library. Keeps the extension tiny — it never
//  has to link the SwiftData stack.
//
//  NOTE: the extension target keeps its own copy of the group id + "Inbox"
//  convention (it doesn't link this package); the two must stay in sync.
//

import Foundation

/// The App Group shared between the app and its Share extension.
public enum AppGroup {
    public static let identifier = "group.com.markwise.app"

    /// The shared container URL, or nil when the App Group entitlement isn't
    /// present (e.g. an unsigned simulator build).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// A drop box of Markdown files shared into the app, awaiting import.
public struct SharedInbox: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The App-Group inbox when available, otherwise a local fallback so the
    /// app side still runs (and is testable) without the entitlement.
    public static func shared() -> SharedInbox {
        let base = AppGroup.containerURL
            ?? (try? FileManager.default.url(for: .applicationSupportDirectory,
                                             in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return SharedInbox(directory: base.appendingPathComponent("Inbox", isDirectory: true))
    }

    public struct PendingFile: Sendable, Equatable {
        public let title: String        // file name without the .md extension
        public let markdown: String
        public let url: URL
    }

    /// Write an incoming file into the inbox. (Mirrored by the extension.)
    @discardableResult
    public func deposit(_ markdown: String, suggestedName: String) -> URL? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            Self.uniqueName(for: suggestedName, in: directory), isDirectory: false)
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Every `.md` file currently waiting to be imported.
    public func pendingFiles() -> [PendingFile] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return PendingFile(
                    title: url.deletingPathExtension().lastPathComponent,
                    markdown: text,
                    url: url
                )
            }
    }

    public func remove(_ file: PendingFile) {
        try? FileManager.default.removeItem(at: file.url)
    }

    private static func uniqueName(for suggested: String, in dir: URL) -> String {
        let trimmed = suggested.hasSuffix(".md") ? String(suggested.dropLast(3)) : suggested
        let base = trimmed.isEmpty ? "Shared" : trimmed
        var name = "\(base).md"
        var counter = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = "\(base)-\(counter).md"
            counter += 1
        }
        return name
    }
}
