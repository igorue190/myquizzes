//
//  VocabularyRenderer.swift
//  MarkdownParser
//
//  Renders a `VocabularySet` into the canonical Markdown vocab format: front
//  matter (`kind: vocabulary`, title, the two languages) followed by a pipe
//  table of pairs. The exact inverse of `VocabularyParser`, so a set round-trips
//  losslessly — which is what lets a vocab set ride the existing import / Library
//  / Backup machinery as a plain `.md` file. The AI service and the copy-paste
//  settings prompt both emit this same shape.
//

import CoreModels
import Foundation

public struct VocabularyRenderer: Sendable {

    public init() {}

    public func render(_ set: VocabularySet) -> String {
        var out: [String] = []
        out.append("---")
        out.append("kind: vocabulary")
        out.append("title: \(singleLine(set.title.isEmpty ? "Vocabulary" : set.title))")
        out.append("foreign: \(singleLine(set.foreignLanguage.label))")
        out.append("native: \(singleLine(set.nativeLanguage.label))")
        out.append("---")
        out.append("")
        out.append("| Term | Translation | Pronunciation | Transcription | Example |")
        out.append("|------|-------------|---------------|---------------|---------|")
        for entry in set.entries {
            let cells = [
                cell(entry.term),
                cell(entry.translation),
                cell(entry.phonetic ?? ""),
                cell(entry.transcription ?? ""),
                cell(entry.example ?? "")
            ]
            out.append("| \(cells.joined(separator: " | ")) |")
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: - Cell escaping

    /// Make a value safe inside a single table cell: collapse newlines and escape
    /// the pipe so the column structure survives a parse round-trip.
    private func cell(_ value: String) -> String {
        singleLine(value).replacingOccurrences(of: "|", with: "\\|")
    }

    /// Collapse any newlines to spaces so a value stays on one line.
    private func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
