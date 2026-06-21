//
//  VocabularyTests.swift
//  CoreModelsTests
//

import Testing
import Foundation
@testable import CoreModels

@Suite("Vocabulary value types")
struct VocabularyTests {

    @Test("Language label round-trips through its parsing init")
    func languageLabel() {
        let lang = Language(code: "hr", displayName: "Croatian")
        #expect(lang.label == "Croatian (hr)")
        #expect(Language(label: "Croatian (hr)") == lang)
        // A bare name has no code.
        #expect(Language(label: "Esperanto") == Language(code: "", displayName: "Esperanto"))
    }

    @Test("Entry prompt/answer follow the direction")
    func directionMapping() {
        let entry = VocabularyEntry(id: 0, term: "hvala", translation: "thanks")
        #expect(entry.prompt(for: .foreignToNative) == "hvala")
        #expect(entry.answer(for: .foreignToNative) == "thanks")
        #expect(entry.prompt(for: .nativeToForeign) == "thanks")
        #expect(entry.answer(for: .nativeToForeign) == "hvala")
    }

    @Test("usableEntries drops half-empty rows")
    func usableEntries() {
        let set = VocabularySet(
            title: "S", foreignLanguage: .croatian, nativeLanguage: .english,
            entries: [
                VocabularyEntry(id: 0, term: "a", translation: "x"),
                VocabularyEntry(id: 1, term: "", translation: "y"),
                VocabularyEntry(id: 2, term: "c", translation: "")
            ]
        )
        #expect(set.usableEntries.map(\.id) == [0])
    }

    @Test("ParseSummary from a set is the vocabulary kind")
    func summaryKind() {
        let set = VocabularySet(title: "S", foreignLanguage: .croatian, nativeLanguage: .english,
                                entries: [VocabularyEntry(id: 0, term: "a", translation: "x")])
        let summary = ParseSummary(set)
        #expect(summary.kind == .vocabulary)
        #expect(summary.questionCount == 1)
    }

    @Test("ParseSummary decodes legacy JSON (no kind) as .quiz")
    func summaryMigration() throws {
        let legacy = #"{"questionCount":5,"warningCount":1,"errorCount":0}"#
        let summary = try JSONDecoder().decode(ParseSummary.self, from: Data(legacy.utf8))
        #expect(summary.kind == .quiz)
        #expect(summary.questionCount == 5)
    }

    @Test("InMemoryVocabReviewRepository stores and clears per file")
    func reviewRepository() async throws {
        let repo = InMemoryVocabReviewRepository()
        let file = UUID()
        try await repo.save(CardReviewState(entryID: 0, box: 2), forFile: file)
        try await repo.save(CardReviewState(entryID: 1, box: 1), forFile: file)
        #expect(try await repo.states(forFile: file).count == 2)
        try await repo.clear(forFile: file)
        #expect(try await repo.states(forFile: file).isEmpty)
    }
}
