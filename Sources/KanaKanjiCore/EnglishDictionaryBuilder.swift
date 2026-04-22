import Foundation

// MARK: - EnglishDictionaryBuilder

/// Builds English dictionary artifacts from parsed entries.
///
/// Output layout under `outputDirectory/`:
/// ```
/// reading.dat   — reading LOUDS trie with termIds
/// word.dat      — word LOUDS trie (uppercase words only, no termIds)
/// token.dat     — EnglishTokenArray (wordCost + nodeId + postings)
/// ```
///
/// This builder is **entirely separate** from the Mozc-family
/// `DictionaryArtifactBuilder` / `MozcArtifactIO` pipeline.
public enum EnglishDictionaryBuilder {

    // MARK: - Artifact file names

    /// The file names written by this builder.
    public static let artifactFileNames = EnglishArtifactIO.artifactFileNames

    /// The output subdirectory name used under a root output directory.
    public static let outputDirectoryName = "english"

    // MARK: - Public build API

    /// Parses the given zip file and builds artifacts into `outputDirectory`.
    ///
    /// - Parameters:
    ///   - zipURL: Path to `1-grams_score_cost_pos_combined_with_ner.zip`.
    ///   - outputDirectory: Directory that receives `reading.dat`, `word.dat`, `token.dat`.
    public static func build(from zipURL: URL, to outputDirectory: URL) throws {
        let entries = try EnglishDictionarySourceParser.parse(from: zipURL)
        try build(entries: entries, to: outputDirectory)
    }

    /// Builds artifacts from a pre-parsed list of ``EnglishDictionaryEntry`` values.
    ///
    /// - Parameters:
    ///   - entries: Parsed entries (must be non-empty).
    ///   - outputDirectory: Target directory for the three artifact files.
    public static func build(entries: [EnglishDictionaryEntry], to outputDirectory: URL) throws {
        guard !entries.isEmpty else {
            throw EnglishDictionaryError.noEntries
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // ── Group by reading, sort by (UTF-16 length, then lexicographic) ────
        var grouped: [String: [EnglishDictionaryEntry]] = [:]
        for entry in entries {
            grouped[entry.reading, default: []].append(entry)
        }

        let keys = grouped.keys.sorted { lhs, rhs in
            let l = Array(lhs.utf16)
            let r = Array(rhs.utf16)
            if l.count != r.count { return l.count < r.count }
            return l.lexicographicallyPrecedes(r)
        }

        // ── Build reading trie (with termIds) ─────────────────────────────────
        let readingTrie = UTF16Trie()
        for (termId, key) in keys.enumerated() {
            readingTrie.insert(key, termId: Int32(termId))
        }

        // ── Build word trie (withUpperCase words only, no termIds) ────────────
        let wordTrie = UTF16Trie()
        for key in keys {
            for entry in grouped[key] ?? [] where entry.withUpperCase {
                wordTrie.insert(entry.word)
            }
        }

        let readingBuilt = buildLOUDS(from: readingTrie, withTermIds: true)
        let wordBuilt    = buildLOUDS(from: wordTrie, withTermIds: false)

        // ── Build token array ─────────────────────────────────────────────────
        var tokenWordCost: [Int16] = []
        var tokenNodeId: [Int32] = []
        var postingsBits: [Bool] = []

        for key in keys {
            postingsBits.append(false)  // termId boundary
            for entry in grouped[key] ?? [] {
                postingsBits.append(true)  // one true per token
                tokenWordCost.append(entry.cost)

                if entry.withUpperCase {
                    // Store the lbs position of the word's node in the word trie.
                    if let idx = wordBuilt.nodeIndexByKey[entry.word], idx <= Int(Int32.max) {
                        tokenNodeId.append(Int32(idx))
                    } else {
                        tokenNodeId.append(-1)
                    }
                } else {
                    // Word is recoverable from reading — skip word trie lookup.
                    tokenNodeId.append(-1)
                }
            }
        }
        postingsBits.append(false)  // final boundary

        let tokenArray = EnglishTokenArray(
            wordCost: tokenWordCost,
            nodeId: tokenNodeId,
            postingsBits: CompatibleBitVector(bits: postingsBits)
        )

        try EnglishArtifactIO.writeArtifacts(
            readingLOUDS: readingBuilt.louds,
            wordLOUDS: wordBuilt.louds,
            tokenArray: tokenArray,
            to: outputDirectory
        )
    }

    // MARK: - LOUDS builder

    private struct BuiltLOUDS {
        let louds: CompatibleLOUDS
        /// Maps the UTF-16 string of each word node to its lbs bit-position.
        let nodeIndexByKey: [String: Int]
    }

    /// Builds a ``CompatibleLOUDS`` from a ``UTF16Trie``.
    ///
    /// Adapted from the private `MozcArtifactIO.buildLOUDS` — kept here so the
    /// English family remains self-contained and does not depend on Mozc internals.
    private static func buildLOUDS(from trie: UTF16Trie, withTermIds: Bool) -> BuiltLOUDS {
        // Sentinel initial state (matches Kotlin / MozcArtifactIO convention).
        var lbs: [Bool]    = [true, false]
        var leaf: [Bool]   = [false, false]
        var labels: [UInt16] = [0x20, 0x20]
        var termIds: [Int32] = withTermIds ? [-1] : []
        var nodeIndexByKey: [String: Int] = [:]

        var queue: [(node: UTF16Trie.Node, key: [UInt16])] = [(trie.root, [])]
        var index  = 0
        var isFirst = true

        while index < queue.count {
            let item = queue[index]
            let node = item.node

            if withTermIds, !isFirst {
                termIds.append(node.isWord ? node.termId : -1)
            }
            isFirst = false

            for childKey in node.children.keys.sorted() {
                let child    = node.children[childKey]!
                let fullKey  = item.key + [childKey]
                let nodeIndex = lbs.count  // lbs position this true-bit will occupy
                if child.isWord {
                    nodeIndexByKey[String(decoding: fullKey, as: UTF16.self)] = nodeIndex
                }
                queue.append((child, fullKey))
                lbs.append(true)
                labels.append(childKey)
                leaf.append(child.isWord)
            }
            lbs.append(false)
            leaf.append(false)
            index += 1
        }

        return BuiltLOUDS(
            louds: CompatibleLOUDS(
                lbs: CompatibleBitVector(bits: lbs),
                isLeaf: CompatibleBitVector(bits: leaf),
                labels: labels,
                termIds: withTermIds ? termIds : nil
            ),
            nodeIndexByKey: nodeIndexByKey
        )
    }
}
