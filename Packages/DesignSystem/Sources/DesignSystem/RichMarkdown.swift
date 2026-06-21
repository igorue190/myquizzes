//
//  RichMarkdown.swift
//  DesignSystem
//
//  A small, Sendable presentation model for rich quiz content (code blocks,
//  tables, lists, images, inline formatting, and LaTeX math) plus the converter
//  that builds it from a Markdown string using Apple's swift-markdown. Lives in
//  DesignSystem so the renderer (RichText) is self-contained — callers just hand
//  it the raw Markdown that prompts/explanations already carry. Math (`$…$`,
//  `$$…$$`) is detected here since swift-markdown doesn't parse it.
//

import Foundation
import Markdown

// MARK: - Model

/// An inline run within a block.
public enum MarkdownInline: Sendable, Equatable, Hashable {
    case text(String)
    indirect case strong([MarkdownInline])
    indirect case emphasis([MarkdownInline])
    case code(String)
    indirect case link(String, [MarkdownInline])
    case image(source: String, alt: String)
    /// LaTeX math; `display` true ⇒ block/centered, false ⇒ inline.
    case math(String, display: Bool)
    case lineBreak
}

public enum TableColumnAlignment: Sendable, Equatable, Hashable {
    case leading, center, trailing
}

/// A block-level element.
public enum MarkdownBlock: Sendable, Equatable, Hashable {
    case paragraph([MarkdownInline])
    case heading(Int, [MarkdownInline])
    case codeBlock(language: String?, code: String)
    indirect case blockQuote([MarkdownBlock])
    case list(ordered: Bool, start: Int, items: [[MarkdownBlock]])
    case table(header: [[MarkdownInline]], rows: [[[MarkdownInline]]], alignments: [TableColumnAlignment])
    case thematicBreak
    case image(source: String, alt: String)
    case mathBlock(String)
}

// MARK: - Converter

public enum RichMarkdown {

    /// Parse Markdown into the renderable block model.
    public static func blocks(from markdown: String) -> [MarkdownBlock] {
        let document = Document(parsing: markdown)
        return document.children.flatMap { convertBlock($0) }
    }

    // MARK: Blocks

    private static func convertBlock(_ markup: Markup) -> [MarkdownBlock] {
        switch markup {
        case let paragraph as Paragraph:
            return [paragraphBlock(from: inlines(of: paragraph))]

        case let heading as Heading:
            return [.heading(heading.level, inlines(of: heading))]

        case let code as CodeBlock:
            let body = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
            return [.codeBlock(language: code.language, code: body)]

        case let quote as BlockQuote:
            return [.blockQuote(quote.children.flatMap { convertBlock($0) })]

        case let list as UnorderedList:
            return [.list(ordered: false, start: 1, items: listItems(list))]

        case let list as OrderedList:
            return [.list(ordered: true, start: Int(list.startIndex), items: listItems(list))]

        case let table as Markdown.Table:
            return [tableBlock(table)]

        case is ThematicBreak:
            return [.thematicBreak]

        default:
            let text = markup.format().trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [.paragraph([.text(text)])]
        }
    }

    /// Collapse a paragraph that is solely a display-math expression or a single
    /// image into a dedicated block; otherwise keep it a paragraph.
    private static func paragraphBlock(from runs: [MarkdownInline]) -> MarkdownBlock {
        let meaningful = runs.filter {
            if case let .text(t) = $0 { return !t.trimmingCharacters(in: .whitespaces).isEmpty }
            return true
        }
        if meaningful.count == 1 {
            if case let .math(latex, true) = meaningful[0] { return .mathBlock(latex) }
            if case let .image(source, alt) = meaningful[0] { return .image(source: source, alt: alt) }
        }
        return .paragraph(runs)
    }

    private static func listItems(_ list: Markup) -> [[MarkdownBlock]] {
        list.children
            .compactMap { $0 as? ListItem }
            .map { item in item.children.flatMap { convertBlock($0) } }
    }

    private static func tableBlock(_ table: Markdown.Table) -> MarkdownBlock {
        let alignments = table.columnAlignments.map { alignment -> TableColumnAlignment in
            switch alignment {
            case .center: return .center
            case .right:  return .trailing
            default:      return .leading
            }
        }
        let header = table.head.children.compactMap { ($0 as? Markdown.Table.Cell).map { inlines(of: $0) } }
        let rows = table.body.children.compactMap { row -> [[MarkdownInline]]? in
            guard let row = row as? Markdown.Table.Row else { return nil }
            return row.children.compactMap { ($0 as? Markdown.Table.Cell).map { inlines(of: $0) } }
        }
        return .table(header: header, rows: rows, alignments: alignments)
    }

    // MARK: Inlines

    private static func inlines(of markup: Markup) -> [MarkdownInline] {
        markup.children.flatMap { convertInline($0) }
    }

    private static func convertInline(_ markup: Markup) -> [MarkdownInline] {
        switch markup {
        case let text as Markdown.Text:
            return splitMath(text.string)
        case let strong as Strong:
            return [.strong(inlines(of: strong))]
        case let emphasis as Emphasis:
            return [.emphasis(inlines(of: emphasis))]
        case let code as InlineCode:
            return [.code(code.code)]
        case let link as Markdown.Link:
            return [.link(link.destination ?? "", inlines(of: link))]
        case let image as Markdown.Image:
            return [.image(source: image.source ?? "", alt: plainText(of: image))]
        case let strike as Strikethrough:
            return inlines(of: strike)
        case is LineBreak:
            return [.lineBreak]
        case is SoftBreak:
            return [.text(" ")]
        default:
            return splitMath(plainText(of: markup))
        }
    }

    /// Recursively concatenate the text of an inline subtree (no Markdown syntax).
    private static func plainText(of markup: Markup) -> String {
        if let text = markup as? Markdown.Text { return text.string }
        return markup.children.map { plainText(of: $0) }.joined()
    }

    /// Split a plain string into text and LaTeX-math runs on `$…$` / `$$…$$`.
    static func splitMath(_ string: String) -> [MarkdownInline] {
        guard string.contains("$") else { return string.isEmpty ? [] : [.text(string)] }
        let chars = Array(string)
        var result: [MarkdownInline] = []
        var buffer = ""
        var i = 0
        func flush() { if !buffer.isEmpty { result.append(.text(buffer)); buffer = "" } }

        while i < chars.count {
            if chars[i] == "$" {
                let display = (i + 1 < chars.count && chars[i + 1] == "$")
                let delimLen = display ? 2 : 1
                var j = i + delimLen
                var close = -1
                while j < chars.count {
                    if chars[j] == "$" {
                        if display {
                            if j + 1 < chars.count && chars[j + 1] == "$" { close = j; break }
                            j += 1; continue
                        }
                        close = j; break
                    }
                    j += 1
                }
                if close >= 0 {
                    let latex = String(chars[(i + delimLen)..<close])
                    if !latex.trimmingCharacters(in: .whitespaces).isEmpty {
                        flush()
                        result.append(.math(latex, display: display))
                        i = close + delimLen
                        continue
                    }
                }
            }
            buffer.append(chars[i])
            i += 1
        }
        flush()
        return result
    }
}
