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

    func testLOUDSTrieCommonPrefixSearchWithOmission() {
        // "が" (prefix leaf) と "がっこう" (4 字 leaf) を 1 本の trie に入れておく。
        // 入力 "かつこう" を走査すると、途中 leaf の "が" (replaceCount=1) と
        // 末尾 leaf の "がっこう" (replaceCount=2) の両方を拾えることを確認する。
        let trie = LOUDSTrie([
            (key: "が", value: 1),
            (key: "がっこう", value: 2)
        ])

        let matches = trie.commonPrefixSearchWithOmission(in: Array("かつこう"), from: 0)

        let byValue = Dictionary(uniqueKeysWithValues: matches.map { ($0.value, $0) })

        XCTAssertEqual(byValue[1]?.length, 1)
        XCTAssertEqual(byValue[1]?.replaceCount, 1, "か→が の 1 置換で leaf 'が' に到達")

        XCTAssertEqual(byValue[2]?.length, 4)
        XCTAssertEqual(byValue[2]?.replaceCount, 2, "か→が, つ→っ の 2 置換で 'がっこう' に到達")
    }

    func testLOUDSTrieOmissionSearchExactMatchHasZeroReplaceCount() {
        let trie = LOUDSTrie([
            (key: "がっこう", value: 1)
        ])

        let matches = trie.commonPrefixSearchWithOmission(in: Array("がっこう"), from: 0)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.replaceCount, 0)
        XCTAssertEqual(matches.first?.length, 4)
    }

    func testPrefixMatchesIncludesPredictiveWhenModeEnabled() {
        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "き", leftId: 1, rightId: 1, cost: 100, surface: "木"),
            DictionaryEntry(yomi: "きゃく", leftId: 1, rightId: 1, cost: 100, surface: "客")
        ])
        let characters = Array("きょう")

        let plain = dictionary.prefixMatches(in: characters, from: 0)
        XCTAssertEqual(plain.flatMap { $0.entries.map(\.surface) }, ["木"])

        let predictive = dictionary.prefixMatches(
            in: characters,
            from: 0,
            mode: .commonPrefixPlusPredictive,
            predictivePrefixLength: 1
        )
        let surfaces = Set(predictive.flatMap { $0.entries.map(\.surface) })
        XCTAssertEqual(surfaces, ["木", "客"])
        for match in predictive {
            XCTAssertEqual(match.penalty, 0, "predictive 経由では penalty は 0 のはず")
        }
    }

    func testPrefixMatchesFiltersPredictiveLongerThanInput() {
        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "きゃく", leftId: 1, rightId: 1, cost: 100, surface: "客")
        ])
        // 入力は 1 文字なので "きゃく"(3 文字) は predictive からも除外される。
        let predictive = dictionary.prefixMatches(
            in: Array("き"),
            from: 0,
            mode: .commonPrefixPlusPredictive,
            predictivePrefixLength: 1
        )
        XCTAssertTrue(predictive.isEmpty)
    }

    func testPrefixMatchesIncludesOmissionWithPenalty() {
        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "がっこう", leftId: 1, rightId: 1, cost: 100, surface: "学校")
        ])
        let characters = Array("かつこう")

        let plain = dictionary.prefixMatches(in: characters, from: 0)
        XCTAssertTrue(plain.isEmpty, "濁点/小書き省略を使わないと一致しないはず")

        let omission = dictionary.prefixMatches(
            in: characters,
            from: 0,
            mode: .commonPrefixPlusOmission
        )
        XCTAssertEqual(omission.count, 1)
        XCTAssertEqual(omission.first?.length, 4)
        XCTAssertEqual(omission.first?.entries.first?.surface, "学校")
        XCTAssertEqual(omission.first?.penalty, 2, "か→が と つ→っ の 2 置換")
    }

    func testPrefixMatchesAllModeMergesWithMinPenalty() {
        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "かこ", leftId: 1, rightId: 1, cost: 100, surface: "過去")
        ])

        // 入力 "かこ" は common prefix でも omission でも同じ yomi "かこ" に到達する。
        // .all の場合、penalty は小さい方 (= 0) にマージされるはず。
        let matches = dictionary.prefixMatches(
            in: Array("かこ"),
            from: 0,
            mode: .all,
            predictivePrefixLength: 1
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.penalty, 0)
        XCTAssertEqual(matches.first?.entries.first?.surface, "過去")
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

    func testConverterPredictiveModeAddsNonPrefixCandidate() throws {
        // 入力 "きょう" に対し、common prefix だけでは "木" しか辞書に当たらない。
        // predictive を有効にすると "客" も候補になるため、変換結果に現れうる。
        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "き", leftId: 1, rightId: 1, cost: 5000, surface: "木"),
            DictionaryEntry(yomi: "きゃく", leftId: 1, rightId: 1, cost: 100, surface: "客")
        ])
        let matrix = try ConnectionMatrix(costs: Array(repeating: 0, count: 4))
        let converter = KanaKanjiConverter(dictionary: dictionary, connectionMatrix: matrix)

        let plain = converter.convert(
            "きょう",
            options: ConversionOptions(limit: 5, yomiSearchMode: .commonPrefixOnly)
        )
        XCTAssertFalse(
            plain.contains { $0.text.contains("客") },
            "common prefix のみでは '客' は現れない"
        )

        let predictive = converter.convert(
            "きょう",
            options: ConversionOptions(
                limit: 5,
                yomiSearchMode: .commonPrefixPlusPredictive,
                predictivePrefixLength: 1
            )
        )
        XCTAssertTrue(
            predictive.contains { $0.text.contains("客") },
            "predictive search を有効にすると '客' が候補に入るはず"
        )
    }

    func testConverterOmissionModeAppliesPenalty() throws {
        // 正確な入力 "がっこう" は word cost 100 で変換される。
        // 省略入力 "かつこう" を .commonPrefixPlusOmission で変換した場合、
        // 同じ surface "学校" が現れ、スコアには replaceCount * weight が加算される。
        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "がっこう", leftId: 1, rightId: 1, cost: 100, surface: "学校")
        ])
        let matrix = try ConnectionMatrix(costs: Array(repeating: 0, count: 4))
        let converter = KanaKanjiConverter(dictionary: dictionary, connectionMatrix: matrix)

        let omissionOff = converter.convert(
            "かつこう",
            options: ConversionOptions(limit: 3, yomiSearchMode: .commonPrefixOnly)
        )
        XCTAssertFalse(
            omissionOff.contains { $0.text == "学校" },
            "omission を無効にすると '学校' は現れないはず"
        )

        let omissionOn = converter.convert(
            "かつこう",
            options: ConversionOptions(
                limit: 3,
                yomiSearchMode: .commonPrefixPlusOmission,
                omissionPenaltyWeight: 1500
            )
        )
        guard let gakkou = omissionOn.first(where: { $0.text == "学校" }) else {
            XCTFail("omission ON で '学校' が候補に無い")
            return
        }
        // word cost 100 + 2 置換 * 1500 = 3100 が下限。
        // backward A* の totalCost が score に使われるため、下限以上 + 余分な BOS/EOS のコネクトコスト(0)。
        XCTAssertGreaterThanOrEqual(gakkou.score, 100 + 2 * 1500)

        let omissionLightWeight = converter.convert(
            "かつこう",
            options: ConversionOptions(
                limit: 3,
                yomiSearchMode: .commonPrefixPlusOmission,
                omissionPenaltyWeight: 0
            )
        )
        // weight=0 の場合、正確入力と同じスコア範囲に収まる
        if let gakkou0 = omissionLightWeight.first(where: { $0.text == "学校" }) {
            XCTAssertEqual(gakkou0.score, 100)
        } else {
            XCTFail("weight=0 でも '学校' は候補に残るはず")
        }
    }

    func testDefaultOptionsPreserveLegacyBehavior() {
        // 既定の ConversionOptions は従来と同じ挙動を保つ。
        let options = ConversionOptions()
        XCTAssertEqual(options.yomiSearchMode, .commonPrefixOnly)
        XCTAssertEqual(options.predictivePrefixLength, 1)
        XCTAssertEqual(options.omissionPenaltyWeight, 1500)

        let dictionary = MozcDictionary(entries: [
            DictionaryEntry(yomi: "きょう", leftId: 1, rightId: 1, cost: 500, surface: "今日")
        ])
        let converter = KanaKanjiConverter(dictionary: dictionary)

        let candidates = converter.convert("きょう")
        XCTAssertEqual(candidates.first?.text, "今日")
        XCTAssertEqual(candidates.first?.score, 500)
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

    func testArtifactDictionarySupportsPredictiveAndOmission() throws {
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
        き\t1\t1\t100\t木
        きゃく\t1\t1\t100\t客
        がっこう\t1\t1\t100\t学校

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
        try "0\n0\n".write(
            to: source.appendingPathComponent("connection_single_column.txt"),
            atomically: true,
            encoding: .utf8
        )

        try MozcDictionary.buildArtifacts(from: source, to: output)
        let dictionary = try MozcDictionary(artifactsDirectory: output)

        // predictive
        let predictive = dictionary.prefixMatches(
            in: Array("きょう"),
            from: 0,
            mode: .commonPrefixPlusPredictive,
            predictivePrefixLength: 1
        )
        let predictiveSurfaces = Set(predictive.flatMap { $0.entries.map(\.surface) })
        XCTAssertTrue(predictiveSurfaces.contains("木"))
        XCTAssertTrue(predictiveSurfaces.contains("客"))

        // omission
        let omission = dictionary.prefixMatches(
            in: Array("かつこう"),
            from: 0,
            mode: .commonPrefixPlusOmission
        )
        let omissionSurfaces = Set(omission.flatMap { $0.entries.map(\.surface) })
        XCTAssertTrue(omissionSurfaces.contains("学校"))
        // replaceCount=2 が penalty として載っているはず
        XCTAssertEqual(omission.first(where: { $0.entries.contains { $0.surface == "学校" } })?.penalty, 2)
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
