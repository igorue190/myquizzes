//
//  QuizGenerationTests.swift
//  CoreModelsTests
//
//  Covers the AI quiz-generation value types and the in-memory service used by
//  previews/tests.
//

import Testing
import Foundation
@testable import CoreModels

@Suite("Quiz generation value types")
struct QuizGenerationTests {

    @Test("QuizGenerationRequest round-trips through Codable")
    func requestRoundTrip() throws {
        let original = QuizGenerationRequest(sourceText: "notes", questionCount: 8, title: "Bio")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuizGenerationRequest.self, from: data)
        #expect(decoded == original)
    }

    @Test("request defaults to 10 questions and no title")
    func requestDefaults() {
        let request = QuizGenerationRequest(sourceText: "x")
        #expect(request.questionCount == 10)
        #expect(request.title == nil)
    }

    @Test("InMemoryQuizGenerationService returns its canned Markdown")
    func inMemoryReturnsCanned() async throws {
        let service = InMemoryQuizGenerationService()
        let markdown = try await service.generate(QuizGenerationRequest(sourceText: "anything"))
        #expect(markdown.contains("## "))
        #expect(markdown.contains("<!-- type:"))
    }

    @Test("InMemoryQuizGenerationService rejects empty source")
    func inMemoryRejectsEmpty() async {
        let service = InMemoryQuizGenerationService()
        await #expect(throws: QuizGenerationError.emptySource) {
            try await service.generate(QuizGenerationRequest(sourceText: "   \n "))
        }
    }
}
