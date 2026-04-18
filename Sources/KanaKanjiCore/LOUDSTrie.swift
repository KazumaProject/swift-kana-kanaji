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

struct LOUDSTrie<Value: Sendable>: Sendable {
    struct PrefixMatch: Sendable {
        let length: Int
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
