import Foundation

struct LOUDSBitVector: Sendable {
    let bitCount: Int

    private let words: [UInt64]
    private let rank1ByWord: [Int]
    private let zeroPositions: [Int]

    init(bits: [Bool]) {
        self.bitCount = bits.count

        var words = Array(repeating: UInt64(0), count: (bits.count + 63) / 64)
        var zeros: [Int] = []
        zeros.reserveCapacity(bits.count / 2)

        for (index, bit) in bits.enumerated() {
            if bit {
                words[index / 64] |= UInt64(1) << UInt64(index % 64)
            } else {
                zeros.append(index)
            }
        }

        var rankByWord: [Int] = []
        rankByWord.reserveCapacity(words.count + 1)
        rankByWord.append(0)
        for word in words {
            rankByWord.append(rankByWord[rankByWord.count - 1] + word.nonzeroBitCount)
        }

        self.words = words
        self.rank1ByWord = rankByWord
        self.zeroPositions = zeros
    }

    init(bitCount: Int, words: [UInt64]) {
        self.bitCount = bitCount
        self.words = words

        var zeros: [Int] = []
        zeros.reserveCapacity(bitCount / 2)

        if bitCount > 0 {
            for index in 0..<bitCount {
                let word = words[index / 64]
                let bit = (word & (UInt64(1) << UInt64(index % 64))) != 0
                if !bit {
                    zeros.append(index)
                }
            }
        }

        var rankByWord: [Int] = []
        rankByWord.reserveCapacity(words.count + 1)
        rankByWord.append(0)
        for word in words {
            rankByWord.append(rankByWord[rankByWord.count - 1] + word.nonzeroBitCount)
        }

        self.rank1ByWord = rankByWord
        self.zeroPositions = zeros
    }

    var packedWords: [UInt64] {
        words
    }

    var zeroCount: Int {
        zeroPositions.count
    }

    func rank1(through index: Int) -> Int {
        guard index >= 0, bitCount > 0 else {
            return 0
        }

        let clamped = min(index, bitCount - 1)
        let wordIndex = clamped / 64
        let bitOffset = clamped % 64
        let mask = bitOffset == 63
            ? UInt64.max
            : ((UInt64(1) << UInt64(bitOffset + 1)) - 1)

        return rank1ByWord[wordIndex] + (words[wordIndex] & mask).nonzeroBitCount
    }

    func select0(_ oneBasedRank: Int) -> Int? {
        guard oneBasedRank > 0, oneBasedRank <= zeroPositions.count else {
            return nil
        }
        return zeroPositions[oneBasedRank - 1]
    }
}

/// 濁点 / 半濁点 / 小書き文字などの「入力で省略されがちなしるし」を吸収するための
/// 文字バリエーション表。C++ 版 `LOUDSReaderUtf16::getCharVariations` と同じ対応を持つ。
///
/// 非対称であることに注意: 入力 `か` に対しては `[か, が]` を返すが、
/// 入力 `が` に対しては `[が]` しか返さない (= 入力が "lean" で辞書が "rich" のケースだけ吸収する)。
enum KanaVariations {
    private static let pairs: [(Character, [Character])] = [
        ("か", ["か", "が"]),
        ("き", ["き", "ぎ"]),
        ("く", ["く", "ぐ"]),
        ("け", ["け", "げ"]),
        ("こ", ["こ", "ご"]),

        ("さ", ["さ", "ざ"]),
        ("し", ["し", "じ"]),
        ("す", ["す", "ず"]),
        ("せ", ["せ", "ぜ"]),
        ("そ", ["そ", "ぞ"]),

        ("た", ["た", "だ"]),
        ("ち", ["ち", "ぢ"]),
        ("つ", ["つ", "づ", "っ"]),
        ("て", ["て", "で"]),
        ("と", ["と", "ど"]),

        ("は", ["は", "ば", "ぱ"]),
        ("ひ", ["ひ", "び", "ぴ"]),
        ("ふ", ["ふ", "ぶ", "ぷ"]),
        ("へ", ["へ", "べ", "ぺ"]),
        ("ほ", ["ほ", "ぼ", "ぽ"]),

        ("や", ["や", "ゃ"]),
        ("ゆ", ["ゆ", "ゅ"]),
        ("よ", ["よ", "ょ"]),

        ("あ", ["あ", "ぁ"]),
        ("い", ["い", "ぃ"]),
        ("う", ["う", "ぅ"]),
        ("え", ["え", "ぇ"]),
        ("お", ["お", "ぉ"])
    ]

    private static let byCharacter: [Character: [Character]] = Dictionary(
        uniqueKeysWithValues: pairs
    )

    private static let byCodeUnit: [UInt16: [UInt16]] = {
        var result: [UInt16: [UInt16]] = [:]
        for (key, values) in pairs {
            guard let keyUnit = key.utf16.first else {
                continue
            }
            let valueUnits = values.compactMap { $0.utf16.first }
            result[keyUnit] = valueUnits
        }
        return result
    }()

    /// 指定された文字に対する置換候補を返す。常に最初の要素は自分自身。
    static func variations(for character: Character) -> [Character] {
        byCharacter[character] ?? [character]
    }

    /// UTF-16 code unit 単位の置換候補を返す (artifact backend 用)。
    static func variations(for codeUnit: UInt16) -> [UInt16] {
        byCodeUnit[codeUnit] ?? [codeUnit]
    }
}

struct LOUDSTrie<Value: Sendable>: Sendable {
    struct PrefixMatch: Sendable {
        let length: Int
        let value: Value
    }

    /// omission-aware search の結果。
    /// `replaceCount` は C++ 版と同じく「置換が必要だった文字数」を指す。
    struct OmissionMatch: Sendable {
        let length: Int
        let replaceCount: Int
        let value: Value
    }

    private final class BuildNode {
        var value: Value?
        var children: [Character: BuildNode] = [:]
    }

    let bitVector: LOUDSBitVector
    let labels: [Character]

    private let values: [Value?]

    var nodeCount: Int {
        values.count
    }

    init(_ pairs: [(key: String, value: Value)]) {
        let root = BuildNode()

        for pair in pairs {
            var node = root
            for character in pair.key {
                if let child = node.children[character] {
                    node = child
                } else {
                    let child = BuildNode()
                    node.children[character] = child
                    node = child
                }
            }
            node.value = pair.value
        }

        var bits: [Bool] = []
        var labels: [Character] = []
        var values: [Value?] = []

        var queue = [root]
        var index = 0

        while index < queue.count {
            let node = queue[index]
            values.append(node.value)

            let children = node.children.sorted {
                String($0.key) < String($1.key)
            }

            for (label, child) in children {
                bits.append(true)
                labels.append(label)
                queue.append(child)
            }
            bits.append(false)

            index += 1
        }

        self.bitVector = LOUDSBitVector(bits: bits)
        self.labels = labels
        self.values = values
    }

    init(bitCount: Int, words: [UInt64], labels: [Character], values: [Value?]) {
        self.bitVector = LOUDSBitVector(bitCount: bitCount, words: words)
        self.labels = labels
        self.values = values
    }

    var packedWords: [UInt64] {
        bitVector.packedWords
    }

    var optionalValues: [Value?] {
        values
    }

    func value(for key: String) -> Value? {
        guard let nodeIndex = nodeIndex(for: key) else {
            return nil
        }
        return values[nodeIndex]
    }

    func commonPrefixSearch(in characters: [Character], from start: Int) -> [PrefixMatch] {
        guard start < characters.count else {
            return []
        }

        var nodeIndex = 0
        var matches: [PrefixMatch] = []

        for index in start..<characters.count {
            guard let childIndex = child(of: nodeIndex, matching: characters[index]) else {
                break
            }

            nodeIndex = childIndex
            if let value = values[nodeIndex] {
                matches.append(PrefixMatch(length: index - start + 1, value: value))
            }
        }

        return matches
    }

    func predictiveSearch(prefix: String, limit: Int = .max) -> [(key: String, value: Value)] {
        guard limit > 0, let startNode = nodeIndex(for: prefix) else {
            return []
        }

        var results: [(key: String, value: Value)] = []
        var stack: [(nodeIndex: Int, key: String)] = [(startNode, prefix)]

        while let current = stack.popLast() {
            if let value = values[current.nodeIndex] {
                results.append((current.key, value))
                if results.count >= limit {
                    break
                }
            }

            let childIndices = children(of: current.nodeIndex).reversed()
            for childIndex in childIndices {
                let label = labels[childIndex - 1]
                stack.append((childIndex, current.key + String(label)))
            }
        }

        return results
    }

    /// 濁点 / 半濁点 / 小書きなどの揺れを吸収した common prefix search。
    ///
    /// C++ 版 `LOUDSReaderUtf16::commonPrefixSearchWithOmission` の移植。
    /// 入力文字列の各文字について `KanaVariations.variations(for:)` で置換候補を試し、
    /// トライ上でノードに着地するたびに leaf を matches に拾い集める。
    /// 同じ yomi (= 同じ node index) に複数経路で到達した場合は `replaceCount`
    /// が最小のものを採用する。
    func commonPrefixSearchWithOmission(
        in characters: [Character],
        from start: Int
    ) -> [OmissionMatch] {
        guard start <= characters.count else {
            return []
        }

        // node index → 最良の (length, replaceCount)
        var resultsByNode: [Int: (length: Int, replaceCount: Int, value: Value)] = [:]

        recursiveOmissionSearch(
            characters: characters,
            startIndex: start,
            strIndex: start,
            currentNodeIndex: 0,
            replaceCount: 0,
            results: &resultsByNode
        )

        return resultsByNode.values.map { tuple in
            OmissionMatch(length: tuple.length, replaceCount: tuple.replaceCount, value: tuple.value)
        }
    }

    private func recursiveOmissionSearch(
        characters: [Character],
        startIndex: Int,
        strIndex: Int,
        currentNodeIndex: Int,
        replaceCount: Int,
        results: inout [Int: (length: Int, replaceCount: Int, value: Value)]
    ) {
        if currentNodeIndex != 0, let value = values[currentNodeIndex] {
            let length = strIndex - startIndex
            if let existing = results[currentNodeIndex] {
                if replaceCount < existing.replaceCount {
                    results[currentNodeIndex] = (length, replaceCount, value)
                }
            } else {
                results[currentNodeIndex] = (length, replaceCount, value)
            }
        }

        guard strIndex < characters.count else {
            return
        }

        let ch = characters[strIndex]
        for variant in KanaVariations.variations(for: ch) {
            guard let childIndex = child(of: currentNodeIndex, matching: variant) else {
                continue
            }
            let replaced = (variant != ch) ? 1 : 0
            recursiveOmissionSearch(
                characters: characters,
                startIndex: startIndex,
                strIndex: strIndex + 1,
                currentNodeIndex: childIndex,
                replaceCount: replaceCount + replaced,
                results: &results
            )
        }
    }

    private func nodeIndex(for key: String) -> Int? {
        var nodeIndex = 0
        for character in key {
            guard let childIndex = child(of: nodeIndex, matching: character) else {
                return nil
            }
            nodeIndex = childIndex
        }
        return nodeIndex
    }

    private func child(of nodeIndex: Int, matching label: Character) -> Int? {
        let children = self.children(of: nodeIndex)
        guard !children.isEmpty else {
            return nil
        }

        let target = String(label)
        var lower = children.startIndex
        var upper = children.endIndex

        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let childIndex = children[middle]
            let childLabel = String(labels[childIndex - 1])

            if childLabel == target {
                return childIndex
            } else if childLabel < target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        return nil
    }

    private func children(of nodeIndex: Int) -> [Int] {
        guard nodeIndex >= 0,
              nodeIndex < values.count,
              let currentZero = bitVector.select0(nodeIndex + 1) else {
            return []
        }

        let previousZero = nodeIndex == 0 ? -1 : (bitVector.select0(nodeIndex) ?? -1)
        let firstBit = previousZero + 1
        guard firstBit < currentZero else {
            return []
        }

        let firstChild = bitVector.rank1(through: firstBit)
        let lastChild = bitVector.rank1(through: currentZero - 1)
        guard firstChild <= lastChild else {
            return []
        }

        return Array(firstChild...lastChild)
    }
}
