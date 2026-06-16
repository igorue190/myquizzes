//
//  main.swift
//  myquizzes — command-line demo
//
//  A runnable demonstration of Markwise's pure core on a plain macOS toolchain:
//  parse a Markdown quiz, surface diagnostics, run an Exam session against a
//  simulated test-taker, and print a Microsoft-style score report + review.
//
//  Usage:
//      myquizzes [path/to/quiz.md]
//
//  With no argument it parses the bundled Samples/AZ-900.md (falling back to a
//  small embedded quiz if the file can't be found).
//

import Foundation
import CoreModels
import MarkdownParser
import QuizEngine

// MARK: - Load source

func loadSource() -> (label: String, markdown: String) {
    if CommandLine.arguments.count > 1 {
        let path = CommandLine.arguments[1]
        if let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return (path, text)
        }
        FileHandle.standardError.write(Data("warning: could not read \(path); using embedded sample\n".utf8))
    }
    // Try the bundled sample relative to the working directory.
    for candidate in ["Samples/AZ-900.md", "./Samples/AZ-900.md"] {
        if let text = try? String(contentsOfFile: candidate, encoding: .utf8) {
            return (candidate, text)
        }
    }
    return ("<embedded>", embeddedSample)
}

let embeddedSample = """
## Which model gives the most control over the OS?
<!-- type: single -->
- [ ] SaaS
- [x] IaaS
- [ ] PaaS

> **Explanation:** IaaS exposes the VM and OS to the customer.
"""

// MARK: - Tiny terminal helpers

/// Strip the most common inline Markdown markers for plain-text terminal output.
func plain(_ s: String) -> String {
    s.replacingOccurrences(of: "**", with: "")
     .replacingOccurrences(of: "`", with: "")
     .replacingOccurrences(of: "*", with: "")
}

func rule(_ title: String = "") {
    if title.isEmpty { print(String(repeating: "─", count: 64)) }
    else { print("── \(title) " + String(repeating: "─", count: max(0, 60 - title.count))) }
}

// MARK: - Run

let (label, markdown) = loadSource()
let parser = MarkdownQuizParser()
let quiz = parser.parse(markdown)

rule("MARKWISE  ·  \(quiz.metadata.title ?? label)")
if let category = quiz.metadata.category, let topic = quiz.metadata.topic {
    print("\(category)  ›  \(topic)")
}
print("Parsed \(quiz.questions.count) question(s) · \(quiz.usableQuestions.count) usable · pass ≥ \(quiz.metadata.passThreshold)%")
print()

// Diagnostics
if quiz.diagnostics.isEmpty {
    print("✓ No diagnostics.")
} else {
    print("Diagnostics:")
    for d in quiz.diagnostics {
        let mark = switch d.severity {
        case .error: "✗ error  "
        case .warning: "! warning"
        case .info: "i info   "
        }
        print("  \(mark)  \(plain(d.message))")
    }
}
print()

// Build and run an Exam session over the usable questions.
let config = SessionConfig(mode: .exam, passThreshold: quiz.metadata.passThreshold, seed: 2026)
var session = SessionPlanner.makeSession(from: quiz.usableQuestions, config: config)
session.start()

// Simulated test-taker: answers every question correctly except the last.
for (i, q) in session.questions.enumerated() {
    if i == session.count - 1, let wrong = q.choices.first(where: { !$0.isCorrect }) {
        session.select(choiceID: wrong.id, in: q.id)
    } else {
        for choice in q.choices where choice.isCorrect {
            session.select(choiceID: choice.id, in: q.id)
        }
    }
}
session.submit()

let result = Scorer.score(session)

rule("SCORE REPORT")
let verdict = result.passed ? "PASS ✓" : "FAIL ✗"
print("\(Int(result.percentage.rounded()))%   (\(result.correctCount)/\(result.totalQuestions) correct)   →   \(verdict)")
if !result.topicBreakdown.isEmpty {
    print("\nBy topic:")
    for topic in result.topicBreakdown {
        let name = topic.topic.padding(toLength: 18, withPad: " ", startingAt: 0)
        let pct = Int((topic.accuracy * 100).rounded())
        print("  \(name) \(topic.correct)/\(topic.total)  (\(pct)%)")
    }
}
print()

rule("REVIEW")
session.openReview()
func labels(_ q: Question, _ ids: Set<Int>) -> String {
    let texts = q.choices.filter { ids.contains($0.id) }.map { plain($0.text) }
    return texts.isEmpty ? "(none)" : texts.joined(separator: ", ")
}
for attempt in result.attempts {
    guard let q = session.questions.first(where: { $0.id == attempt.questionID }) else { continue }
    let mark = attempt.isCorrect ? "✓" : "✗"
    print("\(mark) Q\(attempt.questionID + 1). \(plain(q.prompt))")
    print("    your answer:    \(labels(q, attempt.selectedChoiceIDs))")
    if !attempt.isCorrect {
        print("    correct answer: \(labels(q, attempt.correctChoiceIDs))")
    }
    if let explanation = q.explanation {
        print("    explanation:    \(plain(explanation))")
    }
    print()
}
