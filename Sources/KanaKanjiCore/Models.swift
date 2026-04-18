import Foundation

public struct DictionaryEntry: Equatable, Sendable {
    public let yomi: String
    public let leftId: Int
    public let rightId: Int
    public let cost: Int
    public let surface: String

    public init(yomi: String, leftId: Int, rightId: Int, cost: Int, surface: String) {
        self.yomi = yomi
        self.leftId = leftId
        self.rightId = rightId
        self.cost = cost
        self.surface = surface
    }
}

public struct ConversionCandidate: Equatable, Sendable {
    public let text: String
    public let reading: String
    public let score: Int

    public init(text: String, reading: String, score: Int) {
        self.text = text
        self.reading = reading
        self.score = score
    }
}

public struct ConversionOptions: Equatable, Sendable {
    public var limit: Int
    public var beamWidth: Int
    public var unknownWordCost: Int

    public init(limit: Int = 10, beamWidth: Int = 50, unknownWordCost: Int = 10_000) {
        self.limit = limit
        self.beamWidth = beamWidth
        self.unknownWordCost = unknownWordCost
    }
}

public enum KanaKanjiError: Error, LocalizedError {
    case dictionaryNotFound(URL)
    case noDictionaryEntries(URL)
    case invalidDictionaryLine(file: URL, line: Int, text: String)
    case invalidInteger(field: String, value: String, file: URL, line: Int)
    case connectionMatrixIsEmpty(URL)
    case connectionMatrixIsNotSquare(URL, count: Int)

    public var errorDescription: String? {
        switch self {
        case .dictionaryNotFound(let url):
            return "Dictionary file or directory was not found: \(url.path)"
        case .noDictionaryEntries(let url):
            return "No Mozc dictionary entries were loaded from: \(url.path)"
        case .invalidDictionaryLine(let file, let line, let text):
            return "Invalid Mozc dictionary line at \(file.path):\(line): \(text)"
        case .invalidInteger(let field, let value, let file, let line):
            return "Invalid integer for \(field) at \(file.path):\(line): \(value)"
        case .connectionMatrixIsEmpty(let url):
            return "Connection matrix is empty: \(url.path)"
        case .connectionMatrixIsNotSquare(let url, let count):
            return "Connection matrix value count is not a square number at \(url.path): \(count)"
        }
    }
}
