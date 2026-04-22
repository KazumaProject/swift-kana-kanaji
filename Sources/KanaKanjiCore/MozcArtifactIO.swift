import Foundation

/// Low-level artifact I/O for the kana-kanji dictionary format.
///
/// All public-facing builder and loader functionality is exposed through the
/// higher-level ``DictionaryArtifactBuilder`` type.  This enum owns the binary
/// encoding/decoding details (LOUDS, token array, POS table, connection matrix)
/// and is shared by all dictionary kinds.
enum MozcArtifactIO {
    static let requiredFileNames = [
        "yomi_termid.louds",
        "tango.louds",
        "token_array.bin",
        "pos_table.bin",
        "connection_single_column.bin"
    ]

    // MARK: - Load

    /// Loads a ``MozcArtifactDictionary`` from the four standard artifact files
    /// in `directory`.  Works for any ``DictionaryKind`` — connection matrix is
    /// not loaded here (it is handled separately by ``ConnectionMatrix``).
    static func loadDictionary(from directory: URL) throws -> MozcArtifactDictionary {
        MozcArtifactDictionary(
            yomiTerm: try readLOUDSWithTermId(directory.appendingPathComponent("yomi_termid.louds")),
            tango: try readLOUDS(directory.appendingPathComponent("tango.louds")),
            tokens: try readTokenArray(directory.appendingPathComponent("token_array.bin")),
            posTable: try readPosTable(directory.appendingPathComponent("pos_table.bin"))
        )
    }

    // MARK: - Build (main Mozc dictionary)

    /// Builds artifacts for the **main** Mozc dictionary.
    ///
    /// Reads `dictionary00.txt`–`dictionary09.txt` from `sourceDirectory`,
    /// writes the four standard artifact files plus `connection_single_column.bin`
    /// (if `connection_single_column.txt` is present) to `outputDirectory`.
    static func writeDictionaryArtifacts(from sourceDirectory: URL, to outputDirectory: URL) throws {
        let entries = try loadAllMozcEntries(from: sourceDirectory)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try buildAndWriteArtifacts(entries: entries, to: outputDirectory)

        let connectionText = sourceDirectory.appendingPathComponent("connection_single_column.txt")
        if FileManager.default.fileExists(atPath: connectionText.path) {
            let values = try readConnectionText(connectionText)
            try writeBigEndianInt16(values, to: outputDirectory.appendingPathComponent("connection_single_column.bin"))
        }
    }

    // MARK: - Build (generic, shared by all kinds)

    /// Builds and writes the four standard artifact files from a flat list of
    /// ``DictionaryEntry`` values.
    ///
    /// This is the shared core used by both the main dictionary builder and every
    /// supplemental dictionary builder.  It does **not** write
    /// `connection_single_column.bin`; that is handled separately for `.main`.
    ///
    /// - Parameters:
    ///   - entries: Pre-parsed dictionary entries (any kind).
    ///   - outputDirectory: Directory that receives `yomi_termid.louds`,
    ///     `tango.louds`, `token_array.bin`, and `pos_table.bin`.
    static func buildAndWriteArtifacts(entries: [DictionaryEntry], to outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var grouped: [String: [DictionaryEntry]] = [:]
        grouped.reserveCapacity(entries.count)
        for entry in entries {
            grouped[entry.yomi, default: []].append(entry)
        }

        // Sort keys by UTF-16 code unit length first, then lexicographically —
        // matching the Kotlin reference sort order.
        let keys = grouped.keys.sorted { lhs, rhs in
            let l = Array(lhs.utf16)
            let r = Array(rhs.utf16)
            if l.count != r.count {
                return l.count < r.count
            }
            return l.lexicographicallyPrecedes(r)
        }

        let pos = buildPosTable(keys: keys, grouped: grouped)
        try writePosTable(pos.table, to: outputDirectory.appendingPathComponent("pos_table.bin"))

        let yomiTree = UTF16Trie()
        let tangoTree = UTF16Trie()
        for (termId, key) in keys.enumerated() {
            yomiTree.insert(key, termId: Int32(termId))
            for entry in grouped[key] ?? [] where !isHiraOrKataOnly(entry.surface) {
                tangoTree.insert(entry.surface)
            }
        }

        let yomiBuilt = buildLOUDS(from: yomiTree, withTermIds: true)
        let tangoBuilt = buildLOUDS(from: tangoTree, withTermIds: false)
        try writeLOUDS(yomiBuilt.louds, to: outputDirectory.appendingPathComponent("yomi_termid.louds"))
        try writeLOUDS(tangoBuilt.louds, to: outputDirectory.appendingPathComponent("tango.louds"))

        let tokenArray = buildTokenArray(
            keys: keys,
            grouped: grouped,
            posIndexByPair: pos.indexByPair,
            tangoNodeIndexBySurface: tangoBuilt.nodeIndexByKey
        )
        try writeTokenArray(tokenArray, to: outputDirectory.appendingPathComponent("token_array.bin"))
    }

    // MARK: - Main dictionary entry loading

    private static func loadAllMozcEntries(from directory: URL) throws -> [DictionaryEntry] {
        var entries: [DictionaryEntry] = []
        for index in 0..<10 {
            let fileURL = directory.appendingPathComponent(String(format: "dictionary%02d.txt", index))
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw KanaKanjiError.dictionaryNotFound(fileURL)
            }
            entries.append(contentsOf: try MozcDictionary.loadTSV(fileURL))
        }
        return entries
    }

    // MARK: - LOUDS / POS / token build helpers

    private static func buildPosTable(
        keys: [String],
        grouped: [String: [DictionaryEntry]]
    ) -> (table: CompatiblePosTable, indexByPair: [UInt32: UInt16]) {
        var pairCounter: [UInt32: Int] = [:]
        var counter = 0
        for key in keys {
            for entry in grouped[key] ?? [] {
                let packed = packPair(left: entry.leftId, right: entry.rightId)
                if pairCounter[packed] == nil {
                    pairCounter[packed] = counter
                    counter += 1
                }
            }
        }

        let pairs = pairCounter.sorted { $0.value > $1.value }
        var leftIds: [Int16] = []
        var rightIds: [Int16] = []
        var indexByPair: [UInt32: UInt16] = [:]
        for (index, pair) in pairs.enumerated() {
            leftIds.append(Int16(bitPattern: UInt16((pair.key >> 16) & 0xFFFF)))
            rightIds.append(Int16(bitPattern: UInt16(pair.key & 0xFFFF)))
            indexByPair[pair.key] = UInt16(index)
        }
        return (CompatiblePosTable(leftIds: leftIds, rightIds: rightIds), indexByPair)
    }

    private static func buildTokenArray(
        keys: [String],
        grouped: [String: [DictionaryEntry]],
        posIndexByPair: [UInt32: UInt16],
        tangoNodeIndexBySurface: [String: Int32]
    ) -> CompatibleTokenArray {
        var posIndex: [UInt16] = []
        var wordCost: [Int16] = []
        var nodeIndex: [Int32] = []
        var postingsBits: [Bool] = []

        for key in keys {
            postingsBits.append(false)
            for entry in grouped[key] ?? [] {
                postingsBits.append(true)
                posIndex.append(posIndexByPair[packPair(left: entry.leftId, right: entry.rightId)] ?? 0)
                wordCost.append(Int16(entry.cost))

                if entry.surface == key || isHiraganaOnly(entry.surface) {
                    nodeIndex.append(CompatibleTokenArray.hiraganaSentinel)
                } else if isKatakanaOnly(entry.surface) {
                    nodeIndex.append(CompatibleTokenArray.katakanaSentinel)
                } else {
                    nodeIndex.append(tangoNodeIndexBySurface[entry.surface] ?? -1)
                }
            }
        }
        postingsBits.append(false)

        return CompatibleTokenArray(
            posIndex: posIndex,
            wordCost: wordCost,
            nodeIndex: nodeIndex,
            postingsBits: CompatibleBitVector(bits: postingsBits)
        )
    }

    private struct BuiltLOUDS {
        let louds: CompatibleLOUDS
        let nodeIndexByKey: [String: Int32]
    }

    private static func buildLOUDS(from trie: UTF16Trie, withTermIds: Bool) -> BuiltLOUDS {
        var lbs = [true, false]
        var leaf = [false, false]
        var labels: [UInt16] = [0x20, 0x20]
        var termIds: [Int32] = [-1]
        var nodeIndexByKey: [String: Int32] = [:]

        var queue: [(node: UTF16Trie.Node, key: [UInt16])] = [(trie.root, [])]
        var index = 0
        var isFirst = true

        while index < queue.count {
            let item = queue[index]
            let node = item.node
            if withTermIds, !isFirst {
                termIds.append(node.isWord ? node.termId : -1)
            }
            isFirst = false

            for key in node.children.keys.sorted() {
                let child = node.children[key]!
                let childKey = item.key + [key]
                let nodeIndex = Int32(lbs.count)
                if child.isWord {
                    nodeIndexByKey[String(decoding: childKey, as: UTF16.self)] = nodeIndex
                }
                queue.append((child, childKey))
                lbs.append(true)
                labels.append(key)
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

    // MARK: - Binary read helpers

    private static func readLOUDS(_ fileURL: URL) throws -> CompatibleLOUDS {
        var reader = BinaryReader(data: try Data(contentsOf: fileURL))
        let lbs = try readBitVector(reader: &reader)
        let leaf = try readBitVector(reader: &reader)
        let labelCount = try reader.readIntCount()
        var labels: [UInt16] = []
        labels.reserveCapacity(labelCount)
        for _ in 0..<labelCount {
            labels.append(try reader.readUInt16LE())
        }
        return CompatibleLOUDS(lbs: lbs, isLeaf: leaf, labels: labels, termIds: nil)
    }

    private static func readLOUDSWithTermId(_ fileURL: URL) throws -> CompatibleLOUDS {
        var reader = BinaryReader(data: try Data(contentsOf: fileURL))
        let lbs = try readBitVector(reader: &reader)
        let leaf = try readBitVector(reader: &reader)
        let labelCount = try reader.readIntCount()
        var labels: [UInt16] = []
        labels.reserveCapacity(labelCount)
        for _ in 0..<labelCount {
            labels.append(try reader.readUInt16LE())
        }
        let termCount = try reader.readIntCount()
        var termIds: [Int32] = []
        termIds.reserveCapacity(termCount)
        for _ in 0..<termCount {
            termIds.append(try reader.readInt32LE())
        }
        return CompatibleLOUDS(lbs: lbs, isLeaf: leaf, labels: labels, termIds: termIds)
    }

    private static func readTokenArray(_ fileURL: URL) throws -> CompatibleTokenArray {
        var reader = BinaryReader(data: try Data(contentsOf: fileURL))
        let posCount = Int(try reader.readUInt32LE())
        var posIndex: [UInt16] = []
        for _ in 0..<posCount { posIndex.append(try reader.readUInt16LE()) }

        let costCount = Int(try reader.readUInt32LE())
        var wordCost: [Int16] = []
        for _ in 0..<costCount { wordCost.append(try reader.readInt16LE()) }

        let nodeCount = Int(try reader.readUInt32LE())
        var nodeIndex: [Int32] = []
        for _ in 0..<nodeCount { nodeIndex.append(try reader.readInt32LE()) }

        return CompatibleTokenArray(
            posIndex: posIndex,
            wordCost: wordCost,
            nodeIndex: nodeIndex,
            postingsBits: try readBitVector(reader: &reader)
        )
    }

    private static func readPosTable(_ fileURL: URL) throws -> CompatiblePosTable {
        var reader = BinaryReader(data: try Data(contentsOf: fileURL))
        let count = Int(try reader.readUInt32LE())
        var left: [Int16] = []
        var right: [Int16] = []
        for _ in 0..<count { left.append(try reader.readInt16LE()) }
        for _ in 0..<count { right.append(try reader.readInt16LE()) }
        return CompatiblePosTable(leftIds: left, rightIds: right)
    }

    // MARK: - Binary write helpers

    private static func writeLOUDS(_ louds: CompatibleLOUDS, to fileURL: URL) throws {
        var writer = BinaryWriter()
        writeBitVector(louds.lbs, writer: &writer)
        writeBitVector(louds.isLeaf, writer: &writer)
        writer.writeUInt64(UInt64(louds.labels.count))
        for label in louds.labels { writer.writeUInt16(label) }
        if let termIds = louds.termIds {
            writer.writeUInt64(UInt64(termIds.count))
            for id in termIds { writer.writeInt32(id) }
        }
        try writer.data.write(to: fileURL, options: .atomic)
    }

    private static func writeTokenArray(_ tokens: CompatibleTokenArray, to fileURL: URL) throws {
        var writer = BinaryWriter()
        writer.writeUInt32(UInt32(tokens.posIndex.count))
        for value in tokens.posIndex { writer.writeUInt16(value) }
        writer.writeUInt32(UInt32(tokens.wordCost.count))
        for value in tokens.wordCost { writer.writeInt16(value) }
        writer.writeUInt32(UInt32(tokens.nodeIndex.count))
        for value in tokens.nodeIndex { writer.writeInt32(value) }
        writeBitVector(tokens.postingsBits, writer: &writer)
        try writer.data.write(to: fileURL, options: .atomic)
    }

    private static func writePosTable(_ table: CompatiblePosTable, to fileURL: URL) throws {
        var writer = BinaryWriter()
        writer.writeUInt32(UInt32(table.leftIds.count))
        for value in table.leftIds { writer.writeInt16(value) }
        for value in table.rightIds { writer.writeInt16(value) }
        try writer.data.write(to: fileURL, options: .atomic)
    }

    private static func readBitVector(reader: inout BinaryReader) throws -> CompatibleBitVector {
        let bitCount = try reader.readIntCount()
        let wordCount = try reader.readIntCount()
        var words: [UInt64] = []
        words.reserveCapacity(wordCount)
        for _ in 0..<wordCount { words.append(try reader.readUInt64()) }
        return CompatibleBitVector(bitCount: bitCount, words: words)
    }

    private static func writeBitVector(_ bitVector: CompatibleBitVector, writer: inout BinaryWriter) {
        writer.writeUInt64(UInt64(bitVector.bitCount))
        writer.writeUInt64(UInt64(bitVector.words.count))
        for word in bitVector.words {
            writer.writeUInt64(word)
        }
    }

    private static func readConnectionText(_ fileURL: URL) throws -> [Int16] {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).dropFirst().compactMap {
            Int16($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func writeBigEndianInt16(_ values: [Int16], to fileURL: URL) throws {
        var data = Data()
        data.reserveCapacity(values.count * 2)
        for value in values {
            let raw = UInt16(bitPattern: value)
            data.append(UInt8((raw >> 8) & 0xFF))
            data.append(UInt8(raw & 0xFF))
        }
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Unicode predicates

    private static func packPair(left: Int, right: Int) -> UInt32 {
        (UInt32(UInt16(bitPattern: Int16(left))) << 16) | UInt32(UInt16(bitPattern: Int16(right)))
    }

    private static func isHiraganaOnly(_ value: String) -> Bool {
        !value.isEmpty && value.utf16.allSatisfy { (0x3040...0x309F).contains($0) }
    }

    private static func isKatakanaOnly(_ value: String) -> Bool {
        !value.isEmpty && value.utf16.allSatisfy { (0x30A0...0x30FF).contains($0) || (0xFF65...0xFF9F).contains($0) }
    }

    private static func isHiraOrKataOnly(_ value: String) -> Bool {
        !value.isEmpty && value.utf16.allSatisfy {
            (0x3040...0x309F).contains($0) || (0x30A0...0x30FF).contains($0) || (0xFF65...0xFF9F).contains($0)
        }
    }
}

// MARK: - UTF-16 Trie (internal build helper)

/// A simple mutable UTF-16 trie used during artifact construction.
/// Not part of the public API.
final class UTF16Trie {
    final class Node {
        var isWord = false
        var termId: Int32 = -1
        var children: [UInt16: Node] = [:]
    }

    let root = Node()

    func insert(_ text: String, termId: Int32? = nil) {
        var node = root
        for unit in text.utf16 {
            if let child = node.children[unit] {
                node = child
            } else {
                let child = Node()
                node.children[unit] = child
                node = child
            }
        }
        node.isWord = true
        if let termId {
            node.termId = termId
        }
    }
}
