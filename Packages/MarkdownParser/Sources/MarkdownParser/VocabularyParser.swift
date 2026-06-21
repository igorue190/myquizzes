//
//  VocabularyParser.swift
//  MarkdownParser
//
//  Parses the canonical Markdown vocab format into a `VocabularySet` — the
//  inverse of `VocabularyRenderer`. Like `MarkdownQuizParser` it never throws:
//  malformed rows are skipped rather than failing the file. Reuses `FrontMatter`
//  for the `---` block but reads the vocab-specific keys (`kind`, `foreign`,
//  `native`) itself, and parses the pipe table by hand (no swift-markdown table
//  AST) so an escaped `\|` inside a cell survives. `isVocabulary` lets the import
//  pipeline branch a document to the vocab path vs. the quiz parser.
//

import CoreModels
import Foundation

public struct VocabularyParser: Sendable {

    public init() {}

    /// Whether a document declares itself a vocabulary file (`kind: vocabulary`).
    /// Cheap front-matter-only check used to route imports.
    public static func isVocabulary(_ source: String) -> Bool {
        let (frontMatter, _) = FrontMatter.split(source)
        return frontMatterKeys(frontMatter)["kind"]?.lowercased() == "vocabulary"
    }

    /// Parse a vocabulary document. Returns `nil` when the file isn't a
    /// vocabulary file, so callers can fall back to the quiz parser.
    public func parse(_ source: String) -> VocabularySet? {
        let (frontMatter, body) = FrontMatter.split(source)
        let keys = Self.frontMatterKeys(frontMatter)
        guard keys["kind"]?.lowercased() == "vocabulary" else { return nil }

        let title = keys["title"] ?? "Vocabulary"
        let foreign = Language(label: keys["foreign"] ?? "")
        let native = Language(label: keys["native"] ?? "")
        let entries = Self.parseTable(body)

        return VocabularySet(
            title: title,
            foreignLanguage: foreign,
            nativeLanguage: native,
            entries: entries
        )
    }

    // MARK: - Front matter

    /// Read the flat `key: value` front-matter block into a lowercased-key map.
    static func frontMatterKeys(_ block: String?) -> [String: String] {
        guard let block else { return [:] }
        var keys: [String: String] = [:]
        for rawLine in block.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { continue }
            keys[key] = value
        }
        return keys
    }

    // MARK: - Table

    /// Parse the pipe table in the body into entries. Tolerates an optional header
    /// row (detected by a following `---` separator) and maps columns by header
    /// name when present, otherwise positionally (term, translation, phonetic,
    /// transcription, example). Rows missing both a term and a translation are
    /// skipped.
    static func parseTable(_ body: String) -> [VocabularyEntry] {
        let rows = body
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("|") }

        guard !rows.isEmpty else { return [] }

        var cells = rows.map(splitRow)
        var columnOrder = ["term", "translation", "phonetic", "transcription", "example"]

        // A header row exists when the second table line is a separator (---/:--).
        if cells.count >= 2, isSeparatorRow(cells[1]) {
            columnOrder = cells[0].map(columnKey)
            cells.removeFirst(2)
        } else if cells.count >= 1, isSeparatorRow(cells[0]) {
            cells.removeFirst()
        }

        var entries: [VocabularyEntry] = []
        for row in cells {
            let fields = mapFields(row, order: columnOrder)
            let term = fields["term"] ?? ""
            let translation = fields["translation"] ?? ""
            guard !term.isEmpty || !translation.isEmpty else { continue }
            entries.append(VocabularyEntry(
                id: entries.count,
                term: term,
                translation: translation,
                phonetic: nonEmpty(fields["phonetic"]),
                transcription: nonEmpty(fields["transcription"]),
                example: nonEmpty(fields["example"])
            ))
        }
        return entries
    }

    /// Split a table row on unescaped pipes, dropping the empty cells produced by
    /// the leading/trailing `|`, and unescape `\|` back to `|`.
    private static func splitRow(_ row: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for char in row {
            if escaped {
                current.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        // Drop the empty leading/trailing cells from the surrounding pipes.
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }

    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
        }
    }

    /// Map a header cell to a known column key, defaulting to "term" so an
    /// unrecognized first column still captures the foreign word.
    private static func columnKey(_ header: String) -> String {
        switch header.lowercased() {
        // Checked before "translation"/"phonetic" so a "Transcription" header maps
        // to its own column rather than being grabbed by a substring match.
        case let h where h.contains("transcription") || h.contains("cyrillic") || h.contains("reading"): "transcription"
        case let h where h.contains("term") || h.contains("word") || h.contains("foreign"): "term"
        case let h where h.contains("translation") || h.contains("meaning") || h.contains("native"): "translation"
        case let h where h.contains("pronunciation") || h.contains("phonetic") || h.contains("ipa"): "phonetic"
        case let h where h.contains("example") || h.contains("sentence") || h.contains("usage"): "example"
        default: "term"
        }
    }

    private static func mapFields(_ row: [String], order: [String]) -> [String: String] {
        var fields: [String: String] = [:]
        for (index, value) in row.enumerated() where index < order.count {
            // First wins, so a duplicate "term" header doesn't clobber the real one.
            if fields[order[index]] == nil { fields[order[index]] = value }
        }
        return fields
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
