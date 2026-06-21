//
//  RichMarkdownTests.swift
//  DesignSystemTests
//
//  Covers the Markdown → block-model converter, especially the math detection
//  (which swift-markdown doesn't do) and the block shapes the renderer relies on.
//

import Testing
@testable import DesignSystem

@Suite("RichMarkdown converter")
struct RichMarkdownTests {

    @Test("inline math splits text into text + math runs")
    func inlineMath() {
        let runs = RichMarkdown.splitMath("Euler: $e^{i\\pi}+1=0$ is neat")
        #expect(runs.count == 3)
        guard case let .math(latex, display) = runs[1] else { Issue.record("expected math"); return }
        #expect(latex == "e^{i\\pi}+1=0")
        #expect(display == false)
    }

    @Test("display math uses $$ delimiters")
    func displayMath() {
        let runs = RichMarkdown.splitMath("$$x^2$$")
        #expect(runs.count == 1)
        guard case let .math(_, display) = runs[0] else { Issue.record("expected math"); return }
        #expect(display == true)
    }

    @Test("a lone $$…$$ paragraph becomes a math block")
    func mathBlockPromotion() {
        let blocks = RichMarkdown.blocks(from: "$$\\frac{a}{b}$$")
        #expect(blocks.count == 1)
        guard case let .mathBlock(latex) = blocks[0] else { Issue.record("expected mathBlock"); return }
        #expect(latex.contains("frac"))
    }

    @Test("fenced code block keeps language and body")
    func codeBlock() {
        let blocks = RichMarkdown.blocks(from: "```swift\nlet x = 1\n```")
        guard case let .codeBlock(language, code) = blocks.first else { Issue.record("expected codeBlock"); return }
        #expect(language == "swift")
        #expect(code == "let x = 1")
    }

    @Test("GFM table parses header, rows, and alignment")
    func table() {
        let md = """
        | A | B |
        |:--|--:|
        | 1 | 2 |
        """
        let blocks = RichMarkdown.blocks(from: md)
        guard case let .table(header, rows, alignments) = blocks.first else { Issue.record("expected table"); return }
        #expect(header.count == 2)
        #expect(rows.count == 1)
        #expect(alignments == [.leading, .trailing])
    }

    @Test("an image-only paragraph becomes an image block")
    func image() {
        let blocks = RichMarkdown.blocks(from: "![alt](https://example.com/x.png)")
        guard case let .image(source, alt) = blocks.first else { Issue.record("expected image"); return }
        #expect(source == "https://example.com/x.png")
        #expect(alt == "alt")
    }

    @Test("unordered list yields items")
    func list() {
        let blocks = RichMarkdown.blocks(from: "- one\n- two")
        guard case let .list(ordered, _, items) = blocks.first else { Issue.record("expected list"); return }
        #expect(ordered == false)
        #expect(items.count == 2)
    }
}
