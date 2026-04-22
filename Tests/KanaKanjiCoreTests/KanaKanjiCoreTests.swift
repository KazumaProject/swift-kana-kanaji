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

// MARK: - AuxiliaryDictionaryParser tests

final class AuxiliaryDictionaryParserTests: XCTestCase {

    // MARK: Helpers

    private func writeTemp(_ content: String, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Emoji

    func testParseEmojiBasic() throws {
        // First column is the emoji; subsequent tab-separated columns hold
        // space-separated yomi strings.
        let tsv = "#️⃣\t# かこみすうじ しゃーぷ\n©️\tCまーく きごう\n"
        let url = try writeTemp(tsv, name: "emoji_data.tsv")

        let entries = try AuxiliaryDictionaryParser.parseEmoji(from: url)

        // "#️⃣" should yield 3 entries (one per yomi token in the column)
        let hashEntries = entries.filter { $0.surface == "#️⃣" }
        XCTAssertEqual(hashEntries.count, 3)
        XCTAssertTrue(hashEntries.contains { $0.yomi == "#" })
        XCTAssertTrue(hashEntries.contains { $0.yomi == "かこみすうじ" })
        XCTAssertTrue(hashEntries.contains { $0.yomi == "しゃーぷ" })

        // Default POS IDs and cost
        XCTAssertEqual(hashEntries.first?.leftId, 2641)
        XCTAssertEqual(hashEntries.first?.rightId, 2641)
        XCTAssertEqual(hashEntries.first?.cost, 6000)
    }

    func testParseEmojiMultipleYomiColumns() throws {
        // Two yomi columns, each with multiple space-separated yomis
        let tsv = "😀\tえもじ わらい\tにこにこ\n"
        let url = try writeTemp(tsv, name: "emoji_data.tsv")

        let entries = try AuxiliaryDictionaryParser.parseEmoji(from: url)

        XCTAssertEqual(entries.count, 3)
        let yomis = Set(entries.map(\.yomi))
        XCTAssertEqual(yomis, ["えもじ", "わらい", "にこにこ"])
    }

    // MARK: Emoticon

    func testParseEmoticonBasic() throws {
        let tsv = "＼(^o^)／\tにこにこ にこっ ばんざい\n(^o^)\tにこにこ にこっ\n"
        let url = try writeTemp(tsv, name: "emoticon.tsv")

        let entries = try AuxiliaryDictionaryParser.parseEmoticon(from: url)

        let firstEntries = entries.filter { $0.surface == "＼(^o^)／" }
        XCTAssertEqual(firstEntries.count, 3)
        XCTAssertEqual(firstEntries.first?.cost, 4000)  // emoticon cost ≠ emoji cost
    }

    func testParseEmoticonSkipsEmptyYomi() throws {
        // Trailing tab with no yomi should not produce empty-yomi entries
        let tsv = "(^^)\tにこ \n"
        let url = try writeTemp(tsv, name: "emoticon.tsv")

        let entries = try AuxiliaryDictionaryParser.parseEmoticon(from: url)
        XCTAssertFalse(entries.contains { $0.yomi.isEmpty })
    }

    // MARK: Symbol

    func testParseSymbolBasic() throws {
        let tsv = "、\tとうてん , 、 てん\n。\tくてん . まる\n"
        let url = try writeTemp(tsv, name: "symbol.tsv")

        let entries = try AuxiliaryDictionaryParser.parseSymbol(from: url)

        let tenEntries = entries.filter { $0.surface == "、" }
        XCTAssertTrue(tenEntries.count >= 3)
        XCTAssertTrue(tenEntries.contains { $0.yomi == "とうてん" })
        XCTAssertTrue(tenEntries.contains { $0.yomi == "," })

        XCTAssertEqual(tenEntries.first?.leftId, 2641)
        XCTAssertEqual(tenEntries.first?.cost, 4000)
    }

    func testParseSymbolSkipsEmptyLines() throws {
        let tsv = "？\tはてな\n\n！\tびっくり\n"
        let url = try writeTemp(tsv, name: "symbol.tsv")

        let entries = try AuxiliaryDictionaryParser.parseSymbol(from: url)
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: Reading Correction

    func testParseReadingCorrectionThreeColumns() throws {
        // Format: surface \t wrongYomi \t correctYomi
        let tsv = "お土産\tおどさん\tおみやげ\n一応\tいちよう\tいちおう\n"
        let url = try writeTemp(tsv, name: "reading_correction.tsv")

        let entries = try AuxiliaryDictionaryParser.parseReadingCorrection(from: url)

        XCTAssertEqual(entries.count, 2)

        let first = entries[0]
        // yomi is the wrong reading
        XCTAssertEqual(first.yomi, "おどさん")
        // surface encodes the display text and correct reading, tab-separated
        XCTAssertTrue(first.surface.contains("\t"))
        let parts = first.surface.split(separator: "\t", omittingEmptySubsequences: false)
        XCTAssertEqual(String(parts[0]), "お土産")
        XCTAssertEqual(String(parts[1]), "おみやげ")

        XCTAssertEqual(first.leftId, 1851)
        XCTAssertEqual(first.cost, 4000)
    }

    func testParseReadingCorrectionSkipsMalformedLines() throws {
        // Lines with != 3 columns should be skipped
        let tsv = "お土産\tおどさん\tおみやげ\nonly_one_col\n"
        let url = try writeTemp(tsv, name: "reading_correction.tsv")

        let entries = try AuxiliaryDictionaryParser.parseReadingCorrection(from: url)
        XCTAssertEqual(entries.count, 1)
    }

    // MARK: Kotowaza

    func testParseKotowazaTwoColumns() throws {
        let tsv = "七味とうがらし\tしちみとうがらし\n一期一会\tいちごいちえ\n"
        let url = try writeTemp(tsv, name: "kotowaza.tsv")

        let entries = try AuxiliaryDictionaryParser.parseKotowaza(from: url)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].surface, "七味とうがらし")
        XCTAssertEqual(entries[0].yomi, "しちみとうがらし")
        XCTAssertEqual(entries[0].leftId, 1851)
        XCTAssertEqual(entries[0].cost, 3000)  // kotowaza cost differs from reading_correction
    }

    // MARK: Single Kanji

    func testParseSingleKanjiTabSeparated() throws {
        // Format: yomi \t KANJI_STRING  — each character in KANJI_STRING is an entry
        let tsv = "あ\t亜哀挨\nい\t以位\n"
        let url = try writeTemp(tsv, name: "single_kanji.tsv")

        let entries = try AuxiliaryDictionaryParser.parseSingleKanji(from: url)

        XCTAssertEqual(entries.count, 5)  // 3 for あ + 2 for い

        let aEntries = entries.filter { $0.yomi == "あ" }
        XCTAssertEqual(aEntries.count, 3)
        XCTAssertTrue(aEntries.contains { $0.surface == "亜" })
        XCTAssertTrue(aEntries.contains { $0.surface == "哀" })
        XCTAssertTrue(aEntries.contains { $0.surface == "挨" })

        XCTAssertEqual(aEntries.first?.leftId, 1916)
        XCTAssertEqual(aEntries.first?.rightId, 1916)
        XCTAssertEqual(aEntries.first?.cost, 5000)
    }

    func testParseSingleKanjiCommaSeparated() throws {
        let csv = "う,上氏\n"
        let url = try writeTemp(csv, name: "single_kanji.tsv")

        let entries = try AuxiliaryDictionaryParser.parseSingleKanji(from: url)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.yomi == "う" })
    }

    // MARK: Dispatch

    func testParseDispatchThrowsForMain() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dummy.tsv")
        do {
            _ = try AuxiliaryDictionaryParser.parse(kind: .main, from: url)
            XCTFail("Expected error for .main kind")
        } catch KanaKanjiError.unsupportedKindForParsing(_) {
            // expected
        }
    }

    func testParseDispatchRoutesAllSupplementalKinds() throws {
        // Each supplemental kind must produce at least one entry from minimal input.
        let emojiURL   = try writeTemp("😀\tえもじ\n", name: "emoji_data.tsv")
        let emotiURL   = try writeTemp("(^^)\tにこ\n", name: "emoticon.tsv")
        let symbolURL  = try writeTemp("！\tびっくり\n", name: "symbol.tsv")
        let rcURL      = try writeTemp("お土産\tおどさん\tおみやげ\n", name: "reading_correction.tsv")
        let kotURL     = try writeTemp("一期一会\tいちごいちえ\n", name: "kotowaza.tsv")
        let skURL      = try writeTemp("あ\t亜\n", name: "single_kanji.tsv")

        let cases: [(DictionaryKind, URL)] = [
            (.emoji,             emojiURL),
            (.emoticon,          emotiURL),
            (.symbol,            symbolURL),
            (.readingCorrection, rcURL),
            (.kotowaza,          kotURL),
            (.singleKanji,       skURL),
        ]

        for (kind, url) in cases {
            let entries = try AuxiliaryDictionaryParser.parse(kind: kind, from: url)
            XCTAssertFalse(entries.isEmpty, "Expected entries for kind '\(kind.rawValue)'")
        }
    }
}

// MARK: - DictionaryArtifactBuilder build + load tests

final class DictionaryArtifactBuilderTests: XCTestCase {

    // MARK: Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func writeFile(_ content: String, name: String, in dir: URL) throws {
        try content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    // MARK: Build from entries

    func testBuildFromEntriesProducesCoreArtifacts() throws {
        let outputDir = try makeTempDir()
        let entries = [
            DictionaryEntry(yomi: "えもじ", leftId: 2641, rightId: 2641, cost: 6000, surface: "😀"),
            DictionaryEntry(yomi: "にこ",   leftId: 2641, rightId: 2641, cost: 6000, surface: "😊"),
        ]

        try DictionaryArtifactBuilder.buildFromEntries(entries, to: outputDir)

        for name in ["yomi_termid.louds", "tango.louds", "token_array.bin", "pos_table.bin"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "Expected artifact '\(name)' to exist"
            )
        }
    }

    // MARK: Build emoji

    func testBuildEmojiArtifactsAndLoad() throws {
        let sourceDir = try makeTempDir()
        let outputRoot = try makeTempDir()

        try writeFile(
            "😀\tえもじ わらい\n😊\tにこにこ\n",
            name: "emoji_data.tsv",
            in: sourceDir
        )

        try DictionaryArtifactBuilder.build(kind: .emoji, from: sourceDir, to: outputRoot)

        let emojiDir = DictionaryArtifactBuilder.artifactDirectory(kind: .emoji, in: outputRoot)
        for name in DictionaryKind.emoji.artifactFileNames {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: emojiDir.appendingPathComponent(name).path),
                "Missing artifact: \(name)"
            )
        }

        // Load and perform a lookup
        let dict = try DictionaryArtifactBuilder.load(kind: .emoji, from: outputRoot)
        let matches = dict.prefixMatches(in: Array("えもじ"), from: 0)
        let surfaces = Set(matches.flatMap { $0.entries.map(\.surface) })
        XCTAssertTrue(surfaces.contains("😀"), "Expected 😀 for 'えもじ'")
    }

    // MARK: Build emoticon

    func testBuildEmoticonArtifactsAndLoad() throws {
        let sourceDir = try makeTempDir()
        let outputRoot = try makeTempDir()

        try writeFile(
            "＼(^o^)／\tばんざい にこにこ\n(T_T)\tなく\n",
            name: "emoticon.tsv",
            in: sourceDir
        )

        try DictionaryArtifactBuilder.build(kind: .emoticon, from: sourceDir, to: outputRoot)
        let dict = try DictionaryArtifactBuilder.load(kind: .emoticon, from: outputRoot)

        let matches = dict.prefixMatches(in: Array("ばんざい"), from: 0)
        let surfaces = Set(matches.flatMap { $0.entries.map(\.surface) })
        XCTAssertTrue(surfaces.contains("＼(^o^)／"))
    }

    // MARK: Build symbol

    func testBuildSymbolArtifactsAndLoad() throws {
        let sourceDir = try makeTempDir()
        let outputRoot = try makeTempDir()

        try writeFile(
            "、\tとうてん てん\n。\tくてん まる\n",
            name: "symbol.tsv",
            in: sourceDir
        )

        try DictionaryArtifactBuilder.build(kind: .symbol, from: sourceDir, to: outputRoot)
        let dict = try DictionaryArtifactBuilder.load(kind: .symbol, from: outputRoot)

        let matches = dict.prefixMatches(in: Array("とうてん"), from: 0)
        let surfaces = Set(matches.flatMap { $0.entries.map(\.surface) })
        XCTAssertTrue(surfaces.contains("、"))
    }

    // MARK: Build reading correction

    func testBuildReadingCorrectionArtifactsAndLoad() throws {
        let sourceDir = try makeTempDir()
        let outputRoot = try makeTempDir()

        try writeFile(
            "お土産\tおどさん\tおみやげ\n一応\tいちよう\tいちおう\n",
            name: "reading_correction.tsv",
            in: sourceDir
        )

        try DictionaryArtifactBuilder.build(kind: .readingCorrection, from: sourceDir, to: outputRoot)
        let dict = try DictionaryArtifactBuilder.load(kind: .readingCorrection, from: outputRoot)

        // Wrong reading "おどさん" should map to "お土産\tおみやげ"
        let matches = dict.prefixMatches(in: Array("おどさん"), from: 0)
        XCTAssertFalse(matches.isEmpty, "Expected match for wrongYomi 'おどさん'")
        let surface = matches.first?.entries.first?.surface ?? ""
        XCTAssertTrue(surface.hasPrefix("お土産"), "Surface should start with 'お土産'")
        XCTAssertTrue(surface.contains("おみやげ"), "Surface should contain correct yomi 'おみやげ'")
    }

    // MARK: Build kotowaza

    func testBuildKotowazaArtifactsAndLoad() throws {
        let sourceDir = try makeTempDir()
        let outputRoot = try makeTempDir()

        try writeFile(
            "一期一会\tいちごいちえ\n七味とうがらし\tしちみとうがらし\n",
            name: "kotowaza.tsv",
            in: sourceDir
        )

        try DictionaryArtifactBuilder.build(kind: .kotowaza, from: sourceDir, to: outputRoot)
        let dict = try DictionaryArtifactBuilder.load(kind: .kotowaza, from: outputRoot)

        let matches = dict.prefixMatches(in: Array("いちごいちえ"), from: 0)
        let surfaces = Set(matches.flatMap { $0.entries.map(\.surface) })
        XCTAssertTrue(surfaces.contains("一期一会"))
    }

    // MARK: Build single kanji

    func testBuildSingleKanjiArtifactsAndLoad() throws {
        let sourceDir = try makeTempDir()
        let outputRoot = try makeTempDir()

        try writeFile("あ\t亜哀\nい\t以位\n", name: "single_kanji.tsv", in: sourceDir)

        try DictionaryArtifactBuilder.build(kind: .singleKanji, from: sourceDir, to: outputRoot)
        let dict = try DictionaryArtifactBuilder.load(kind: .singleKanji, from: outputRoot)

        let matches = dict.prefixMatches(in: Array("あ"), from: 0)
        let surfaces = Set(matches.flatMap { $0.entries.map(\.surface) })
        XCTAssertTrue(surfaces.contains("亜"), "Expected '亜' for yomi 'あ'")
        XCTAssertTrue(surfaces.contains("哀"), "Expected '哀' for yomi 'あ'")
    }

    // MARK: Build all (supplemental only, skip main)

    func testBuildAllSkipsMissingSourceFiles() throws {
        let sourceDir = try makeTempDir()
        let outputRoot = try makeTempDir()

        // Only provide emoji; all others are absent
        try writeFile("🎉\tぱーてぃー\n", name: "emoji_data.tsv", in: sourceDir)

        let built = try DictionaryArtifactBuilder.buildAll(
            from: sourceDir,
            to: outputRoot,
            skipMissingSupplemental: true
        )

        // main will fail (no dictionary*.txt), others missing TSVs are skipped
        XCTAssertTrue(built.contains(.emoji))
        XCTAssertFalse(built.contains(.main))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: outputRoot.appendingPathComponent(DictionaryKind.main.outputDirectoryName).path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: outputRoot.appendingPathComponent(DictionaryKind.singleKanji.outputDirectoryName).path
        ))
    }

    func testBuildAllBuildsMultipleKinds() throws {
        let sourceDir = try makeTempDir()
        let outputRoot = try makeTempDir()

        try writeFile("😀\tえもじ\n", name: "emoji_data.tsv", in: sourceDir)
        try writeFile("(^^)\tにこ\n", name: "emoticon.tsv", in: sourceDir)
        try writeFile("！\tびっくり\n", name: "symbol.tsv", in: sourceDir)

        let built = try DictionaryArtifactBuilder.buildAll(
            from: sourceDir,
            to: outputRoot,
            skipMissingSupplemental: true
        )

        XCTAssertTrue(built.contains(.emoji))
        XCTAssertTrue(built.contains(.emoticon))
        XCTAssertTrue(built.contains(.symbol))
    }

    // MARK: loadAll

    func testLoadAllReturnsOnlyBuiltKinds() throws {
        let sourceDir = try makeTempDir()
        let outputRoot = try makeTempDir()

        try writeFile("😀\tえもじ\n", name: "emoji_data.tsv", in: sourceDir)
        try writeFile("(^^)\tにこ\n", name: "emoticon.tsv", in: sourceDir)

        try DictionaryArtifactBuilder.buildAll(
            from: sourceDir,
            to: outputRoot,
            skipMissingSupplemental: true
        )

        let loaded = try DictionaryArtifactBuilder.loadAll(from: outputRoot)
        XCTAssertNotNil(loaded[.emoji])
        XCTAssertNotNil(loaded[.emoticon])
        XCTAssertNil(loaded[.main])
    }

    // MARK: DictionaryKind properties

    func testDictionaryKindOutputDirectoryName() {
        XCTAssertEqual(DictionaryKind.main.outputDirectoryName, "main")
        XCTAssertEqual(DictionaryKind.singleKanji.outputDirectoryName, "single_kanji")
        XCTAssertEqual(DictionaryKind.readingCorrection.outputDirectoryName, "reading_correction")
    }

    func testDictionaryKindRequiresConnectionMatrixOnlyForMain() {
        XCTAssertTrue(DictionaryKind.main.requiresConnectionMatrix)
        for kind in DictionaryKind.allCases where kind != .main {
            XCTAssertFalse(kind.requiresConnectionMatrix, "'\(kind.rawValue)' should not require connection matrix")
        }
    }

    func testDictionaryKindArtifactFileNamesContainConnectionOnlyForMain() {
        XCTAssertTrue(DictionaryKind.main.artifactFileNames.contains("connection_single_column.bin"))
        for kind in DictionaryKind.allCases where kind != .main {
            XCTAssertFalse(
                kind.artifactFileNames.contains("connection_single_column.bin"),
                "'\(kind.rawValue)' should not list connection_single_column.bin"
            )
        }
    }

    // MARK: MozcDictionary.load(kind:from:) convenience

    func testMozcDictionaryLoadKindConvenience() throws {
        let sourceDir = try makeTempDir()
        let outputRoot = try makeTempDir()

        try writeFile("🎉\tぱーてぃー\n", name: "emoji_data.tsv", in: sourceDir)
        try DictionaryArtifactBuilder.build(kind: .emoji, from: sourceDir, to: outputRoot)

        let dict = try MozcDictionary.load(kind: .emoji, from: outputRoot)
        let matches = dict.prefixMatches(in: Array("ぱーてぃー"), from: 0)
        let surfaces = Set(matches.flatMap { $0.entries.map(\.surface) })
        XCTAssertTrue(surfaces.contains("🎉"))
    }

    // MARK: Existing main dictionary round-trip still works

    func testMainDictionaryRoundTripUnchanged() throws {
        let sourceDir = try makeTempDir()
        let outputDir = try makeTempDir()

        try writeFile(
            "きょう\t1\t1\t100\t今日\nてんき\t1\t1\t80\t天気\n",
            name: "dictionary00.txt",
            in: sourceDir
        )
        for i in 1..<10 {
            try writeFile("", name: String(format: "dictionary%02d.txt", i), in: sourceDir)
        }
        try writeFile("0\n0\n0\n0\n", name: "connection_single_column.txt", in: sourceDir)

        // Existing flat-output API must still work unchanged
        try MozcDictionary.buildArtifacts(from: sourceDir, to: outputDir)

        for name in ["yomi_termid.louds", "tango.louds", "token_array.bin", "pos_table.bin",
                     "connection_single_column.bin"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "Missing main artifact: \(name)"
            )
        }

        let dict = try MozcDictionary(artifactsDirectory: outputDir)
        let matches = dict.prefixMatches(in: Array("きょう"), from: 0)
        XCTAssertFalse(matches.isEmpty)
        let surfaces = Set(matches.flatMap { $0.entries.map(\.surface) })
        XCTAssertTrue(surfaces.contains("今日"))
    }
}
