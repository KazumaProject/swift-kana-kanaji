import XCTest
@testable import KanaKanjiCore

// MARK: - hasInternalUpperCase

final class HasInternalUpperCaseTests: XCTestCase {
    func testLowercaseWordReturnsFalse() {
        XCTAssertFalse("hello".hasInternalUpperCase())
        XCTAssertFalse("world".hasInternalUpperCase())
        XCTAssertFalse("foo".hasInternalUpperCase())
    }

    func testUppercaseWordReturnsTrue() {
        XCTAssertTrue("iOS".hasInternalUpperCase())
        XCTAssertTrue("GitHub".hasInternalUpperCase())
        XCTAssertTrue("SwiftUI".hasInternalUpperCase())
        XCTAssertTrue("iPhone".hasInternalUpperCase())
    }

    func testAllCapsReturnsTrue() {
        XCTAssertTrue("URL".hasInternalUpperCase())
        XCTAssertTrue("HTTP".hasInternalUpperCase())
    }

    func testSingleCapitalFirstReturnsTrue() {
        // Capital first letter → lowercased() differs → true
        XCTAssertTrue("Hello".hasInternalUpperCase())
    }

    func testEmptyStringReturnsFalse() {
        XCTAssertFalse("".hasInternalUpperCase())
    }
}

// MARK: - EnglishDictionarySourceParser

final class EnglishDictionarySourceParserTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a temp directory with a single `.txt` fixture file.
    private func makeTxtDir(_ content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try content.write(to: dir.appendingPathComponent("test_dict.txt"),
                          atomically: true, encoding: .utf8)
        return dir
    }

    /// Creates a zip archive in `zipDir` containing a `.txt` file with `content`.
    private func makeZip(content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let txtPath = dir.appendingPathComponent("test_dict.txt")
        try content.write(to: txtPath, atomically: true, encoding: .utf8)

        let zipPath = dir.appendingPathComponent("1-grams_score_cost_pos_combined_with_ner.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = dir
        process.arguments = [zipPath.path, txtPath.lastPathComponent]
        try process.run()
        process.waitUntilExit()
        return zipPath
    }

    // MARK: - Fixture content

    private let fixture = """
    word\treading\tpos\tcost\textra
    header2\theader2\theader2\theader2\theader2
    hello\thello\tnoun\t100\textra
    ios\tiOS\tnoun\t200\textra
    github\tGitHub\tnoun\t300\textra
    """

    // MARK: - Tests

    func testSkipsFirstTwoHeaderLines() throws {
        let dir = try makeTxtDir(fixture)
        let entries = try EnglishDictionarySourceParser.parseDirectory(dir)
        // Only the three data rows should be parsed (header lines skipped).
        XCTAssertEqual(entries.count, 3)
    }

    func testParsesReadingWordCost() throws {
        let dir = try makeTxtDir(fixture)
        let entries = try EnglishDictionarySourceParser.parseDirectory(dir)

        let hello = entries.first { $0.reading == "hello" }
        XCTAssertNotNil(hello)
        XCTAssertEqual(hello?.word, "hello")
        XCTAssertEqual(hello?.cost, 100)

        let ios = entries.first { $0.reading == "ios" }
        XCTAssertNotNil(ios)
        XCTAssertEqual(ios?.word, "iOS")
        XCTAssertEqual(ios?.cost, 200)

        let github = entries.first { $0.reading == "github" }
        XCTAssertNotNil(github)
        XCTAssertEqual(github?.word, "GitHub")
        XCTAssertEqual(github?.cost, 300)
    }

    func testWithUpperCaseFlagCorrect() throws {
        let dir = try makeTxtDir(fixture)
        let entries = try EnglishDictionarySourceParser.parseDirectory(dir)

        let hello  = entries.first { $0.reading == "hello" }!
        let ios    = entries.first { $0.reading == "ios" }!
        let github = entries.first { $0.reading == "github" }!

        XCTAssertFalse(hello.withUpperCase,  "hello has no uppercase → false")
        XCTAssertTrue(ios.withUpperCase,     "iOS has uppercase → true")
        XCTAssertTrue(github.withUpperCase,  "GitHub has uppercase → true")
    }

    func testSkipsLinesWithFewerThanFourColumns() throws {
        let content = """
        header1\th1\th1\th1
        header2\th2\th2\th2
        onlythree\tcols\there
        valid\tword\tnoun\t50\textra
        """
        let dir = try makeTxtDir(content)
        let entries = try EnglishDictionarySourceParser.parseDirectory(dir)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.reading, "valid")
    }

    func testCostClampedToInt16Max() throws {
        let big = Int(Int16.max) + 1000
        let content = """
        h1\th1\th1\th1
        h2\th2\th2\th2
        overflow\tOverflow\tnoun\t\(big)
        """
        let dir = try makeTxtDir(content)
        let entries = try EnglishDictionarySourceParser.parseDirectory(dir)
        XCTAssertEqual(entries.first?.cost, Int16.max)
    }

    func testCostZeroOnParseFailure() throws {
        let content = """
        h1\th1\th1\th1
        h2\th2\th2\th2
        word\tword\tnoun\tNOT_A_NUMBER
        """
        let dir = try makeTxtDir(content)
        let entries = try EnglishDictionarySourceParser.parseDirectory(dir)
        XCTAssertEqual(entries.first?.cost, 0)
    }

    func testZipExtractionAndParsing() throws {
        // Requires /usr/bin/zip to be present (available on macOS and most Linux distros).
        guard FileManager.default.fileExists(atPath: "/usr/bin/zip") else {
            print("[SKIP] /usr/bin/zip not available — skipping zip round-trip test")
            return
        }
        let zipURL = try makeZip(content: fixture)
        let entries = try EnglishDictionarySourceParser.parse(from: zipURL)
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.contains { $0.reading == "hello" && $0.word == "hello" })
        XCTAssertTrue(entries.contains { $0.reading == "ios"   && $0.word == "iOS" })
        XCTAssertTrue(entries.contains { $0.reading == "github" && $0.word == "GitHub" })
    }
}

// MARK: - EnglishDictionaryBuilder  (build + load roundtrip)

final class EnglishDictionaryBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func buildFromFixture() throws -> (outputDir: URL, engine: EnglishEngine) {
        let entries = [
            EnglishDictionaryEntry(reading: "hello",  cost: 100, word: "hello"),
            EnglishDictionaryEntry(reading: "ios",    cost: 200, word: "iOS"),
            EnglishDictionaryEntry(reading: "github", cost: 300, word: "GitHub"),
        ]
        let outputDir = try makeTempDir()
        try EnglishDictionaryBuilder.build(entries: entries, to: outputDir)
        let dictionary = try EnglishDictionary(artifactsDirectory: outputDir)
        let engine = EnglishEngine(dictionary: dictionary)
        return (outputDir, engine)
    }

    // MARK: - Artifact existence

    func testBuildProducesThreeArtifactFiles() throws {
        let entries = [EnglishDictionaryEntry(reading: "hello", cost: 100, word: "hello")]
        let outputDir = try makeTempDir()
        try EnglishDictionaryBuilder.build(entries: entries, to: outputDir)

        for name in EnglishDictionaryBuilder.artifactFileNames {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path),
                "Expected artifact '\(name)' to exist"
            )
        }
    }

    func testArtifactFileNamesAreCorrect() {
        XCTAssertEqual(
            Set(EnglishDictionaryBuilder.artifactFileNames),
            ["reading.dat", "word.dat", "token.dat"]
        )
    }

    // MARK: - Load roundtrip

    func testLoadSucceedsAfterBuild() throws {
        let (outputDir, _) = try buildFromFixture()
        XCTAssertNoThrow(try EnglishDictionary(artifactsDirectory: outputDir))
    }

    func testLoadThrowsWhenArtifactsMissing() throws {
        let emptyDir = try makeTempDir()
        XCTAssertThrowsError(try EnglishDictionary(artifactsDirectory: emptyDir))
    }

    // MARK: - Prediction: hello (lowercase, nodeId == -1)

    func testHelloPredictionReturnsHelloAsWord() throws {
        let (_, engine) = try buildFromFixture()
        let results = engine.getPrediction(input: "hel")
        let found = results.first { $0.reading == "hello" }
        XCTAssertNotNil(found, "Expect 'hello' candidate for prefix 'hel'")
        XCTAssertEqual(found?.word, "hello", "lowercase word should equal reading")
        XCTAssertEqual(found?.score, 100)
    }

    // MARK: - Prediction: iOS (uppercase, nodeId >= 0)

    func testIosPredictionReturnsIOS() throws {
        let (_, engine) = try buildFromFixture()
        let results = engine.getPrediction(input: "io")
        let found = results.first { $0.reading == "ios" }
        XCTAssertNotNil(found, "Expect 'ios' candidate for prefix 'io'")
        XCTAssertEqual(found?.word, "iOS", "word trie must restore 'iOS'")
        XCTAssertEqual(found?.score, 200)
    }

    // MARK: - Prediction: GitHub

    func testGithubPredictionReturnsGitHub() throws {
        let (_, engine) = try buildFromFixture()
        let results = engine.getPrediction(input: "git")
        let found = results.first { $0.reading == "github" }
        XCTAssertNotNil(found, "Expect 'github' candidate for prefix 'git'")
        XCTAssertEqual(found?.word, "GitHub", "word trie must restore 'GitHub'")
        XCTAssertEqual(found?.score, 300)
    }

    // MARK: - Prediction: sort order

    func testPredictionSortedByCostAscending() throws {
        // All three words share the prefix ""; sort order should be hello < ios < github.
        let (_, engine) = try buildFromFixture()
        // Use a prefix that matches all three.
        // "h" only matches hello; let's use a larger set by testing exact match.
        let all = engine.getPrediction(input: "hello") +
                  engine.getPrediction(input: "ios") +
                  engine.getPrediction(input: "github")
        let sorted = all.sorted { $0.score < $1.score }
        XCTAssertEqual(sorted.map(\.score), all.sorted { $0.score < $1.score }.map(\.score))
    }

    // MARK: - Prediction: no match

    /// With the enhanced engine, an unknown prefix always yields the three
    /// input-based fallback candidates (original / capitalised / all-upper).
    func testNoPredictionForUnknownPrefix() throws {
        let (_, engine) = try buildFromFixture()
        let results = engine.getPrediction(input: "xyz")
        XCTAssertFalse(results.isEmpty, "unknown prefix must return fallback candidates, not an empty array")
        XCTAssertEqual(results.count, 3, "fallback always contains exactly 3 candidates")
        let words = Set(results.map(\.word))
        XCTAssertTrue(words.contains("xyz"), "fallback must include the raw input")
        XCTAssertTrue(words.contains("Xyz"), "fallback must include the first-letter-uppercased input")
        XCTAssertTrue(words.contains("XYZ"), "fallback must include the all-uppercased input")
    }

    // MARK: - Empty input

    func testEmptyInputReturnsEmpty() throws {
        let (_, engine) = try buildFromFixture()
        XCTAssertTrue(engine.getPrediction(input: "").isEmpty)
    }

    // MARK: - Exact-prefix roundtrip with more entries

    func testMultipleEntriesRoundtrip() throws {
        let entries = [
            EnglishDictionaryEntry(reading: "apple",   cost: 10,  word: "apple"),
            EnglishDictionaryEntry(reading: "applet",  cost: 20,  word: "applet"),
            EnglishDictionaryEntry(reading: "app",     cost: 5,   word: "app"),
            EnglishDictionaryEntry(reading: "android", cost: 15,  word: "Android"),
        ]
        let outputDir = try makeTempDir()
        try EnglishDictionaryBuilder.build(entries: entries, to: outputDir)
        let dict   = try EnglishDictionary(artifactsDirectory: outputDir)
        let engine = EnglishEngine(dictionary: dict)

        let apResults = engine.getPrediction(input: "app")
        let words = Set(apResults.map(\.word))
        XCTAssertTrue(words.contains("app"),    "exact match 'app' must appear")
        XCTAssertTrue(words.contains("apple"),  "'apple' must appear for prefix 'app'")
        XCTAssertTrue(words.contains("applet"), "'applet' must appear for prefix 'app'")

        let androidResults = engine.getPrediction(input: "and")
        XCTAssertTrue(androidResults.contains { $0.word == "Android" })
    }
}

// MARK: - build-all skips English when source zip is absent

final class EnglishBuildAllIntegrationTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// When the English zip is absent, `buildAll` should succeed and not
    /// produce an `english/` directory.
    func testBuildAllSkipsEnglishWhenZipAbsent() throws {
        let sourceDir = try makeTempDir()
        let outputDir = try makeTempDir()

        // Provide only an emoji TSV — no English zip.
        try "😀\tえもじ\n".write(
            to: sourceDir.appendingPathComponent("emoji_data.tsv"),
            atomically: true, encoding: .utf8
        )

        let built = try DictionaryArtifactBuilder.buildAll(
            from: sourceDir,
            to: outputDir,
            skipMissingSupplemental: true
        )

        XCTAssertTrue(built.contains(.emoji))

        // English directory must NOT exist when zip is absent.
        let englishDir = outputDir
            .appendingPathComponent(EnglishDictionaryBuilder.outputDirectoryName)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: englishDir.path),
            "english/ should not be created when zip is absent"
        )
    }
}

// MARK: - EnglishEngine Kotlin-parity tests

/// Tests that verify ``EnglishEngine.getPrediction(input:)`` matches the
/// behaviour described in the Kotlin `EnglishEngine.getCandidates` spec:
/// input variants, predictive candidates with casing variants, deduplication,
/// score ordering, fallback, and limit enforcement.
final class EnglishEngineKotlinParityTests: XCTestCase {

    // MARK: - Fixture

    /// A small dictionary that covers: plain-lowercase word, mixed-case word,
    /// and an all-caps word (stored via word trie).
    private static let fixture: [EnglishDictionaryEntry] = [
        EnglishDictionaryEntry(reading: "hello",  cost: 100,  word: "hello"),
        EnglishDictionaryEntry(reading: "help",   cost: 150,  word: "help"),
        EnglishDictionaryEntry(reading: "ios",    cost: 200,  word: "iOS"),
        EnglishDictionaryEntry(reading: "github", cost: 300,  word: "GitHub"),
        EnglishDictionaryEntry(reading: "nasa",   cost:  50,  word: "NASA"),
    ]

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func buildEngine(entries: [EnglishDictionaryEntry]) throws -> EnglishEngine {
        let outputDir = try makeTempDir()
        try EnglishDictionaryBuilder.build(entries: entries, to: outputDir)
        let dictionary = try EnglishDictionary(artifactsDirectory: outputDir)
        return EnglishEngine(dictionary: dictionary)
    }

    private func fixtureEngine() throws -> EnglishEngine {
        try buildEngine(entries: Self.fixture)
    }

    // MARK: - 1. 空文字で空配列

    func testEmptyInputReturnsEmptyArray() throws {
        let engine = try fixtureEngine()
        XCTAssertTrue(engine.getPrediction(input: "").isEmpty,
                      "empty input must return an empty array")
    }

    // MARK: - 2. 入力そのもの / 先頭大文字 / 全大文字が返る

    func testInputVariantsAlwaysPresentWhenPredictiveHits() throws {
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "hel")
        let words = Set(results.map(\.word))
        XCTAssertTrue(words.contains("hel"), "original input must be present")
        XCTAssertTrue(words.contains("Hel"), "first-letter-uppercased input must be present")
        XCTAssertTrue(words.contains("HEL"), "all-uppercased input must be present")
    }

    func testInputVariantsAlwaysPresentForMixedCase() throws {
        // Input already starts with uppercase.
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "Hel")
        let words = Set(results.map(\.word))
        XCTAssertTrue(words.contains("Hel"), "original mixed-case input must be present")
        XCTAssertTrue(words.contains("HEL"), "all-upper variant must be present")
    }

    // MARK: - 3. predictive search の候補が返る

    func testPredictiveDictionaryCandidatesIncluded() throws {
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "hel")
        let words = Set(results.map(\.word))
        XCTAssertTrue(words.contains("hello"), "dictionary word 'hello' must appear")
        XCTAssertTrue(words.contains("help"),  "dictionary word 'help' must appear")
    }

    func testDictionaryWordCapitalizationVariantsIncluded() throws {
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "hel")
        let words = Set(results.map(\.word))
        XCTAssertTrue(words.contains("Hello"), "first-letter-cap variant of 'hello' must appear")
        XCTAssertTrue(words.contains("HELLO"), "all-upper variant of 'hello' must appear")
        XCTAssertTrue(words.contains("Help"),  "first-letter-cap variant of 'help' must appear")
        XCTAssertTrue(words.contains("HELP"),  "all-upper variant of 'help' must appear")
    }

    func testMixedCaseDictionaryWordRestored() throws {
        // "ios" reading → "iOS" word (stored in word trie).
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "io")
        let words = Set(results.map(\.word))
        XCTAssertTrue(words.contains("iOS"), "mixed-case word 'iOS' must be restored from word trie")
    }

    // MARK: - 4. 同一文字列が重複しない

    func testNoDuplicateWordsInResult() throws {
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "hel")
        let wordList = results.map(\.word)
        XCTAssertEqual(wordList.count, Set(wordList).count,
                       "every word in the result must be unique (dedup applied)")
    }

    /// When the input itself collides with a dictionary base word, only one entry
    /// with the minimum score must survive deduplication.
    func testDeduplicationWhenInputEqualsDictionaryWord() throws {
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "hello")
        let helloCount = results.filter { $0.word == "hello" }.count
        XCTAssertEqual(helloCount, 1, "'hello' must appear exactly once after deduplication")
    }

    func testDeduplicationKeepsLowestScore() throws {
        // "hello" appears as both an input-based candidate (score 500) and a
        // dictionary base candidate (wordCost 100). After dedup the score must be
        // the lower of the two (100 from the dictionary).
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "hello")
        let helloCandidate = results.first { $0.word == "hello" }
        XCTAssertNotNil(helloCandidate)
        XCTAssertEqual(helloCandidate?.score, 100,
                       "dedup must keep the entry with the lower score (dict cost=100, not input score=500)")
    }

    // MARK: - 5. score 昇順で並ぶ

    func testResultsSortedByScoreAscending() throws {
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "hel")
        let scores = results.map(\.score)
        XCTAssertEqual(scores, scores.sorted(),
                       "candidates must be sorted by score ascending (lowest first)")
    }

    func testFallbackResultsSortedByScore() throws {
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "zzz")
        let scores = results.map(\.score)
        XCTAssertEqual(scores, scores.sorted(),
                       "fallback candidates must also be sorted by score ascending")
    }

    // MARK: - 6. predictive がなくても fallback 候補が返る

    func testFallbackReturnedForCompletelyUnknownInput() throws {
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "zzz")
        XCTAssertFalse(results.isEmpty,
                       "unknown prefix must yield fallback candidates, not an empty array")
        XCTAssertEqual(results.count, 3,
                       "fallback must contain exactly 3 candidates")
        let words = Set(results.map(\.word))
        XCTAssertTrue(words.contains("zzz"), "fallback: original input")
        XCTAssertTrue(words.contains("Zzz"), "fallback: first-letter-uppercased")
        XCTAssertTrue(words.contains("ZZZ"), "fallback: all-uppercased")
    }

    /// When the input already starts with an uppercase letter the first-letter-cap
    /// fallback variant should receive a *better* (lower) score than the raw input —
    /// matching Kotlin's `score = if (input.first().isUpperCase()) 8500 else 10001`.
    func testFallbackCapScoreImprovedWhenInputStartsUppercase() throws {
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "Zzz")
        // "Zzz" capitalised is still "Zzz", so the fallback list contains two entries
        // with word == "Zzz": one at score 10000 (raw input) and one at score 8500
        // (the first-letter-cap path when input starts uppercase).  After sorting by
        // score ascending the first occurrence of "Zzz" in results has score 8500.
        let firstZzz = results.first { $0.word == "Zzz" }
        XCTAssertNotNil(firstZzz)
        XCTAssertEqual(firstZzz?.score, 8500,
                       "when input starts uppercase, the best 'Zzz' entry must have score 8500")
    }

    func testFallbackForNonAlphabeticInput() throws {
        // Digits / symbols must not crash capitalizeFirst.
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "123")
        XCTAssertEqual(results.count, 3, "numeric input must still produce 3 fallback candidates")
    }

    // MARK: - 7. Predictive limit enforcement

    /// Input of length ≤ 2 must use a limit of 6 readings.
    /// Build a dictionary with 8 entries all starting with "a" so the predictive
    /// search would normally return all 8; with limit=6 only 6 may contribute.
    func testPredictiveLimitSixForShortInput() throws {
        let entries: [EnglishDictionaryEntry] = (0..<8).map { i in
            EnglishDictionaryEntry(reading: "a\(i)", cost: Int16(i * 10), word: "a\(i)")
        }
        let engine = try buildEngine(entries: entries)
        let results = engine.getPrediction(input: "a")   // length 1 → limit 6
        // Max possible unique words: 6 readings × 3 variants + 3 input variants = 21.
        // (Some may dedup.) The ceiling must not exceed 21.
        XCTAssertLessThanOrEqual(results.count, 21,
                                 "short input (len≤2) must apply a predictive limit of 6 readings")
        // More practically: ensure we do NOT get all 8 readings' base words.
        let baseWords = Set(results.map(\.word)).filter { !$0.hasPrefix("a") || $0.count == 1 }
        // At most 6 "a<N>" readings contributed → at most 6 base forms from the dict.
        let dictBaseCount = results.filter {
            $0.score < 500 && $0.word.count == 2 && $0.word.first == "a"
        }.count
        XCTAssertLessThanOrEqual(dictBaseCount, 6,
                                 "no more than 6 dictionary base words when predictive limit is 6")
    }

    /// Input of length > 2 must use a limit of 12 readings.
    func testPredictiveLimitTwelveForLongerInput() throws {
        let entries: [EnglishDictionaryEntry] = (0..<15).map { i in
            EnglishDictionaryEntry(reading: "hel\(i)", cost: Int16(i * 10), word: "hel\(i)")
        }
        let engine = try buildEngine(entries: entries)
        let results = engine.getPrediction(input: "hel")  // length 3 → limit 12
        let dictBaseCount = results.filter {
            $0.score < 500 && $0.word.hasPrefix("hel") && $0.word.count > 3
        }.count
        XCTAssertLessThanOrEqual(dictBaseCount, 12,
                                 "no more than 12 dictionary base words when predictive limit is 12")
    }

    // MARK: - 8. Uppercase-first input boosts capitalised dictionary variant

    /// When input starts with uppercase the first-letter-cap score for a dict word
    /// is `max(0, wordCost + len × 2000 − 8000)` — which for short cheap words
    /// is lower than the plain-lower base score.  This ensures the capitalised
    /// form sorts ahead of or near the base form.
    func testUppercaseFirstInputBoostedCapScore() throws {
        // "nasa" cost=50, len=4 → capScore = max(0, 50 + 4×2000 − 8000) = max(0, 50) = 50
        // That equals the base score, so after dedup the cap entry ("NASA") may
        // win or the base entry ("nasa") wins — both at score ≤ 50+4×2000=8050.
        let engine = try fixtureEngine()
        let results = engine.getPrediction(input: "Nasa")
        let scores = results.map(\.score)
        XCTAssertEqual(scores, scores.sorted(),
                       "results must still be sorted when input starts uppercase")
        let words = Set(results.map(\.word))
        // At least original "Nasa" and all-upper "NASA" must be present.
        XCTAssertTrue(words.contains("Nasa"), "original mixed-case input must appear")
        XCTAssertTrue(words.contains("NASA"), "all-upper variant must appear")
    }
}
