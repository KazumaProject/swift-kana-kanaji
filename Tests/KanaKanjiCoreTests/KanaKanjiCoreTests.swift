import XCTest
@testable import KanaKanjiCore

final class KanaKanjiCoreTests: XCTestCase {
    func testLOUDSTrieCommonPrefixSearch() {
        let trie = LOUDSTrie([
            (key: "き", value: 1),
            (key: "きょう", value: 2),
            (key: "きょうと", value: 3),
            (key: "てんき", value: 4)
        ])

        let matches = trie.commonPrefixSearch(in: Array("きょうです"), from: 0)

        XCTAssertEqual(matches.map(\.length), [1, 3])
        XCTAssertEqual(matches.map(\.value), [1, 2])
        XCTAssertEqual(trie.bitVector.zeroCount, trie.nodeCount)
        XCTAssertEqual(trie.labels.count + 1, trie.nodeCount)
    }

    func testLOUDSTriePredictiveSearch() {
        let trie = LOUDSTrie([
            (key: "あい", value: "love"),
            (key: "あいす", value: "ice"),
            (key: "あお", value: "blue")
        ])

        let results = trie.predictiveSearch(prefix: "あい")

        XCTAssertEqual(results.map(\.key), ["あい", "あいす"])
    }

    func testConvertsWithSmallDictionary() throws {
        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "きょう", leftId: 1, rightId: 1, cost: 100, surface: "今日"),
            DictionaryEntry(yomi: "きょう", leftId: 1, rightId: 1, cost: 500, surface: "京"),
            DictionaryEntry(yomi: "の", leftId: 2, rightId: 2, cost: 10, surface: "の"),
            DictionaryEntry(yomi: "てんき", leftId: 3, rightId: 3, cost: 80, surface: "天気"),
            DictionaryEntry(yomi: "です", leftId: 2, rightId: 2, cost: 20, surface: "です")
        ])
        let matrix = try ConnectionMatrix(costs: Array(repeating: 0, count: 16))
        let converter = KanaKanjiConverter(dictionary: dictionary, connectionMatrix: matrix)

        let candidates = converter.convert("きょうのてんきです", options: ConversionOptions(limit: 3))

        XCTAssertEqual(candidates.first?.text, "今日の天気です")
        XCTAssertEqual(candidates.first?.reading, "きょうのてんきです")
    }

    func testConnectionCostChangesRanking() throws {
        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "あ", leftId: 1, rightId: 1, cost: 10, surface: "亜"),
            DictionaryEntry(yomi: "あ", leftId: 2, rightId: 2, cost: 20, surface: "阿"),
            DictionaryEntry(yomi: "い", leftId: 1, rightId: 1, cost: 10, surface: "伊")
        ])

        var costs = Array(repeating: 0, count: 9)
        costs[1 * 3 + 1] = 100
        costs[2 * 3 + 1] = 0

        let converter = try KanaKanjiConverter(
            dictionary: dictionary,
            connectionMatrix: ConnectionMatrix(costs: costs)
        )

        let candidates = converter.convert("あい", options: ConversionOptions(limit: 2))

        XCTAssertEqual(candidates.first?.text, "阿伊")
    }

    func testUnknownFallbackKeepsInputCharacter() {
        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "あ", leftId: 1, rightId: 1, cost: 10, surface: "亜")
        ])
        let converter = KanaKanjiConverter(dictionary: dictionary)

        let candidates = converter.convert("あx", options: ConversionOptions(limit: 1))

        XCTAssertEqual(candidates.first?.text, "亜x")
    }

    func testFinalCandidatesDeduplicateSameSurface() {
        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "きょう", leftId: 1, rightId: 1, cost: 500, surface: "今日"),
            DictionaryEntry(yomi: "きょう", leftId: 2, rightId: 2, cost: 100, surface: "今日")
        ])
        let converter = KanaKanjiConverter(dictionary: dictionary)

        let candidates = converter.convert("きょう", options: ConversionOptions(limit: 5))

        XCTAssertEqual(candidates.map(\.text), ["今日"])
        XCTAssertEqual(candidates.first?.score, 100)
    }

    func testLoadsMozcTSV() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("dictionary00.txt")
        try """
        # yomi\tleft\tright\tcost\tsurface
        きょう\t1\t2\t100\t今日
        てんき\t3\t4\t80\t天気

        """.write(to: file, atomically: true, encoding: .utf8)

        let dictionary = try MozcDictionary(directory: directory)

        XCTAssertEqual(dictionary.entryCount, 2)
    }

    func testLoadsMozcTSVWithExtraColumns() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("dictionary00.txt")
        try "あばんしあ\t1841\t1841\t9218\tアヴァンシア\tSPELLING_CORRECTION\n"
            .write(to: file, atomically: true, encoding: .utf8)

        let dictionary = try MozcDictionary(directory: directory)
        let converter = KanaKanjiConverter(dictionary: dictionary)

        XCTAssertEqual(dictionary.entryCount, 1)
        XCTAssertEqual(converter.convert("あばんしあ").first?.text, "アヴァンシア")
    }

    func testArtifactDictionaryRoundTripUsesBuiltLOUDSFiles() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        try """
        きょう\t1\t1\t100\t今日
        きょう\t2\t2\t500\t京
        の\t1\t1\t10\tの
        てんき\t1\t1\t80\t天気

        """.write(
            to: source.appendingPathComponent("dictionary00.txt"),
            atomically: true,
            encoding: .utf8
        )
        for index in 1..<10 {
            try "".write(
                to: source.appendingPathComponent(String(format: "dictionary%02d.txt", index)),
                atomically: true,
                encoding: .utf8
            )
        }

        try "0\n0\n0\n0\n".write(
            to: source.appendingPathComponent("connection_single_column.txt"),
            atomically: true,
            encoding: .utf8
        )

        try MozcDictionary.buildArtifacts(from: source, to: output)
        let dictionary = try MozcDictionary(artifactsDirectory: output)
        let converter = KanaKanjiConverter(dictionary: dictionary)

        let prefix = dictionary.prefixMatches(in: Array("きょう"), from: 0)
        XCTAssertEqual(prefix.first?.entries.first?.surface, "今日")
        XCTAssertEqual(dictionary.prefixMatches(in: Array("の"), from: 0).first?.entries.first?.surface, "の")
        _ = converter.convert("きょう", options: ConversionOptions(limit: 2))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("yomi_termid.louds").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("token_array.bin").path))
    }

    func testDownloadsDictionaryOSSFilesFromBaseURL() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        for fileName in MozcDictionaryDownloader.dictionaryFileNames {
            try "あ\t1\t1\t1\t亜\n".write(
                to: source.appendingPathComponent(fileName),
                atomically: true,
                encoding: .utf8
            )
        }
        try "0\n0\n0\n0\n".write(
            to: source.appendingPathComponent(MozcDictionaryDownloader.connectionFileName),
            atomically: true,
            encoding: .utf8
        )

        let files = try MozcDictionaryDownloader.downloadDictionaryOSS(
            to: destination,
            baseURL: source,
            overwrite: true
        )

        XCTAssertEqual(files.count, 11)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("dictionary00.txt").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("connection_single_column.txt").path
        ))
    }
}
