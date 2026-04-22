import Foundation

// MARK: - EnglishDictionary

/// A loaded English dictionary, backed by three artifact files built by
/// ``EnglishDictionaryBuilder``.
///
/// This type is **separate** from ``MozcDictionary`` and uses a dedicated
/// LOUDS + token layout suited to the English n-gram source format.
public struct EnglishDictionary: Sendable {

    // MARK: - Stored artifacts

    let reading: CompatibleLOUDS   // reading trie  (LOUDSWithTermId)
    let word: CompatibleLOUDS      // word trie      (LOUDS, uppercase words only)
    let tokens: EnglishTokenArray  // token array    (wordCost + nodeId)

    // MARK: - Init

    /// Loads English dictionary artifacts from `artifactsDirectory`.
    ///
    /// Expects `reading.dat`, `word.dat`, and `token.dat` to be present.
    ///
    /// - Parameter artifactsDirectory: Directory produced by ``EnglishDictionaryBuilder``.
    public init(artifactsDirectory directory: URL) throws {
        let artifacts = try EnglishArtifactIO.loadArtifacts(from: directory)
        self.reading = artifacts.reading
        self.word    = artifacts.word
        self.tokens  = artifacts.tokens
    }

    /// Internal init for tests and in-process build-then-load.
    init(reading: CompatibleLOUDS, word: CompatibleLOUDS, tokens: EnglishTokenArray) {
        self.reading = reading
        self.word    = word
        self.tokens  = tokens
    }
}
