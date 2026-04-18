import Foundation

public struct ConnectionMatrix: Sendable {
    private let dimension: Int
    private let costs: [Int]

    public init(costs: [Int]) throws {
        guard !costs.isEmpty else {
            self.dimension = 0
            self.costs = []
            return
        }

        let root = Int(Double(costs.count).squareRoot().rounded())
        guard root > 0, root * root == costs.count else {
            throw KanaKanjiError.connectionMatrixIsNotSquare(URL(fileURLWithPath: "<memory>"), count: costs.count)
        }

        self.dimension = root
        self.costs = costs
    }

    public static func loadText(
        _ fileURL: URL,
        skipFirstLine: Bool = true
    ) throws -> ConnectionMatrix {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KanaKanjiError.dictionaryNotFound(fileURL)
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        if skipFirstLine, !lines.isEmpty {
            lines.removeFirst()
        }

        var values: [Int] = []
        values.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            guard let value = Int(trimmed) else {
                continue
            }
            values.append(value)
        }

        guard !values.isEmpty else {
            throw KanaKanjiError.connectionMatrixIsEmpty(fileURL)
        }

        let root = Int(Double(values.count).squareRoot().rounded())
        guard root > 0, root * root == values.count else {
            throw KanaKanjiError.connectionMatrixIsNotSquare(fileURL, count: values.count)
        }

        return try ConnectionMatrix(costs: values)
    }

    public static func loadBinaryBigEndianInt16(_ fileURL: URL) throws -> ConnectionMatrix {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KanaKanjiError.dictionaryNotFound(fileURL)
        }

        let data = try Data(contentsOf: fileURL)
        var values: [Int] = []
        values.reserveCapacity(data.count / 2)

        var index = data.startIndex
        while index < data.endIndex {
            let next = data.index(after: index)
            guard next < data.endIndex else {
                break
            }

            let raw = UInt16(data[index]) << 8 | UInt16(data[next])
            values.append(Int(Int16(bitPattern: raw)))
            index = data.index(after: next)
        }

        guard !values.isEmpty else {
            throw KanaKanjiError.connectionMatrixIsEmpty(fileURL)
        }

        let root = Int(Double(values.count).squareRoot().rounded())
        guard root > 0, root * root == values.count else {
            throw KanaKanjiError.connectionMatrixIsNotSquare(fileURL, count: values.count)
        }

        return try ConnectionMatrix(costs: values)
    }

    public func cost(previousLeftId: Int, currentRightId: Int) -> Int {
        guard dimension > 0,
              previousLeftId >= 0,
              currentRightId >= 0,
              previousLeftId < dimension,
              currentRightId < dimension else {
            return 0
        }

        return costs[previousLeftId * dimension + currentRightId]
    }
}
