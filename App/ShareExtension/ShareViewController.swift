//
//  ShareViewController.swift
//  ShareExtension
//
//  The Share-sheet entry point for Markwise. When the user shares a `.md` file
//  (or selected text) into the app, this copies it into the App Group "Inbox"
//  folder and completes — the main app drains that folder on its next foreground
//  (see Persistence/SharedInbox). The extension stays deliberately tiny: it never
//  links the SwiftData stack, only the shared-container convention.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    /// Must match `AppGroup.identifier` / the "Inbox" convention in Persistence.
    private let appGroupID = "group.com.markwise.app"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleShare()
    }

    private func handleShare() {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            loadMarkdown(from: provider) { [weak self] name, text in
                if let text, !text.isEmpty { self?.deposit(markdown: text, name: name) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    /// Resolve a provider to (suggested name, markdown). Prefers a file URL
    /// (how `.md` files arrive), falling back to plain text.
    private func loadMarkdown(from provider: NSItemProvider,
                              completion: @escaping (String, String?) -> Void) {
        let fileURLType = UTType.fileURL.identifier
        if provider.hasItemConformingToTypeIdentifier(fileURLType) {
            provider.loadItem(forTypeIdentifier: fileURLType, options: nil) { item, _ in
                if let url = item as? URL, let text = try? String(contentsOf: url, encoding: .utf8) {
                    completion(url.deletingPathExtension().lastPathComponent, text)
                } else {
                    completion("Shared", nil)
                }
            }
            return
        }

        let textType = UTType.plainText.identifier
        if provider.hasItemConformingToTypeIdentifier(textType) {
            provider.loadItem(forTypeIdentifier: textType, options: nil) { item, _ in
                if let text = item as? String {
                    completion("Shared", text)
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    completion("Shared", text)
                } else {
                    completion("Shared", nil)
                }
            }
            return
        }

        completion("Shared", nil)
    }

    private func deposit(markdown: String, name: String) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let base = name.isEmpty ? "Shared" : name
        var fileName = "\(base).md"
        var counter = 2
        while FileManager.default.fileExists(atPath: inbox.appendingPathComponent(fileName).path) {
            fileName = "\(base)-\(counter).md"
            counter += 1
        }
        try? markdown.write(to: inbox.appendingPathComponent(fileName),
                            atomically: true, encoding: .utf8)
    }
}
