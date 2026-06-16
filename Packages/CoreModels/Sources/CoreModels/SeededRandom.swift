//
//  SeededRandom.swift
//  CoreModels
//
//  A deterministic, Sendable random number generator. The quiz engine seeds one
//  of these from `SessionConfig.seed` so question selection and answer shuffling
//  are reproducible — the same seed always yields the same session, which is
//  what makes the engine unit-testable.
//

import Foundation

/// SplitMix64 — a tiny, well-distributed PRNG. Not for cryptographic use; its
/// job here is reproducibility, not unpredictability.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // Avoid the all-zero state degenerating; mix the seed once.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
