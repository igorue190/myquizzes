//
//  VocabularyParserTests.swift
//  MarkdownParserTests
//

import Testing
import CoreModels
@testable import MarkdownParser

private let vocabDoc = """
---
kind: vocabulary
title: Croatian — Travel Basics
foreign: Croatian (hr)
native: Russian (ru)
---

| Term | Translation | Pronunciation | Transcription | Example |
|------|-------------|---------------|---------------|---------|
| dobar dan | добрый день | DOH-bar dahn | добар дан | Dobar dan, kako ste? |
| hvala | спасибо |  |  |  |
"""

@Suite("VocabularyParser")
struct VocabularyParserTests {

    @Test("Detects a vocabulary file by its front matter")
    func detection() {
        #expect(VocabularyParser.isVocabulary(vocabDoc))
        #expect(!VocabularyParser.isVocabulary("## A quiz question\n- [x] yes\n- [ ] no"))
    }

    @Test("Parses front matter, languages, and table rows")
    func parses() throws {
        let set = try #require(VocabularyParser().parse(vocabDoc))
        #expect(set.title == "Croatian — Travel Basics")
        #expect(set.foreignLanguage == Language(code: "hr", displayName: "Croatian"))
        #expect(set.nativeLanguage == Language(code: "ru", displayName: "Russian"))
        #expect(set.entries.count == 2)
        #expect(set.entries[0].term == "dobar dan")
        #expect(set.entries[0].translation == "добрый день")
        #expect(set.entries[0].phonetic == "DOH-bar dahn")
        #expect(set.entries[0].transcription == "добар дан")
        #expect(set.entries[0].example == "Dobar dan, kako ste?")
        // Empty optional cells become nil.
        #expect(set.entries[1].phonetic == nil)
        #expect(set.entries[1].transcription == nil)
        #expect(set.entries[1].example == nil)
        // Ids are zero-based and contiguous.
        #expect(set.entries.map(\.id) == [0, 1])
    }

    @Test("A non-vocabulary document returns nil")
    func notVocabulary() {
        #expect(VocabularyParser().parse("## Q\n- [x] a\n- [ ] b") == nil)
    }

    @Test("Render → parse round-trips losslessly")
    func roundTrip() throws {
        let original = VocabularySet(
            title: "My Set",
            foreignLanguage: .croatian,
            nativeLanguage: .russian,
            entries: [
                VocabularyEntry(id: 0, term: "pas", translation: "собака", phonetic: "pahs", transcription: "пас", example: "Moj pas."),
                VocabularyEntry(id: 1, term: "mačka", translation: "кошка")
            ]
        )
        let markdown = VocabularyRenderer().render(original)
        let reparsed = try #require(VocabularyParser().parse(markdown))
        #expect(reparsed == original)
    }

    @Test("Pipes inside a cell survive the round-trip")
    func escapedPipe() throws {
        let original = VocabularySet(
            title: "Edge",
            foreignLanguage: .english,
            nativeLanguage: .russian,
            entries: [VocabularyEntry(id: 0, term: "a | b", translation: "и")]
        )
        let reparsed = try #require(VocabularyParser().parse(VocabularyRenderer().render(original)))
        #expect(reparsed.entries[0].term == "a | b")
    }
}
