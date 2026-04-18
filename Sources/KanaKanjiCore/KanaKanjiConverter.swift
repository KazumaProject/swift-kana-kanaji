import Foundation

public struct KanaKanjiConverter: Sendable {
    private final class Node {
        let leftId: Int
        let rightId: Int
        let score: Int
        var forwardCost: Int
        let surface: String
        let yomi: String
        let length: Int
        let startPosition: Int
        weak var previous: Node?

        init(
            leftId: Int,
            rightId: Int,
            score: Int,
            forwardCost: Int,
            surface: String,
            yomi: String,
            length: Int,
            startPosition: Int
        ) {
            self.leftId = leftId
            self.rightId = rightId
            self.score = score
            self.forwardCost = forwardCost
            self.surface = surface
            self.yomi = yomi
            self.length = length
            self.startPosition = startPosition
        }
    }

    private final class State {
        let node: Node
        let backwardCost: Int
        let totalCost: Int
        let next: State?
        let serial: Int

        init(node: Node, backwardCost: Int, totalCost: Int, next: State?, serial: Int) {
            self.node = node
            self.backwardCost = backwardCost
            self.totalCost = totalCost
            self.next = next
            self.serial = serial
        }
    }

    private struct StateHeap {
        private var storage: [State] = []

        var isEmpty: Bool {
            storage.isEmpty
        }

        mutating func push(_ state: State) {
            storage.append(state)
            siftUp(from: storage.count - 1)
        }

        mutating func pop() -> State? {
            guard !storage.isEmpty else {
                return nil
            }
            if storage.count == 1 {
                return storage.removeLast()
            }

            let result = storage[0]
            storage[0] = storage.removeLast()
            siftDown(from: 0)
            return result
        }

        private mutating func siftUp(from index: Int) {
            var child = index
            while child > 0 {
                let parent = (child - 1) / 2
                guard Self.hasHigherPriority(storage[child], than: storage[parent]) else {
                    break
                }
                storage.swapAt(child, parent)
                child = parent
            }
        }

        private mutating func siftDown(from index: Int) {
            var parent = index
            while true {
                let left = parent * 2 + 1
                let right = left + 1
                var candidate = parent

                if left < storage.count, Self.hasHigherPriority(storage[left], than: storage[candidate]) {
                    candidate = left
                }
                if right < storage.count, Self.hasHigherPriority(storage[right], than: storage[candidate]) {
                    candidate = right
                }
                if candidate == parent {
                    return
                }

                storage.swapAt(parent, candidate)
                parent = candidate
            }
        }

        private static func hasHigherPriority(_ lhs: State, than rhs: State) -> Bool {
            if lhs.totalCost != rhs.totalCost {
                return lhs.totalCost < rhs.totalCost
            }
            if lhs.node.startPosition != rhs.node.startPosition {
                return lhs.node.startPosition < rhs.node.startPosition
            }
            if lhs.node.length != rhs.node.length {
                return lhs.node.length < rhs.node.length
            }
            return lhs.serial < rhs.serial
        }
    }

    private let dictionary: MozcDictionary
    private let connectionMatrix: ConnectionMatrix?

    public init(dictionary: MozcDictionary, connectionMatrix: ConnectionMatrix? = nil) {
        self.dictionary = dictionary
        self.connectionMatrix = connectionMatrix
    }

    public func convert(
        _ input: String,
        options: ConversionOptions = ConversionOptions()
    ) -> [ConversionCandidate] {
        guard !input.isEmpty, options.limit > 0 else {
            return []
        }

        var graph = constructGraph(input, unknownWordCost: options.unknownWordCost)
        return backwardAStar(
            graph: &graph,
            length: Array(input).count,
            nBest: options.limit,
            beamWidth: max(1, options.beamWidth)
        )
    }

    private func constructGraph(
        _ input: String,
        unknownWordCost: Int
    ) -> [[Node]] {
        let characters = Array(input)
        let length = characters.count

        var graph = Array(repeating: [Node](), count: length + 2)
        graph[0].append(makeBOS())
        graph[length + 1].append(makeEOS(position: length + 1))

        for position in 0..<length {
            let matches = dictionary.prefixMatches(in: characters, from: position)
            var foundInDictionary = false

            if !matches.isEmpty {
                foundInDictionary = true
                for match in matches {
                    let endPosition = position + match.length
                    guard endPosition <= length else {
                        continue
                    }

                    for entry in match.entries {
                        let node = Node(
                            leftId: entry.leftId,
                            rightId: entry.rightId,
                            score: entry.cost,
                            forwardCost: entry.cost,
                            surface: entry.surface,
                            yomi: entry.yomi,
                            length: match.length,
                            startPosition: position
                        )
                        addOrUpdate(node, at: endPosition, in: &graph)
                    }
                }
            }

            if !foundInDictionary {
                let yomi = String(characters[position])
                let node = Node(
                    leftId: 0,
                    rightId: 0,
                    score: unknownWordCost,
                    forwardCost: unknownWordCost,
                    surface: yomi,
                    yomi: yomi,
                    length: 1,
                    startPosition: position
                )
                graph[position + 1].append(node)
            }
        }

        return graph
    }

    private func forwardDP(graph: inout [[Node]], length: Int, beamWidth: Int) {
        let infinity = Int.max / 4
        guard length + 1 < graph.count else {
            return
        }

        for index in 1...(length + 1) {
            guard !graph[index].isEmpty else {
                continue
            }

            for node in graph[index] {
                let nodeWordCost = node.score
                var best = infinity
                var bestPrevious: Node?

                for previous in previousNodesForward(graph: graph, node: node, endIndex: index, length: length) {
                    let edge = connectionCost(previousLeftId: previous.leftId, currentRightId: node.rightId)
                    let candidate = previous.forwardCost + nodeWordCost + edge
                    if candidate < best {
                        best = candidate
                        bestPrevious = previous
                    }
                }

                node.previous = bestPrevious
                node.forwardCost = best
            }

            if index <= length, beamWidth > 0, graph[index].count > beamWidth {
                graph[index].sort { $0.forwardCost < $1.forwardCost }
                graph[index].removeSubrange(beamWidth..<graph[index].count)
            }
        }
    }

    private func backwardAStar(
        graph: inout [[Node]],
        length: Int,
        nBest: Int,
        beamWidth: Int
    ) -> [ConversionCandidate] {
        guard nBest > 0 else {
            return []
        }

        forwardDP(graph: &graph, length: length, beamWidth: beamWidth)

        guard length + 1 < graph.count, let eos = graph[length + 1].first else {
            return []
        }

        var serial = 0
        func nextSerial() -> Int {
            serial += 1
            return serial
        }

        var heap = StateHeap()
        heap.push(State(node: eos, backwardCost: 0, totalCost: 0, next: nil, serial: nextSerial()))

        var results: [ConversionCandidate] = []
        results.reserveCapacity(nBest)

        var seenSurfaces = Set<String>()
        seenSurfaces.reserveCapacity(nBest * 4)

        while let current = heap.pop() {
            let node = current.node

            if node.surface == "BOS" {
                let surface = buildSurface(fromBOSState: current)
                let yomi = buildYomi(fromBOSState: current)

                if seenSurfaces.insert(surface).inserted {
                    let score = current.totalCost + (containsDigit(surface) ? 2000 : 0)
                    results.append(ConversionCandidate(text: surface, reading: yomi, score: score))
                    if results.count >= nBest {
                        return results
                    }
                }
                continue
            }

            for previous in previousNodesBackward(graph: graph, node: node, length: length) {
                let edge = connectionCost(previousLeftId: previous.leftId, currentRightId: node.rightId)
                let backwardCost = current.backwardCost + edge + node.score
                let totalCost = backwardCost + previous.forwardCost
                heap.push(State(
                    node: previous,
                    backwardCost: backwardCost,
                    totalCost: totalCost,
                    next: current,
                    serial: nextSerial()
                ))
            }
        }

        return results.sorted {
            if $0.score != $1.score {
                return $0.score < $1.score
            }
            return $0.text < $1.text
        }
    }

    private func previousNodesForward(
        graph: [[Node]],
        node: Node,
        endIndex: Int,
        length: Int
    ) -> [Node] {
        let index = node.surface == "EOS" ? length : endIndex - node.length
        if index == 0 {
            return graph[0].prefix(1).map { $0 }
        }
        guard index >= 0, index < graph.count else {
            return []
        }
        return graph[index]
    }

    private func previousNodesBackward(
        graph: [[Node]],
        node: Node,
        length: Int
    ) -> [Node] {
        let index = node.surface == "EOS" ? length : node.startPosition
        if index == 0 {
            return graph[0].prefix(1).map { $0 }
        }
        guard index >= 0, index < graph.count else {
            return []
        }
        return graph[index]
    }

    private func addOrUpdate(_ newNode: Node, at endIndex: Int, in graph: inout [[Node]]) {
        guard endIndex >= 0, endIndex < graph.count else {
            return
        }

        if let index = graph[endIndex].firstIndex(where: {
            $0.leftId == newNode.leftId &&
                $0.rightId == newNode.rightId &&
                $0.surface == newNode.surface &&
                $0.yomi == newNode.yomi
        }) {
            if newNode.score < graph[endIndex][index].score {
                graph[endIndex][index] = newNode
            }
        } else {
            graph[endIndex].append(newNode)
        }
    }

    private func buildSurface(fromBOSState state: State) -> String {
        var result = ""
        var current = state.next
        while let state = current, state.node.surface != "EOS" {
            result += state.node.surface
            current = state.next
        }
        return result
    }

    private func buildYomi(fromBOSState state: State) -> String {
        var result = ""
        var current = state.next
        while let state = current, state.node.surface != "EOS" {
            result += state.node.yomi
            current = state.next
        }
        return result
    }

    private func connectionCost(previousLeftId: Int, currentRightId: Int) -> Int {
        connectionMatrix?.cost(previousLeftId: previousLeftId, currentRightId: currentRightId) ?? 0
    }

    private func makeBOS() -> Node {
        Node(
            leftId: 0,
            rightId: 0,
            score: 0,
            forwardCost: 0,
            surface: "BOS",
            yomi: "",
            length: 0,
            startPosition: 0
        )
    }

    private func makeEOS(position: Int) -> Node {
        Node(
            leftId: 0,
            rightId: 0,
            score: 0,
            forwardCost: 0,
            surface: "EOS",
            yomi: "",
            length: 0,
            startPosition: position
        )
    }

    private func containsDigit(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            ("0"..."9").contains(Character($0)) || (0xFF10...0xFF19).contains(Int($0.value))
        }
    }
}
