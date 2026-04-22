import Foundation

/// Identifies one of the supported dictionary kinds.
///
/// Each kind maps to a dedicated subdirectory under the root output directory and
/// produces a well-defined set of artifact files.  Only `.main` requires a
/// connection matrix; supplemental kinds share the same four-file layout.
public enum DictionaryKind: String, CaseIterable, Sendable {

    /// Main Mozc OSS dictionary.
    /// Source: ten `dictionary00.txt`–`dictionary09.txt` files plus
    /// `connection_single_column.txt`.
    case main

    /// Single-kanji supplemental dictionary.
    /// Source: a TSV file where each line is `yomi\tKANJI_STRING`.
    case singleKanji = "single_kanji"

    /// Emoji supplemental dictionary.
    /// Source: `emoji_data.tsv` — first column is the emoji glyph, remaining
    /// tab-separated columns contain space-separated yomi strings.
    case emoji

    /// Emoticon / kaomoji supplemental dictionary.
    /// Source: `emoticon.tsv` — same layout as emoji.
    case emoticon

    /// Symbol supplemental dictionary.
    /// Source: `symbol.tsv` — first column is the symbol, second column contains
    /// space-separated yomi strings.
    case symbol

    /// Reading-correction supplemental dictionary.
    /// Source: `reading_correction.tsv` — three columns:
    /// `surface\twrongYomi\tcorrectYomi`.
    case readingCorrection = "reading_correction"

    /// Kotowaza (proverb / fixed phrase) supplemental dictionary.
    /// Source: `kotowaza.tsv` — two columns: `surface\tyomi`.
    case kotowaza

    // MARK: - Properties

    /// The subdirectory name written under the root output directory.
    ///
    /// Matches `rawValue`, so e.g. `.singleKanji` → `"single_kanji"`.
    public var outputDirectoryName: String { rawValue }

    /// Whether this kind requires a `connection_single_column.bin` artifact.
    ///
    /// Only `.main` writes and loads a connection matrix.  Supplemental kinds
    /// rely on the main dictionary's connection matrix at runtime and therefore
    /// do not produce or require this file.
    public var requiresConnectionMatrix: Bool { self == .main }

    /// The artifact file names produced (and expected) for this dictionary kind.
    public var artifactFileNames: [String] {
        var names = [
            "yomi_termid.louds",
            "tango.louds",
            "token_array.bin",
            "pos_table.bin",
        ]
        if requiresConnectionMatrix {
            names.append("connection_single_column.bin")
        }
        return names
    }

    /// The default source file name within the source directory.
    ///
    /// For `.main` there are multiple source files, so this returns `nil`.
    /// For supplemental kinds this is the TSV file name to read.
    public var defaultSourceFileName: String? {
        switch self {
        case .main:             return nil
        case .singleKanji:      return "single_kanji.tsv"
        case .emoji:            return "emoji_data.tsv"
        case .emoticon:         return "emoticon.tsv"
        case .symbol:           return "symbol.tsv"
        case .readingCorrection: return "reading_correction.tsv"
        case .kotowaza:         return "kotowaza.tsv"
        }
    }

    /// Human-readable description of the kind.
    public var description: String {
        switch self {
        case .main:             return "Main Mozc OSS dictionary"
        case .singleKanji:      return "Single-kanji supplemental dictionary"
        case .emoji:            return "Emoji supplemental dictionary"
        case .emoticon:         return "Emoticon / kaomoji supplemental dictionary"
        case .symbol:           return "Symbol supplemental dictionary"
        case .readingCorrection: return "Reading-correction supplemental dictionary"
        case .kotowaza:         return "Kotowaza (proverb) supplemental dictionary"
        }
    }
}
