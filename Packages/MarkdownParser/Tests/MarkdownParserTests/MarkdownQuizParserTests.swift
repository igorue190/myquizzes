//
//  MarkdownQuizParserTests.swift
//  MarkdownParserTests
//
//  Fixture-driven tests for the format spec (§5): every question type, type
//  inference, front matter, and each diagnostic. The parser must be tolerant —
//  bad content becomes diagnostics, never a crash or a thrown error.
//

import Testing
import CoreModels
@testable import MarkdownParser

@Suite("MarkdownQuizParser — format spec")
struct MarkdownQuizParserTests {

    let parser = MarkdownQuizParser()

    // MARK: Front matter

    @Test("YAML front matter populates metadata and is stripped from the body")
    func frontMatter() {
        let md = """
        ---
        title: AZ-900 — Azure Fundamentals
        category: Microsoft Azure
        topic: Cloud Concepts
        difficulty: beginner
        passThreshold: 80
        shuffleQuestions: true
        shuffleAnswers: false
        ---

        ## Is the sky blue?
        - [x] Yes
        - [ ] No
        """
        let quiz = parser.parse(md)
        #expect(quiz.metadata.title == "AZ-900 — Azure Fundamentals")
        #expect(quiz.metadata.category == "Microsoft Azure")
        #expect(quiz.metadata.topic == "Cloud Concepts")
        #expect(quiz.metadata.difficulty == .beginner)
        #expect(quiz.metadata.passThreshold == 80)
        #expect(quiz.metadata.shuffleQuestions == true)
        #expect(quiz.metadata.shuffleAnswers == false)
        #expect(quiz.questions.count == 1)
        #expect(quiz.questions[0].prompt == "Is the sky blue?")
    }

    @Test("A file with no front matter still parses with default metadata")
    func noFrontMatter() {
        let quiz = parser.parse("## Q\n- [x] A\n- [ ] B\n")
        #expect(quiz.metadata.passThreshold == 70)   // default
        #expect(quiz.questions.count == 1)
    }

    // MARK: Question types

    @Test("Single-answer question parses choices and the correct one")
    func singleAnswer() {
        let md = """
        ## Which model gives the most control over the OS?
        <!-- type: single -->

        - [ ] SaaS
        - [ ] PaaS
        - [x] IaaS
        - [ ] FaaS

        > **Explanation:** IaaS exposes the VM and OS to the customer.
        > **Reference:** https://learn.microsoft.com/azure/
        """
        let quiz = parser.parse(md)
        let q = quiz.questions[0]
        #expect(q.type == .single)
        #expect(q.choices.count == 4)
        #expect(q.choices.map(\.text) == ["SaaS", "PaaS", "IaaS", "FaaS"])
        #expect(q.correctChoiceIDs == [2])
        #expect(q.explanation?.contains("IaaS exposes") == true)
        #expect(q.reference == "https://learn.microsoft.com/azure/")
        #expect(quiz.diagnostics.isEmpty)
    }

    @Test("Multiple-answer question keeps inline Markdown in labels")
    func multipleAnswer() {
        let md = """
        ## Which are characteristics of elasticity? (Choose two.)
        <!-- type: multiple -->
        - [x] Resources scale out **automatically**
        - [x] You pay only for what you consume
        - [ ] Capacity is fixed at provisioning time
        """
        let quiz = parser.parse(md)
        let q = quiz.questions[0]
        #expect(q.type == .multiple)
        #expect(q.correctChoiceIDs == [0, 1])
        #expect(q.choices[0].text.contains("**automatically**"))   // formatting preserved
    }

    @Test("True/False is inferred from a True/False choice pair without a hint")
    func trueFalseInference() {
        let md = """
        ## Availability Zones protect against a full region outage.
        - [ ] True
        - [x] False
        """
        let quiz = parser.parse(md)
        #expect(quiz.questions[0].type == .trueFalse)
        #expect(quiz.questions[0].correctChoiceIDs == [1])
    }

    @Test("Type is inferred: one correct → single, two+ correct → multiple")
    func typeInference() {
        let single = parser.parse("## Q\n- [x] A\n- [ ] B\n- [ ] C\n")
        #expect(single.questions[0].type == .single)
        let multiple = parser.parse("## Q\n- [x] A\n- [x] B\n- [ ] C\n")
        #expect(multiple.questions[0].type == .multiple)
    }

    @Test("Per-question tags are read from a tags comment")
    func tags() {
        let md = """
        ## Q
        <!-- tags: networking, security -->
        - [x] A
        - [ ] B
        """
        #expect(parser.parse(md).questions[0].tags == ["networking", "security"])
    }

    // MARK: Diagnostics

    @Test("No correct answer is an error and disqualifies the question")
    func noCorrectAnswer() {
        let md = "## Q\n- [ ] A\n- [ ] B\n"
        let quiz = parser.parse(md)
        let diag = quiz.diagnostics.first { $0.kind == .noCorrectAnswer }
        #expect(diag != nil)
        #expect(diag?.severity == .error)
        #expect(quiz.usableQuestions.isEmpty)        // error → not usable
        #expect(quiz.questions.count == 1)           // but still present for display
    }

    @Test("All-correct and duplicate answers are warnings, not disqualifying")
    func warnings() {
        let md = "## Q\n- [x] Same\n- [x] Same\n"
        let quiz = parser.parse(md)
        let kinds = Set(quiz.diagnostics.map(\.kind))
        #expect(kinds.contains(.allAnswersCorrect))
        #expect(kinds.contains(.duplicateAnswers))
        #expect(quiz.diagnostics.allSatisfy { $0.severity == .warning })
        #expect(quiz.usableQuestions.count == 1)     // warnings keep it usable
    }

    @Test("A declared type that disagrees with the correct count warns")
    func typeMismatch() {
        let md = """
        ## Q
        <!-- type: single -->
        - [x] A
        - [x] B
        """
        let quiz = parser.parse(md)
        #expect(quiz.diagnostics.contains { $0.kind == .typeCountMismatch })
    }

    @Test("A malformed type hint warns and falls back to inference")
    func malformedType() {
        let md = """
        ## Q
        <!-- type: bogus -->
        - [x] A
        - [ ] B
        """
        let quiz = parser.parse(md)
        #expect(quiz.diagnostics.contains { $0.kind == .malformedTypeHint })
        #expect(quiz.questions[0].type == .single)   // inferred
    }

    @Test("Multiple questions get stable ascending ids matching diagnostics")
    func multipleQuestions() {
        let md = """
        ## First
        - [x] A
        - [ ] B

        ## Second (broken)
        - [ ] A
        - [ ] B

        ## Third
        - [x] A
        - [ ] B
        """
        let quiz = parser.parse(md)
        #expect(quiz.questions.map(\.id) == [0, 1, 2])
        let errorIndex = quiz.diagnostics.first { $0.severity == .error }?.questionIndex
        #expect(errorIndex == 1)
        #expect(quiz.usableQuestions.map(\.id) == [0, 2])
    }
}
