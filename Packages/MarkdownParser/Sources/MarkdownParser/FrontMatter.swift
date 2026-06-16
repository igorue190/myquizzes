//
//  FrontMatter.swift
//  MarkdownParser
//
//  swift-markdown does not understand YAML front matter, so we split it off
//  before handing the body to the AST parser. The format spec (§5.1) only uses
//  flat `key: value` pairs, so a tiny hand-rolled reader is enough — no YAML
//  dependency. Unknown keys are ignored; malformed values fall back to defaults.
//

import CoreModels
import Foundation

enum FrontMatter {

    /// Split a document into its (optional) front-matter block and the Markdown
    /// body. Front matter must be the very first thing in the file, fenced by
    /// `---` lines.
    static func split(_ source: String) -> (frontMatter: String?, body: String) {
        // Normalize newlines so the scanner is platform-agnostic.
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") || normalized == "---" else {
            return (nil, source)
        }

        let lines = normalized.components(separatedBy: "\n")
        // lines[0] == "---". Find the closing fence.
        guard let closingIndex = lines.dropFirst().firstIndex(of: "---") else {
            return (nil, source)   // no closing fence → treat whole file as body
        }

        let fmLines = lines[1..<closingIndex]
        let bodyLines = lines[(closingIndex + 1)...]
        return (fmLines.joined(separator: "\n"), bodyLines.joined(separator: "\n"))
    }

    /// Parse the front-matter block into metadata, applying defaults for keys
    /// that are absent or unparseable.
    static func parse(_ block: String?) -> QuizMetadata {
        var meta = QuizMetadata()
        guard let block else { return meta }

        for rawLine in block.components(separatedBy: "\n") {
            // Strip trailing comments and whitespace.
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let colon = line.firstIndex(of: ":") else { continue }

            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            // Drop an inline `# comment` and surrounding quotes.
            if let hash = value.firstIndex(of: "#") {
                value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { continue }

            switch key {
            case "title":            meta.title = value
            case "category":         meta.category = value
            case "topic":            meta.topic = value
            case "difficulty":       meta.difficulty = Difficulty(rawValue: value.lowercased())
            case "passthreshold":    meta.passThreshold = Int(value) ?? meta.passThreshold
            case "shufflequestions": meta.shuffleQuestions = parseBool(value) ?? meta.shuffleQuestions
            case "shuffleanswers":   meta.shuffleAnswers = parseBool(value) ?? meta.shuffleAnswers
            default:                 break
            }
        }
        return meta
    }

    private static func parseBool(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "true", "yes", "on", "1":  true
        case "false", "no", "off", "0": false
        default:                        nil
        }
    }
}
