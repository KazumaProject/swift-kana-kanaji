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

/// Yomi(読み) 候補の収集方法を表す。C++ 版の `YomiSearchMode` に対応する。
///
/// - `commonPrefixOnly`: 従来通り共通接頭辞検索のみを使う (既存挙動)。
/// - `commonPrefixPlusPredictive`: 接頭辞検索に加え、入力冒頭から始まる
///   Predictive Search の結果も候補に加える。
/// - `commonPrefixPlusOmission`: 接頭辞検索に加え、濁点・半濁点・小書き文字
///   の省略を許容する omission-aware search も候補に加える。
/// - `all`: 上記 3 つを併用する。
public enum YomiSearchMode: Int, Sendable, Equatable {
    case commonPrefixOnly = 0
    case commonPrefixPlusPredictive = 1
    case commonPrefixPlusOmission = 2
    case all = 3

    var includesPredictive: Bool {
        self == .commonPrefixPlusPredictive || self == .all
    }

    var includesOmission: Bool {
        self == .commonPrefixPlusOmission || self == .all
    }
}

public struct ConversionOptions: Equatable, Sendable {
    public var limit: Int
    public var beamWidth: Int
    public var unknownWordCost: Int

    /// yomi 候補の収集モード。省略時は従来通り `commonPrefixOnly`。
    public var yomiSearchMode: YomiSearchMode

    /// Predictive Search 時に入力から取り出す接頭辞長 (文字数)。
    /// C++ 版の `predictivePrefixLen` に対応する。最低 1 文字。
    public var predictivePrefixLength: Int

    /// omission-aware search の置換 1 回あたりのコスト加算量。
    /// 実効ペナルティは `replaceCount * omissionPenaltyWeight` で word cost に加算される。
    /// C++ 版の `typo.weight` と同じ使い方。
    public var omissionPenaltyWeight: Int

    public init(
        limit: Int = 10,
        beamWidth: Int = 50,
        unknownWordCost: Int = 10_000,
        yomiSearchMode: YomiSearchMode = .commonPrefixOnly,
        predictivePrefixLength: Int = 1,
        omissionPenaltyWeight: Int = 1500
    ) {
        self.limit = limit
        self.beamWidth = beamWidth
        self.unknownWordCost = unknownWordCost
        self.yomiSearchMode = yomiSearchMode
        self.predictivePrefixLength = predictivePrefixLength
        self.omissionPenaltyWeight = omissionPenaltyWeight
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
