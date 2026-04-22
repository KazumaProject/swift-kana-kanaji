import Foundation

// MARK: - EnglishDictionaryEntry

/// A parsed entry from the English n-gram dictionary source.
///
/// Corresponds to one non-header row in the source `.txt` files inside
/// `1-grams_score_cost_pos_combined_with_ner.zip`.
public struct EnglishDictionaryEntry: Sendable {
    /// Lowercase reading / romanized form (cols[0]).
    public let reading: String
    /// Word cost — lower is more common (cols[3], clamped to `Int16.max`).
    public let cost: Int16
    /// The actual word with its original casing (cols[1]).
    public let word: String
    /// `true` when `word` differs from its own lowercase form.
    ///
    /// Words without any uppercase character (e.g. `"hello"`) can be
    /// recovered directly from `reading`, so they are *not* inserted into
    /// the word trie and receive `nodeId = -1` in the token array.
    /// Words like `"iOS"` or `"GitHub"` must be stored in the word trie.
    public let withUpperCase: Bool

    public init(reading: String, cost: Int16, word: String) {
        self.reading = reading
        self.cost = cost
        self.word = word
        self.withUpperCase = word.hasInternalUpperCase()
    }
}

// MARK: - String extension

extension String {
    /// Returns `true` when this string contains at least one uppercase character.
    ///
    /// Examples:
    /// - `"hello"` → `false`
    /// - `"iOS"` → `true`  (has uppercase O, S)
    /// - `"GitHub"` → `true` (has uppercase G, H)
    func hasInternalUpperCase() -> Bool {
        self != self.lowercased()
    }
}
