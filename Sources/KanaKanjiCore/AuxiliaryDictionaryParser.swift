import Foundation

/// Parses supplemental dictionary source files into ``DictionaryEntry`` arrays.
///
/// Each static method corresponds to one ``DictionaryKind`` and handles the
/// specific TSV/text layout used by that kind.  Default left/right IDs and
/// word costs mirror the values used in the Kotlin reference implementation.
public enum AuxiliaryDictionaryParser {

    // MARK: - Emoji

    /// Parses `emoji_data.tsv`.
    ///
    /// File format (tab-separated columns):
    /// ```
    /// EMOJI    yomi1 yomi2    yomi3
    /// ```
    /// The first column is the emoji glyph (surface/tango).  Every subsequent
    /// column contains one or more yomi strings separated by ASCII spaces.
    /// One ``DictionaryEntry`` is created per (emoji, yomi) pair.
    ///
    /// Default POS: leftId = 2641, rightId = 2641, cost = 6000.
    public static func parseEmoji(from fileURL: URL) throws -> [DictionaryEntry] {
        let leftId = 2641
        let rightId = 2641
        let cost = 6000

        return try parseEmojiOrEmoticon(from: fileURL, leftId: leftId, rightId: rightId, cost: cost)
    }

    // MARK: - Emoticon

    /// Parses `emoticon.tsv`.
    ///
    /// Identical layout to `emoji_data.tsv`: first column is the emoticon
    /// string, remaining columns contain space-separated yomi strings.
    ///
    /// Default POS: leftId = 2641, rightId = 2641, cost = 4000.
    public static func parseEmoticon(from fileURL: URL) throws -> [DictionaryEntry] {
        let leftId = 2641
        let rightId = 2641
        let cost = 4000

        return try parseEmojiOrEmoticon(from: fileURL, leftId: leftId, rightId: rightId, cost: cost)
    }

    // MARK: - Symbol

    /// Parses `symbol.tsv`.
    ///
    /// File format: each non-empty line contains a symbol glyph followed by
    /// one or more whitespace characters, then a space-separated list of yomi
    /// strings.  Example:
    /// ```
    /// 、    とうてん , 、 ， てん
    /// ```
    /// One ``DictionaryEntry`` is created per (symbol, yomi) pair.
    ///
    /// Default POS: leftId = 2641, rightId = 2641, cost = 4000.
    public static func parseSymbol(from fileURL: URL) throws -> [DictionaryEntry] {
        let leftId = 2641
        let rightId = 2641
        let cost = 4000

        let text = try loadText(from: fileURL)
        var entries: [DictionaryEntry] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Split on the first run of whitespace to separate symbol from yomis.
            // Using a 2-part limit so a symbol that contains whitespace is preserved.
            let parts = line.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let tango = parts[0]
            let yomis = parts.dropFirst()

            for yomi in yomis {
                let trimmed = yomi.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                entries.append(DictionaryEntry(
                    yomi: trimmed,
                    leftId: leftId,
                    rightId: rightId,
                    cost: cost,
                    surface: tango
                ))
            }
        }

        return entries
    }

    // MARK: - Reading Correction

    /// Parses `reading_correction.tsv`.
    ///
    /// File format (three tab-separated columns):
    /// ```
    /// surface    wrongYomi    correctYomi
    /// ```
    /// The `yomi` field of the entry is set to `wrongYomi` (the incorrect
    /// reading a user might type).  The `surface` is encoded as
    /// `"surface\tcorrectYomi"` so that consumers can recover the display
    /// text and the canonical reading simultaneously — matching the behaviour
    /// of the Kotlin reference implementation.
    ///
    /// Default POS: leftId = 1851, rightId = 1851, cost = 4000.
    public static func parseReadingCorrection(from fileURL: URL) throws -> [DictionaryEntry] {
        let leftId = 1851
        let rightId = 1851
        let cost = 4000

        let text = try loadText(from: fileURL)
        var entries: [DictionaryEntry] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard !line.isEmpty else { continue }

            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }

            let surface = String(parts[0])
            let wrongYomi = String(parts[1])
            let correctYomi = String(parts[2])

            // Surface is encoded as "表示テキスト\t正しい読み" to preserve both
            // the display text and the canonical reading in a single field,
            // consistent with the Kotlin reference implementation.
            let encodedSurface = surface + "\t" + correctYomi

            entries.append(DictionaryEntry(
                yomi: wrongYomi,
                leftId: leftId,
                rightId: rightId,
                cost: cost,
                surface: encodedSurface
            ))
        }

        return entries
    }

    // MARK: - Kotowaza

    /// Parses `kotowaza.tsv`.
    ///
    /// File format (two tab-separated columns):
    /// ```
    /// surface    yomi
    /// ```
    ///
    /// Default POS: leftId = 1851, rightId = 1851, cost = 3000.
    public static func parseKotowaza(from fileURL: URL) throws -> [DictionaryEntry] {
        let leftId = 1851
        let rightId = 1851
        let cost = 3000

        let text = try loadText(from: fileURL)
        var entries: [DictionaryEntry] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard !line.isEmpty else { continue }

            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let surface = String(parts[0])
            let yomi = String(parts[1])

            entries.append(DictionaryEntry(
                yomi: yomi,
                leftId: leftId,
                rightId: rightId,
                cost: cost,
                surface: surface
            ))
        }

        return entries
    }

    // MARK: - Single Kanji

    /// Parses a single-kanji TSV file.
    ///
    /// File format: each line is `yomi\tKANJI_STRING` (or `yomi,KANJI_STRING`).
    /// `KANJI_STRING` is a concatenated string of individual kanji characters.
    /// One ``DictionaryEntry`` is created per (yomi, character) pair so that
    /// each kanji is addressable independently.
    ///
    /// Default POS: leftId = 1916, rightId = 1916, cost = 5000.
    public static func parseSingleKanji(from fileURL: URL) throws -> [DictionaryEntry] {
        let leftId = 1916
        let rightId = 1916
        let cost = 5000

        let text = try loadText(from: fileURL)
        var entries: [DictionaryEntry] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard !line.isEmpty else { continue }

            // Support both tab-separated and comma-separated formats.
            let separator: Character = line.contains("\t") ? "\t" : ","
            let parts = line.split(separator: separator, omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }

            let yomi = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let kanjiString = String(parts[1]).trimmingCharacters(in: .whitespaces)
            guard !yomi.isEmpty, !kanjiString.isEmpty else { continue }

            for character in kanjiString {
                entries.append(DictionaryEntry(
                    yomi: yomi,
                    leftId: leftId,
                    rightId: rightId,
                    cost: cost,
                    surface: String(character)
                ))
            }
        }

        return entries
    }

    // MARK: - Dispatch

    /// Parses entries for any supplemental ``DictionaryKind`` from the given file.
    ///
    /// - Parameters:
    ///   - kind: Must not be `.main`; use ``MozcDictionary/buildArtifacts(from:to:)``
    ///     for the main dictionary.
    ///   - fileURL: Path to the source TSV file.
    /// - Throws: ``KanaKanjiError/unsupportedKindForParsing(_:)`` when called
    ///   with `.main`.
    public static func parse(kind: DictionaryKind, from fileURL: URL) throws -> [DictionaryEntry] {
        switch kind {
        case .main:
            throw KanaKanjiError.unsupportedKindForParsing(kind)
        case .singleKanji:
            return try parseSingleKanji(from: fileURL)
        case .emoji:
            return try parseEmoji(from: fileURL)
        case .emoticon:
            return try parseEmoticon(from: fileURL)
        case .symbol:
            return try parseSymbol(from: fileURL)
        case .readingCorrection:
            return try parseReadingCorrection(from: fileURL)
        case .kotowaza:
            return try parseKotowaza(from: fileURL)
        }
    }

    // MARK: - Private helpers

    /// Shared parser for emoji and emoticon files (identical layout).
    private static func parseEmojiOrEmoticon(
        from fileURL: URL,
        leftId: Int,
        rightId: Int,
        cost: Int
    ) throws -> [DictionaryEntry] {
        let text = try loadText(from: fileURL)
        var entries: [DictionaryEntry] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard !line.isEmpty else { continue }

            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard !columns.isEmpty else { continue }

            let tango = String(columns[0]).trimmingCharacters(in: .whitespaces)
            guard !tango.isEmpty else { continue }

            // Each subsequent tab-separated column may hold multiple yomis
            // separated by ASCII spaces.
            for column in columns.dropFirst() {
                let yomis = column.split(separator: " ")
                for yomi in yomis {
                    let trimmed = String(yomi).trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    entries.append(DictionaryEntry(
                        yomi: trimmed,
                        leftId: leftId,
                        rightId: rightId,
                        cost: cost,
                        surface: tango
                    ))
                }
            }
        }

        return entries
    }

    private static func loadText(from fileURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KanaKanjiError.dictionaryNotFound(fileURL)
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
