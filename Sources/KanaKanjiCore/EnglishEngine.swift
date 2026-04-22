import Foundation

// MARK: - EnglishEngine

/// Provides English word prediction using a loaded ``EnglishDictionary``.
///
/// Corresponds to `EnglishEngine.getPrediction` in the Kotlin reference
/// implementation, implemented on top of the Swift LOUDS trie infrastructure.
///
/// ## Lookup flow
/// 1. Perform a predictive search on the **reading trie** — find every reading
///    that begins with `input`.
/// 2. For each matching reading, retrieve its `termId` and collect tokens.
/// 3. Recover the word for each token:
///    - `nodeId == -1` → word is the same as the reading (no uppercase).
///    - `nodeId >= 0`  → reconstruct word from the **word trie**.
/// 4. Sort candidates by `score` (word cost) ascending.
public struct EnglishEngine: Sendable {

    // MARK: - Candidate

    /// A single prediction result.
    public struct Candidate: Sendable, Equatable {
        /// The lowercase reading form.
        public let reading: String
        /// The word with original casing (may equal `reading` when all-lowercase).
        public let word: String
        /// The word cost (lower = more common / ranked higher).
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

    // MARK: - Prediction

    /// Returns English word candidates whose reading starts with `input`.
    ///
    /// - Parameter input: A (typically lowercase) prefix such as `"gi"` or `"iOS"`.
    /// - Returns: Candidate list sorted by `score` ascending (best first).
    public func getPrediction(input: String) -> [Candidate] {
        guard !input.isEmpty else { return [] }

        let codeUnits = Array(input.utf16)
        let termIdHits = dictionary.reading.predictiveSearchTermIds(codeUnits)

        var candidates: [Candidate] = []
        candidates.reserveCapacity(termIdHits.count * 2)

        for (readingStr, termId) in termIdHits {
            let tokenEntries = dictionary.tokens.tokens(forTermId: termId)
            for token in tokenEntries {
                let wordStr: String
                if token.nodeId == -1 {
                    // No uppercase: word equals reading.
                    wordStr = readingStr
                } else {
                    // Uppercase word: reconstruct from word trie.
                    wordStr = dictionary.word.getLetter(nodeIndex: Int(token.nodeId))
                }
                candidates.append(Candidate(
                    reading: readingStr,
                    word: wordStr,
                    score: Int(token.wordCost)
                ))
            }
        }

        return candidates.sorted { $0.score < $1.score }
    }
}
