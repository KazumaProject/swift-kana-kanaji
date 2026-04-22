import Foundation

// MARK: - EnglishArtifactIO

/// Low-level artifact I/O for the English dictionary family.
///
/// File names mirror the Kotlin reference implementation:
/// - `reading.dat` — reading LOUDS trie (LOUDSWithTermId binary format)
/// - `word.dat`    — word LOUDS trie (plain LOUDS binary format)
/// - `token.dat`   — English token array
///
/// The binary format for `reading.dat` and `word.dat` is identical to the
/// format used by `MozcArtifactIO` for `yomi_termid.louds` / `tango.louds`,
/// which makes the codec easy to share without coupling the two families.
///
/// `token.dat` format:
/// ```
/// UInt32  wordCost count
/// [Int16] wordCost array
/// UInt32  nodeId count
/// [Int32] nodeId array
/// BitVector (bitCount UInt64, wordCount UInt64, [UInt64] words)
/// ```
enum EnglishArtifactIO {

    static let artifactFileNames = ["reading.dat", "word.dat", "token.dat"]

    // MARK: - Write

    static func writeArtifacts(
        readingLOUDS: CompatibleLOUDS,
        wordLOUDS: CompatibleLOUDS,
        tokenArray: EnglishTokenArray,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeLOUDS(readingLOUDS, to: directory.appendingPathComponent("reading.dat"))
        try writeLOUDS(wordLOUDS,    to: directory.appendingPathComponent("word.dat"))
        try writeTokenArray(tokenArray, to: directory.appendingPathComponent("token.dat"))
    }

    // MARK: - Read

    static func loadArtifacts(from directory: URL) throws -> (
        reading: CompatibleLOUDS,
        word: CompatibleLOUDS,
        tokens: EnglishTokenArray
    ) {
        let readingURL = directory.appendingPathComponent("reading.dat")
        let wordURL    = directory.appendingPathComponent("word.dat")
        let tokenURL   = directory.appendingPathComponent("token.dat")

        for url in [readingURL, wordURL, tokenURL] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw EnglishDictionaryError.artifactNotFound(url)
            }
        }

        let reading = try readLOUDS(readingURL, withTermIds: true)
        let word    = try readLOUDS(wordURL,    withTermIds: false)
        let tokens  = try readTokenArray(tokenURL)

        return (reading, word, tokens)
    }

    // MARK: - LOUDS read / write (same encoding as MozcArtifactIO)

    private static func writeLOUDS(_ louds: CompatibleLOUDS, to url: URL) throws {
        var w = BinaryWriter()
        writeBitVector(louds.lbs,    writer: &w)
        writeBitVector(louds.isLeaf, writer: &w)
        w.writeUInt64(UInt64(louds.labels.count))
        for label in louds.labels { w.writeUInt16(label) }
        if let termIds = louds.termIds {
            w.writeUInt64(UInt64(termIds.count))
            for id in termIds { w.writeInt32(id) }
        }
        try w.data.write(to: url, options: .atomic)
    }

    private static func readLOUDS(_ url: URL, withTermIds: Bool) throws -> CompatibleLOUDS {
        var r = BinaryReader(data: try Data(contentsOf: url))
        let lbs  = try readBitVector(reader: &r)
        let leaf = try readBitVector(reader: &r)

        let labelCount = try r.readIntCount()
        var labels = [UInt16]()
        labels.reserveCapacity(labelCount)
        for _ in 0..<labelCount { labels.append(try r.readUInt16LE()) }

        var termIds: [Int32]?
        if withTermIds {
            let termCount = try r.readIntCount()
            var ids = [Int32]()
            ids.reserveCapacity(termCount)
            for _ in 0..<termCount { ids.append(try r.readInt32LE()) }
            termIds = ids
        }

        return CompatibleLOUDS(lbs: lbs, isLeaf: leaf, labels: labels, termIds: termIds)
    }

    // MARK: - Token array read / write

    private static func writeTokenArray(_ array: EnglishTokenArray, to url: URL) throws {
        var w = BinaryWriter()
        w.writeUInt32(UInt32(array.wordCost.count))
        for v in array.wordCost { w.writeInt16(v) }
        w.writeUInt32(UInt32(array.nodeId.count))
        for v in array.nodeId { w.writeInt32(v) }
        writeBitVector(array.postingsBits, writer: &w)
        try w.data.write(to: url, options: .atomic)
    }

    private static func readTokenArray(_ url: URL) throws -> EnglishTokenArray {
        var r = BinaryReader(data: try Data(contentsOf: url))

        let costCount = Int(try r.readUInt32LE())
        var costs = [Int16]()
        costs.reserveCapacity(costCount)
        for _ in 0..<costCount { costs.append(try r.readInt16LE()) }

        let nodeCount = Int(try r.readUInt32LE())
        var nodes = [Int32]()
        nodes.reserveCapacity(nodeCount)
        for _ in 0..<nodeCount { nodes.append(try r.readInt32LE()) }

        let postings = try readBitVector(reader: &r)

        return EnglishTokenArray(wordCost: costs, nodeId: nodes, postingsBits: postings)
    }

    // MARK: - Bit vector helpers (same encoding as MozcArtifactIO)

    private static func writeBitVector(_ bv: CompatibleBitVector, writer: inout BinaryWriter) {
        writer.writeUInt64(UInt64(bv.bitCount))
        writer.writeUInt64(UInt64(bv.words.count))
        for w in bv.words { writer.writeUInt64(w) }
    }

    private static func readBitVector(reader: inout BinaryReader) throws -> CompatibleBitVector {
        let bitCount  = try reader.readIntCount()
        let wordCount = try reader.readIntCount()
        var words = [UInt64]()
        words.reserveCapacity(wordCount)
        for _ in 0..<wordCount { words.append(try reader.readUInt64()) }
        return CompatibleBitVector(bitCount: bitCount, words: words)
    }
}
