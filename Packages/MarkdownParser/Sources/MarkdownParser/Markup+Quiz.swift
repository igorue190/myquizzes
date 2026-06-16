//
//  Markup+Quiz.swift
//  MarkdownParser
//
//  Thin helpers over the swift-markdown AST. All direct use of the swift-markdown
//  API is concentrated here and in MarkdownQuizParser, so if a swift-markdown
//  version bumps an API the blast radius is one file.
//

import Foundation
import Markdown

extension Markup {
    /// The inline Markdown of this node's children, preserving bold/italic/code/
    /// links (used for prompts and answer labels, which keep their formatting).
    var inlineMarkdown: String {
        children
            .map { $0.format() }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ListItem {
    /// The answer label — the inline Markdown of the item's first paragraph,
    /// stripped of the task-list marker.
    var answerText: String {
        for child in children {
            if let paragraph = child as? Paragraph {
                return paragraph.inlineMarkdown
            }
        }
        return children.map { $0.format() }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when this is a `- [x]` item.
    var isChecked: Bool { checkbox == .checked }
}

extension BlockQuote {
    /// Split an explanation blockquote into its explanation text and an optional
    /// reference. Tolerant of the two living on one soft-wrapped line or two.
    var explanationAndReference: (explanation: String?, reference: String?) {
        let full = plainText(of: self)
        var explanationPart = full
        var reference: String?

        if let r = full.range(of: "reference:", options: .caseInsensitive) {
            let after = String(full[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            reference = after.isEmpty ? nil : after
            explanationPart = String(full[..<r.lowerBound])
        }
        if let e = explanationPart.range(of: "explanation:", options: .caseInsensitive) {
            explanationPart = String(explanationPart[e.upperBound...])
        }

        // Prefer a real link destination over scraped text when one exists.
        if let dest = firstLinkDestination(in: self) {
            reference = dest
        }

        let explanation = explanationPart.trimmingCharacters(in: .whitespacesAndNewlines)
        return (explanation.isEmpty ? nil : explanation, reference)
    }
}

/// Concatenated text of all descendant text nodes. swift-markdown doesn't
/// expose a `plainText`, so we walk it ourselves: `Text`/`InlineCode` contribute
/// their string, soft/hard line breaks become spaces, everything else recurses.
func plainText(of markup: Markup) -> String {
    var result = ""
    func walk(_ node: Markup) {
        for child in node.children {
            switch child {
            case let text as Text:        result += text.string
            case let code as InlineCode:  result += code.code
            case is SoftBreak, is LineBreak: result += " "
            default:                      walk(child)
            }
        }
    }
    walk(markup)
    return result
}

/// Depth-first search for the first link destination under a markup node.
func firstLinkDestination(in markup: Markup) -> String? {
    for child in markup.children {
        if let link = child as? Link, let dest = link.destination, !dest.isEmpty {
            return dest
        }
        if let nested = firstLinkDestination(in: child) {
            return nested
        }
    }
    return nil
}

/// Parses a `<!-- type: ... -->` / `<!-- tags: ... -->` HTML comment.
enum CommentDirective {
    static func parse(_ rawHTML: String) -> (type: String?, tags: [String]?) {
        let inner = rawHTML
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let colon = inner.firstIndex(of: ":") else { return (nil, nil) }
        let key = String(inner[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
        let value = String(inner[inner.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

        switch key {
        case "type":
            return (value.isEmpty ? nil : value, nil)
        case "tags":
            let tags = value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return (nil, tags.isEmpty ? nil : tags)
        default:
            return (nil, nil)
        }
    }
}
