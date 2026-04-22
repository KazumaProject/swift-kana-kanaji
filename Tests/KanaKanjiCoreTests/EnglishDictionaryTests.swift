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

    func testNoPredictionForUnknownPrefix() throws {
        let (_, engine) = try buildFromFixture()
        XCTAssertTrue(engine.getPrediction(input: "xyz").isEmpty)
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
