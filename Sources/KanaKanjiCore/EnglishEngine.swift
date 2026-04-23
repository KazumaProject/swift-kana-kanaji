import Foundation

// MARK: - EnglishEngine

/// English word prediction engine backed by a loaded ``EnglishDictionary``.
///
/// Matches the behaviour of `EnglishEngine.getCandidates` in the Kotlin reference
/// implementation, implemented on top of the Swift LOUDS trie infrastructure.
///
/// ## Candidate generation flow
/// 1. Lowercase the input and perform a **predictive search** on the reading trie,
///    limited to 6 readings (input ≤ 2 chars) or 12 readings (input > 2 chars).
/// 2. Always emit the three casing variants of the raw input itself
///    (original / first-letter-uppercase / all-uppercase) with fixed scores.
/// 3. For every matched reading, collect tokens, resolve the base word, then emit
///    base / first-letter-uppercase / all-uppercase variants with length-weighted scores.
/// 4. When the first character of the input is uppercase the first-letter-cap variant
///    of dictionary words is boosted (score reduced) to reflect that the user likely
///    wants a capitalised result.
/// 5. **Deduplicate** by display string – keep only the entry with the lowest score.
/// 6. **Fallback**: when the predictive search finds no readings at all, return the
///    three input-based casing variants with distinct fallback scores.
/// 7. Return the list sorted by `score` ascending (best / most-common first).
///
/// ## Typo correction
/// The Kotlin counterpart supports an optional typo-correction pass.
/// The hook is present here as `enableTypoCorrection` but the pass is **not yet
/// implemented**; the parameter exists so call-sites can be written in final form
/// now and the feature can be added later without breaking changes.
public struct EnglishEngine: Sendable {

    // MARK: - Constants

    /// Per-character score penalty applied to capitalised / uppercased variants of
    /// dictionary words so that longer words sort after shorter ones of the same cost.
    /// Mirrors Kotlin's `LENGTH_MULTIPLY = 2000`.
    private static let lengthMultiply = 2000

    // MARK: - Candidate

    /// A single prediction result.
    public struct Candidate: Sendable, Equatable {
        /// The lowercase reading used as the trie lookup key.
        /// For input-based candidates (original / cased variants of the typed text)
        /// this equals `input.lowercased()`.
        public let reading: String
        /// The word to display, potentially a cased variant of the base form.
        public let word: String
        /// Rank score – lower means more preferred / more common.
        public let score: Int

        public init(reading: String, word: String, score: Int) {
            self.reading = reading
            self.word    = word
            self.score   = score
        }
    }

    // MARK: - Properties

    private let dictionary: EnglishDictionary

    // MARK: - Init

    public init(dictionary: EnglishDictionary) {
        self.dictionary = dictionary
    }

    // MARK: - Public API

    /// Returns English word candidates whose reading starts with `input`.
    ///
    /// Implements the full Kotlin `EnglishEngine.getCandidates` logic:
    /// input variants, predictive-search candidates with casing variants,
    /// deduplication, and fallback.
    ///
    /// - Parameters:
    ///   - input: Raw user input, e.g. `"hel"`, `"NASA"`, or `"ios"`.
    ///   - enableTypoCorrection: Reserved for future typo-correction pass.
    ///                           Currently unused — always treated as `false`.
    /// - Returns: Candidate list sorted by `score` ascending (best first).
    public func getPrediction(
        input: String,
        enableTypoCorrection: Bool = false
    ) -> [Candidate] {
        guard !input.isEmpty else { return [] }

        let lowerInput = input.lowercased()
        // Predictive limit: 6 for very short inputs, 12 otherwise (mirrors Kotlin).
        let limit = input.count <= 2 ? 6 : 12
        let firstCharUpper = input.first?.isUppercase ?? false

        // Predictive search on the reading trie using the lowercased key.
        let lowerCUs   = Array(lowerInput.utf16)
        let termIdHits = Array(
            dictionary.reading.predictiveSearchTermIds(lowerCUs).prefix(limit)
        )

        // ── Fallback: no predictive hits ───────────────────────────────────────
        if termIdHits.isEmpty {
            return fallbackCandidates(
                input: input,
                lowerInput: lowerInput,
                firstCharUpper: firstCharUpper
            ).sorted { $0.score < $1.score }
        }

        // ── Build full candidate set ───────────────────────────────────────────
        var all: [Candidate] = []
        all.reserveCapacity(3 + termIdHits.count * 6)

        // 1. Input-based variants (always present when predictive is non-empty).
        all += inputCandidates(input: input, lowerInput: lowerInput)

        // 2. Dictionary-based variants.
        for (readingStr, termId) in termIdHits {
            let tokenEntries = dictionary.tokens.tokens(forTermId: termId)
            for token in tokenEntries {
                let base = resolveBase(token: token, readingStr: readingStr)
                all += wordVariants(
                    base: base,
                    reading: readingStr,
                    wordCost: Int(token.wordCost),
                    inputFirstCharUpper: firstCharUpper
                )
            }
        }

        // 3. Dedup: same display word → keep entry with lowest score.
        let deduped = Dictionary(grouping: all, by: { $0.word })
            .compactMapValues { $0.min(by: { $0.score < $1.score }) }
            .values

        return deduped.sorted { $0.score < $1.score }
    }

    // MARK: - Private helpers

    /// Three fallback candidates returned when the dictionary has no predictive hits.
    ///
    /// When the input's first character is already uppercase the
    /// first-letter-cap variant gets a *lower* (better) score than the
    /// original, mirroring the Kotlin scoring heuristic.
    private func fallbackCandidates(
        input: String,
        lowerInput: String,
        firstCharUpper: Bool
    ) -> [Candidate] {
        [
            Candidate(reading: lowerInput, word: input,                  score: 10000),
            Candidate(reading: lowerInput, word: capitalizeFirst(input),  score: firstCharUpper ? 8500 : 10001),
            Candidate(reading: lowerInput, word: input.uppercased(),      score: 10002),
        ]
    }

    /// Three input-based candidates included whenever the predictive search is non-empty.
    private func inputCandidates(input: String, lowerInput: String) -> [Candidate] {
        let len = input.count
        return [
            Candidate(reading: lowerInput, word: input,                  score: 500),
            Candidate(reading: lowerInput, word: capitalizeFirst(input),  score: len <= 3 ? 9_000 : len <= 4 ? 12_000 : 57_000),
            Candidate(reading: lowerInput, word: input.uppercased(),      score: len <= 3 ? 9_001 : len <= 4 ? 22_001 : 57_001),
        ]
    }

    /// Three casing variants (base / first-letter-cap / all-upper) for one dictionary word.
    ///
    /// Score design mirrors Kotlin `getCandidates`:
    /// - Base: raw `wordCost`.
    /// - Cap:  if input starts with uppercase → `max(0, wordCost + len × M − 8000)`;
    ///         otherwise `wordCost + 500 + len × M`.
    /// - Upper: if input starts with uppercase → `wordCost + len × M`;
    ///          otherwise `wordCost + 2000 + len × M`.
    private func wordVariants(
        base: String,
        reading: String,
        wordCost: Int,
        inputFirstCharUpper: Bool
    ) -> [Candidate] {
        let m   = Self.lengthMultiply
        let len = base.count

        let capScore: Int = inputFirstCharUpper
            ? max(0, wordCost + len * m - 8_000)
            : wordCost + 500 + len * m

        let upperScore: Int = inputFirstCharUpper
            ? wordCost + len * m
            : wordCost + 2_000 + len * m

        return [
            Candidate(reading: reading, word: base,                   score: wordCost),
            Candidate(reading: reading, word: capitalizeFirst(base),   score: capScore),
            Candidate(reading: reading, word: base.uppercased(),       score: upperScore),
        ]
    }

    /// Resolves the display word for a token.
    ///
    /// - `nodeId == -1`: word is identical to the reading (no uppercase chars stored).
    /// - `nodeId >= 0`:  word has uppercase chars; reconstruct from the word trie.
    private func resolveBase(token: EnglishTokenEntry, readingStr: String) -> String {
        token.nodeId == -1
            ? readingStr
            : dictionary.word.getLetter(nodeIndex: Int(token.nodeId))
    }

    /// Capitalises the first character of `s` safely.
    ///
    /// - Empty strings are returned unchanged.
    /// - Non-alphabetic leading characters are passed through `uppercased()` without
    ///   effect, so the method never crashes or produces garbled output.
    private func capitalizeFirst(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
