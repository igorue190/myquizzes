//
//  RichText.swift
//  DesignSystem
//
//  The rich-content renderer: turns a Markdown string into SwiftUI, supporting
//  code blocks, tables, lists, block quotes, images (remote+cached and data: URIs),
//  inline formatting, and LaTeX math (via KaTeX in MathView). Drop-in replacement
//  for MarkdownText wherever quiz content can be rich (prompts, explanations).
//  Inline-only text still renders as a native `Text` so it scales with Dynamic Type.
//

import SwiftUI

public struct RichText: View {
    private let blocks: [MarkdownBlock]
    private let baseFont: Font

    public init(_ markdown: String, baseFont: Font = Typography.body) {
        self.blocks = RichMarkdown.blocks(from: markdown)
        self.baseFont = baseFont
    }

    public var body: some View {
        RichBlocksView(blocks: blocks, baseFont: baseFont)
    }
}

// MARK: - Block list

struct RichBlocksView: View {
    let blocks: [MarkdownBlock]
    var baseFont: Font = Typography.body

    @Environment(\.colorScheme) private var colorScheme

    private var mathColorHex: String { colorScheme == .dark ? "#FFFFFF" : "#000000" }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .paragraph(inlines):
            if inlines.containsMath {
                MathView(html: KaTeXAssets.document(body: "<div>\(InlineHTML.render(inlines))</div>", colorHex: mathColorHex))
            } else {
                Text(InlineAttributed.render(inlines))
                    .font(baseFont)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .heading(level, inlines):
            Text(InlineAttributed.render(inlines))
                .font(headingFont(level))
                .fixedSize(horizontal: false, vertical: true)

        case let .codeBlock(language, code):
            codeBlock(language: language, code: code)

        case let .blockQuote(children):
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 2).fill(ColorTokens.brand.opacity(0.5)).frame(width: 3)
                RichBlocksView(blocks: children, baseFont: baseFont)
            }

        case let .list(ordered, start, items):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Text(ordered ? "\(start + index)." : "•")
                            .font(baseFont)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        RichBlocksView(blocks: item, baseFont: baseFont)
                    }
                }
            }

        case let .table(header, rows, alignments):
            RichTableView(header: header, rows: rows, alignments: alignments, baseFont: baseFont)

        case .thematicBreak:
            Divider()

        case let .image(source, alt):
            RichImageView(source: source, alt: alt)

        case let .mathBlock(latex):
            MathView(html: KaTeXAssets.document(
                body: "<div class=\"kx-display\"><span data-tex=\"\(InlineHTML.escapeAttribute(latex))\" data-display=\"1\"></span></div>",
                colorHex: mathColorHex
            ))
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return Typography.title
        case 2: return Typography.headline
        default: return Typography.body.weight(.semibold)
        }
    }

    private func codeBlock(language: String?, code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(ColorTokens.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Table

private struct RichTableView: View {
    let header: [[MarkdownInline]]
    let rows: [[[MarkdownInline]]]
    let alignments: [TableColumnAlignment]
    let baseFont: Font

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.sm) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { index, cell in
                        Text(InlineAttributed.render(cell))
                            .font(baseFont.weight(.semibold))
                            .gridColumnAlignment(alignment(index))
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(InlineAttributed.render(cell)).font(baseFont)
                        }
                    }
                }
            }
            .padding(Spacing.md)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(ColorTokens.hairline, lineWidth: 1)
        )
    }

    private func alignment(_ index: Int) -> HorizontalAlignment {
        guard alignments.indices.contains(index) else { return .leading }
        switch alignments[index] {
        case .center:   return .center
        case .trailing: return .trailing
        case .leading:  return .leading
        }
    }
}

// MARK: - Image

private struct RichImageView: View {
    let source: String
    let alt: String

    var body: some View {
        if source.hasPrefix("data:"), let image = Self.decodeDataURI(source) {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else if let url = URL(string: source), url.scheme == "http" || url.scheme == "https" {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                case .failure:
                    fallback
                case .empty:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
            .font(Typography.caption)
            .foregroundStyle(.secondary)
    }

    private static func decodeDataURI(_ string: String) -> UIImage? {
        guard let comma = string.firstIndex(of: ","),
              let data = Data(base64Encoded: String(string[string.index(after: comma)...]))
        else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Inline rendering

private extension Array where Element == MarkdownInline {
    var containsMath: Bool {
        contains { inline in
            switch inline {
            case .math: return true
            case let .strong(c), let .emphasis(c): return c.containsMath
            case let .link(_, c): return c.containsMath
            default: return false
            }
        }
    }
}

/// Builds an `AttributedString` for non-math inline runs (scales with Dynamic Type).
enum InlineAttributed {
    static func render(_ inlines: [MarkdownInline]) -> AttributedString {
        var result = AttributedString()
        for inline in inlines { result.append(run(inline)) }
        return result
    }

    private static func run(_ inline: MarkdownInline) -> AttributedString {
        switch inline {
        case let .text(text):
            return AttributedString(text)
        case let .strong(children):
            var a = render(children); a.inlinePresentationIntent = .stronglyEmphasized; return a
        case let .emphasis(children):
            var a = render(children); a.inlinePresentationIntent = .emphasized; return a
        case let .code(code):
            var a = AttributedString(code); a.inlinePresentationIntent = .code; return a
        case let .link(url, children):
            var a = render(children)
            if let u = URL(string: url) { a.link = u }
            a.foregroundColor = ColorTokens.brand
            return a
        case let .image(_, alt):
            return AttributedString(alt)
        case let .math(latex, _):
            return AttributedString(latex)   // only reached if a math run sneaks past containsMath
        case .lineBreak:
            return AttributedString("\n")
        }
    }
}

/// Builds an HTML fragment for inline runs, for the KaTeX web view.
enum InlineHTML {
    static func render(_ inlines: [MarkdownInline]) -> String {
        inlines.map(run).joined()
    }

    private static func run(_ inline: MarkdownInline) -> String {
        switch inline {
        case let .text(text):       return escape(text)
        case let .strong(c):        return "<strong>\(render(c))</strong>"
        case let .emphasis(c):      return "<em>\(render(c))</em>"
        case let .code(code):       return "<code>\(escape(code))</code>"
        case let .link(url, c):     return "<a href=\"\(escapeAttribute(url))\">\(render(c))</a>"
        case let .image(src, alt):  return "<img src=\"\(escapeAttribute(src))\" alt=\"\(escapeAttribute(alt))\" style=\"max-width:100%\">"
        case let .math(latex, d):   return "<span data-tex=\"\(escapeAttribute(latex))\" data-display=\"\(d ? "1" : "0")\"></span>"
        case .lineBreak:            return "<br>"
        }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ s: String) -> String {
        escape(s).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
