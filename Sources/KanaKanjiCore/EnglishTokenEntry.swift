import Foundation

// MARK: - EnglishTokenEntry

/// A single token in the English dictionary token array.
///
/// Pairs a word cost with a reference into the word trie.
/// When `nodeId == -1` the word is identical to the reading (no uppercase),
/// so it can be recovered without a trie lookup.
public struct EnglishTokenEntry: Sendable {
    /// Word cost (lower = more common / better candidate).
    public let wordCost: Int16
    /// Bit-position of the word's node in the word LOUDS trie,
    /// or `-1` when `word == reading` (case-insensitively identical).
    public let nodeId: Int32
}

// MARK: - EnglishTokenArray

/// Token array indexed by reading `termId`.
///
/// Layout mirrors `CompatibleTokenArray` but omits the POS index:
/// - `wordCost` array
/// - `nodeId` array
/// - `postingsBits` bit vector (false = termId boundary, true = token)
struct EnglishTokenArray: Sendable {
    let wordCost: [Int16]
    let nodeId: [Int32]
    let postingsBits: CompatibleBitVector

    /// Returns all token entries for the given `termId`.
    func tokens(forTermId termId: Int) -> [EnglishTokenEntry] {
        let p0 = postingsBits.select0(termId + 1)
        let p1 = postingsBits.select0(termId + 2)
        guard p0 >= 0, p1 >= 0 else { return [] }

        let begin = postingsBits.rank1(p0)
        let end   = postingsBits.rank1(p1)
        guard begin <= end, end <= wordCost.count else { return [] }

        return (begin..<end).map {
            EnglishTokenEntry(wordCost: wordCost[$0], nodeId: nodeId[$0])
        }
    }
}
