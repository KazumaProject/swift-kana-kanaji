import Foundation

struct CompatibleBitVector: Sendable {
    let bitCount: Int
    let words: [UInt64]

    private let rank1ByWord: [Int]
    private let zeroPositions: [Int]
    private let onePositions: [Int]

    init(bits: [Bool]) {
        self.bitCount = bits.count

        var words = Array(repeating: UInt64(0), count: (bits.count + 63) / 64)
        var zeros: [Int] = []
        var ones: [Int] = []

        for (index, bit) in bits.enumerated() {
            if bit {
                words[index / 64] |= UInt64(1) << UInt64(index % 64)
                ones.append(index)
            } else {
                zeros.append(index)
            }
        }

        self.words = words
        self.rank1ByWord = Self.makeRank(words)
        self.zeroPositions = zeros
        self.onePositions = ones
    }

    init(bitCount: Int, words: [UInt64]) {
        self.bitCount = bitCount
        self.words = words

        var zeros: [Int] = []
        var ones: [Int] = []
        for index in 0..<bitCount {
            let bit = ((words[index / 64] >> UInt64(index % 64)) & 1) == 1
            if bit {
                ones.append(index)
            } else {
                zeros.append(index)
            }
        }

        self.rank1ByWord = Self.makeRank(words)
        self.zeroPositions = zeros
        self.onePositions = ones
    }

    func get(_ index: Int) -> Bool {
        guard index >= 0, index < bitCount else {
            return false
        }
        return ((words[index / 64] >> UInt64(index % 64)) & 1) == 1
    }

    func rank1(_ index: Int) -> Int {
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

    func rank0(_ index: Int) -> Int {
        guard index >= 0, bitCount > 0 else {
            return 0
        }
        let clamped = min(index, bitCount - 1)
        return clamped + 1 - rank1(clamped)
    }

    func select0(_ oneBasedRank: Int) -> Int {
        guard oneBasedRank > 0, oneBasedRank <= zeroPositions.count else {
            return -1
        }
        return zeroPositions[oneBasedRank - 1]
    }

    func select1(_ oneBasedRank: Int) -> Int {
        guard oneBasedRank > 0, oneBasedRank <= onePositions.count else {
            return -1
        }
        return onePositions[oneBasedRank - 1]
    }

    private static func makeRank(_ words: [UInt64]) -> [Int] {
        var rank = [0]
        rank.reserveCapacity(words.count + 1)
        for word in words {
            rank.append(rank[rank.count - 1] + word.nonzeroBitCount)
        }
        return rank
    }
}

struct CompatibleLOUDS: Sendable {
    let lbs: CompatibleBitVector
    let isLeaf: CompatibleBitVector
    let labels: [UInt16]
    let termIds: [Int32]?

    func firstChild(_ pos: Int) -> Int {
        let r1 = lbs.rank1(pos)
        guard r1 > 0 else {
            return -1
        }
        let y = lbs.select0(r1) + 1
        guard y >= 0, y < lbs.bitCount else {
            return -1
        }
        return lbs.get(y) ? y : -1
    }

    func traverse(_ pos: Int, _ codeUnit: UInt16) -> Int {
        var child = firstChild(pos)
        while child >= 0, child < lbs.bitCount, lbs.get(child) {
            let labelIndex = lbs.rank1(child)
            if labelIndex >= 0, labelIndex < labels.count, labels[labelIndex] == codeUnit {
                return child
            }
            child += 1
        }
        return -1
    }

    func commonPrefixSearchTermIds(_ codeUnits: [UInt16]) -> [(yomi: String, termId: Int)] {
        var resultUnits: [UInt16] = []
        var results: [(String, Int)] = []
        var node = 0

        for codeUnit in codeUnits {
            node = traverse(node, codeUnit)
            if node < 0 {
                break
            }

            let index = lbs.rank1(node)
            guard index >= 0, index < labels.count else {
                break
            }
            resultUnits.append(labels[index])

            if node < isLeaf.bitCount, isLeaf.get(node) {
                let nodeId = lbs.rank1(node) - 1
                if let termIds, nodeId >= 0, nodeId < termIds.count, termIds[nodeId] >= 0 {
                    let yomi = String(decoding: resultUnits, as: UTF16.self)
                    results.append((yomi, Int(termIds[nodeId])))
                }
            }
        }

        return results
    }

    func getLetter(nodeIndex: Int) -> String {
        guard nodeIndex >= 0, nodeIndex < lbs.bitCount else {
            return ""
        }

        var units: [UInt16] = []
        var current = nodeIndex

        while true {
            let nodeId = lbs.rank1(current)
            guard nodeId >= 0, nodeId < labels.count else {
                break
            }

            let codeUnit = labels[nodeId]
            if codeUnit != 0x20 {
                units.append(codeUnit)
            }

            if nodeId == 0 {
                break
            }

            let r0 = lbs.rank0(current)
            current = lbs.select1(r0)
            if current < 0 {
                break
            }
        }

        return String(decoding: units.reversed(), as: UTF16.self)
    }

    func getNodeIndex(_ text: String) -> Int {
        search(index: 2, chars: Array(text.utf16), offset: 0)
    }

    private func search(index: Int, chars: [UInt16], offset: Int) -> Int {
        var current = index
        guard !chars.isEmpty, current >= 0 else {
            return -1
        }

        while current < lbs.bitCount, lbs.get(current) {
            if offset >= chars.count {
                return current
            }

            let labelIndex = lbs.rank1(current)
            guard labelIndex >= 0, labelIndex < labels.count else {
                return -1
            }

            if chars[offset] == labels[labelIndex] {
                if offset + 1 == chars.count {
                    return current
                }

                let next = lbs.select0(labelIndex) + 1
                guard next >= 0 else {
                    return -1
                }
                return search(index: next, chars: chars, offset: offset + 1)
            }

            current += 1
        }

        return -1
    }
}

struct TokenEntry: Sendable {
    let posIndex: UInt16
    let wordCost: Int16
    let nodeIndex: Int32
}

struct CompatibleTokenArray: Sendable {
    static let hiraganaSentinel = Int32(-1)
    static let katakanaSentinel = Int32(-2)

    let posIndex: [UInt16]
    let wordCost: [Int16]
    let nodeIndex: [Int32]
    let postingsBits: CompatibleBitVector

    func tokens(forTermId termId: Int) -> [TokenEntry] {
        let p0 = postingsBits.select0(termId + 1)
        let p1 = postingsBits.select0(termId + 2)
        guard p0 >= 0, p1 >= 0 else {
            return []
        }

        let begin = postingsBits.rank1(p0)
        let end = postingsBits.rank1(p1)
        guard begin <= end else {
            return []
        }

        return (begin..<end).map {
            TokenEntry(posIndex: posIndex[$0], wordCost: wordCost[$0], nodeIndex: nodeIndex[$0])
        }
    }
}

struct CompatiblePosTable: Sendable {
    let leftIds: [Int16]
    let rightIds: [Int16]

    func ids(for index: UInt16) -> (left: Int, right: Int) {
        let i = Int(index)
        guard i < leftIds.count, i < rightIds.count else {
            return (0, 0)
        }
        return (Int(leftIds[i]), Int(rightIds[i]))
    }
}

struct MozcArtifactDictionary: Sendable {
    let yomiTerm: CompatibleLOUDS
    let tango: CompatibleLOUDS
    let tokens: CompatibleTokenArray
    let posTable: CompatiblePosTable

    func prefixMatches(_ input: String) -> [MozcDictionary.PrefixMatch] {
        yomiTerm.commonPrefixSearchTermIds(Array(input.utf16)).map { hit in
            let entries = tokens.tokens(forTermId: hit.termId).map { token -> DictionaryEntry in
                let ids = posTable.ids(for: token.posIndex)
                let surface: String
                if token.nodeIndex == CompatibleTokenArray.hiraganaSentinel {
                    surface = hit.yomi
                } else if token.nodeIndex == CompatibleTokenArray.katakanaSentinel {
                    surface = hiraganaToKatakana(hit.yomi)
                } else {
                    surface = tango.getLetter(nodeIndex: Int(token.nodeIndex))
                }
                return DictionaryEntry(
                    yomi: hit.yomi,
                    leftId: ids.left,
                    rightId: ids.right,
                    cost: Int(token.wordCost),
                    surface: surface
                )
            }.sorted {
                if $0.cost != $1.cost {
                    return $0.cost < $1.cost
                }
                return $0.surface < $1.surface
            }
            return MozcDictionary.PrefixMatch(length: hit.yomi.count, entries: entries)
        }
    }

    private func hiraganaToKatakana(_ value: String) -> String {
        let units = value.utf16.map { unit -> UInt16 in
            if (0x3041...0x3096).contains(unit) || (0x309D...0x309F).contains(unit) {
                return unit + 0x60
            }
            return unit
        }
        return String(decoding: units, as: UTF16.self)
    }
}
