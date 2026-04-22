import Foundation

// MARK: - EnglishDictionarySourceParser

/// Parses the English n-gram dictionary source zip.
///
/// Expected zip name: `1-grams_score_cost_pos_combined_with_ner.zip`
///
/// Each `.txt` file inside the zip is tab-separated with the following layout:
/// ```
/// <header line 1>
/// <header line 2>
/// reading  word  <ignored>  cost  ...
/// ```
/// - `cols[0]` = reading (lowercase romanized form)
/// - `cols[1]` = word (original casing)
/// - `cols[3]` = word cost (integer; clamped to `Int16.max` if too large)
///
/// The first two lines of every file are skipped as headers.
/// Lines with fewer than 4 tab-separated columns are skipped.
public enum EnglishDictionarySourceParser {

    /// The expected source zip file name.
    public static let sourceFileName = "1-grams_score_cost_pos_combined_with_ner.zip"

    // MARK: - Public API

    /// Parses English dictionary entries from a zip archive.
    ///
    /// Extracts the zip to a temporary directory, then recursively parses all
    /// `.txt` files found anywhere inside.
    ///
    /// - Parameter zipURL: Path to `1-grams_score_cost_pos_combined_with_ner.zip`.
    /// - Returns: Parsed ``EnglishDictionaryEntry`` values.
    public static func parse(from zipURL: URL) throws -> [EnglishDictionaryEntry] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("eng_dict_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try extractZip(at: zipURL, to: tempDir)
        return try parseTxtFiles(in: tempDir, recursive: true)
    }

    /// Parses English dictionary entries from a directory of `.txt` files.
    ///
    /// Each file must have the same two-line header / tab-separated body format.
    /// Useful for tests with manually prepared fixtures.
    ///
    /// - Parameters:
    ///   - directory: Directory containing one or more `.txt` files.
    ///   - recursive: When `true`, subdirectories are scanned recursively (default `false`).
    public static func parseDirectory(_ directory: URL, recursive: Bool = false) throws -> [EnglishDictionaryEntry] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw KanaKanjiError.dictionaryNotFound(directory)
        }
        return try parseTxtFiles(in: directory, recursive: recursive)
    }

    // MARK: - Private helpers

    private static func parseTxtFiles(in directory: URL, recursive: Bool) throws -> [EnglishDictionaryEntry] {
        var txtFiles: [URL] = []

        if recursive {
            // Deep scan via NSDirectoryEnumerator.
            if let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator
                where url.pathExtension == "txt" {
                    txtFiles.append(url)
                }
            }
        } else {
            txtFiles = try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "txt" }
        }

        txtFiles.sort { $0.lastPathComponent < $1.lastPathComponent }

        var entries: [EnglishDictionaryEntry] = []
        for fileURL in txtFiles {
            entries.append(contentsOf: try parseTxtFile(fileURL))
        }
        return entries
    }

    // MARK: - Private

    private static func parseTxtFile(_ fileURL: URL) throws -> [EnglishDictionaryEntry] {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var entries: [EnglishDictionaryEntry] = []
        var lineIndex = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            defer { lineIndex += 1 }
            // Skip the first two header lines.
            if lineIndex < 2 { continue }

            let line = String(rawLine)
            guard !line.isEmpty else { continue }

            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 4 else { continue }

            let reading = String(cols[0])
            let word    = String(cols[1])
            guard !reading.isEmpty, !word.isEmpty else { continue }

            let cost: Int16
            if let parsed = Int(cols[3]) {
                cost = parsed > Int(Int16.max) ? Int16.max : Int16(parsed)
            } else {
                cost = 0
            }

            entries.append(EnglishDictionaryEntry(reading: reading, cost: cost, word: word))
        }

        return entries
    }

    /// Extracts a zip archive to `directory` using the system `unzip` command.
    /// Exit status 1 is acceptable (warnings but no fatal error).
    private static func extractZip(at zipURL: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", directory.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        try process.run()
        process.waitUntilExit()

        // unzip returns 0 on full success, 1 on warnings (e.g. overwritten files).
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw EnglishDictionaryError.zipExtractionFailed(
                zipURL,
                exitCode: Int(process.terminationStatus)
            )
        }
    }
}

// MARK: - EnglishDictionaryError

/// Errors specific to the English dictionary family.
public enum EnglishDictionaryError: Error, LocalizedError {
    case zipExtractionFailed(URL, exitCode: Int)
    case artifactNotFound(URL)
    case noEntries

    public var errorDescription: String? {
        switch self {
        case .zipExtractionFailed(let url, let code):
            return "Failed to extract zip at \(url.path) (exit code \(code))"
        case .artifactNotFound(let url):
            return "English dictionary artifact not found: \(url.path)"
        case .noEntries:
            return "No English dictionary entries were parsed from the source"
        }
    }
}
