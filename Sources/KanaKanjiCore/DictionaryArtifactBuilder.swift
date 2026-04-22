import Foundation

/// Builds and loads LOUDS-based dictionary artifacts for any ``DictionaryKind``.
///
/// ## Output directory layout
///
/// ``buildAll(from:to:)`` and ``build(kind:from:to:)`` write to **kind-specific
/// subdirectories** inside the root output directory:
///
/// ```
/// <output>/
///   main/
///     yomi_termid.louds
///     tango.louds
///     token_array.bin
///     pos_table.bin
///     connection_single_column.bin   ← only for main
///   single_kanji/
///     yomi_termid.louds
///     tango.louds
///     token_array.bin
///     pos_table.bin
///   emoji/     …
///   emoticon/  …
///   symbol/    …
///   reading_correction/ …
///   kotowaza/  …
/// ```
///
/// The existing flat-output path (used by ``MozcDictionary/buildArtifacts(from:to:)``
/// for backward compatibility) is **not** affected by this type.
///
/// ## Loading
///
/// Use ``load(kind:from:)`` to load a ``MozcDictionary`` from a previously built
/// kind subdirectory inside a root directory.
public enum DictionaryArtifactBuilder {

    // MARK: - Build

    /// Builds artifacts for **all** supported dictionary kinds from the given
    /// source directory.
    ///
    /// - Parameters:
    ///   - sourceDirectory: Directory containing both the Mozc main dictionary
    ///     text files (`dictionary00.txt`–`dictionary09.txt`,
    ///     `connection_single_column.txt`) and the supplemental TSV files
    ///     (`emoji_data.tsv`, `emoticon.tsv`, `symbol.tsv`,
    ///     `reading_correction.tsv`, `kotowaza.tsv`, `single_kanji.tsv`).
    ///   - outputDirectory: Root directory that receives a subdirectory for each
    ///     kind (e.g. `<output>/emoji/`).
    ///   - skipMissingSupplemental: When `true` (default), supplemental kinds
    ///     whose source TSV is absent are silently skipped.  When `false`, a
    ///     ``KanaKanjiError/dictionaryNotFound(_:)`` is thrown instead.
    /// - Returns: The ``DictionaryKind`` values that were actually built.
    @discardableResult
    public static func buildAll(
        from sourceDirectory: URL,
        to outputDirectory: URL,
        skipMissingSupplemental: Bool = true
    ) throws -> [DictionaryKind] {
        var built: [DictionaryKind] = []
        for kind in DictionaryKind.allCases {
            do {
                try build(kind: kind, from: sourceDirectory, to: outputDirectory)
                built.append(kind)
            } catch KanaKanjiError.dictionaryNotFound(_) where skipMissingSupplemental && kind != .main {
                // Source TSV for this supplemental kind is absent — skip silently.
                continue
            }
        }
        return built
    }

    /// Builds artifacts for a **single** dictionary kind.
    ///
    /// For `.main`, reads `dictionary00.txt`–`dictionary09.txt` and
    /// (optionally) `connection_single_column.txt` from `sourceDirectory`.
    /// For supplemental kinds, reads the kind's ``DictionaryKind/defaultSourceFileName``
    /// from `sourceDirectory`.
    ///
    /// Artifacts are written to `<outputDirectory>/<kind.outputDirectoryName>/`.
    ///
    /// - Parameters:
    ///   - kind: The dictionary kind to build.
    ///   - sourceDirectory: Directory containing the source files for `kind`.
    ///   - outputDirectory: Root directory; a `kind`-specific subdirectory is
    ///     created automatically.
    /// - Returns: The paths of artifact files that were written.
    @discardableResult
    public static func build(
        kind: DictionaryKind,
        from sourceDirectory: URL,
        to outputDirectory: URL
    ) throws -> [URL] {
        let kindOutputDirectory = outputDirectory.appendingPathComponent(kind.outputDirectoryName)
        try FileManager.default.createDirectory(at: kindOutputDirectory, withIntermediateDirectories: true)

        switch kind {
        case .main:
            try MozcArtifactIO.writeDictionaryArtifacts(from: sourceDirectory, to: kindOutputDirectory)

        default:
            guard let sourceFileName = kind.defaultSourceFileName else {
                throw KanaKanjiError.unsupportedKindForParsing(kind)
            }
            let sourceFile = sourceDirectory.appendingPathComponent(sourceFileName)
            let entries = try AuxiliaryDictionaryParser.parse(kind: kind, from: sourceFile)
            try MozcArtifactIO.buildAndWriteArtifacts(entries: entries, to: kindOutputDirectory)
        }

        return kind.artifactFileNames.map { kindOutputDirectory.appendingPathComponent($0) }
    }

    /// Builds artifacts from a pre-parsed list of ``DictionaryEntry`` values.
    ///
    /// This low-level overload lets callers supply their own entries without going
    /// through a file-based parser.  Artifacts are written to
    /// `<outputDirectory>/<kind.outputDirectoryName>/` for the standard subdir
    /// layout, or pass a specific kind-leaf directory directly when you prefer
    /// flat output.
    ///
    /// - Parameters:
    ///   - entries: The dictionary entries to build artifacts from.
    ///   - outputDirectory: Target directory (artifacts are written directly here,
    ///     no subdirectory is appended).
    @discardableResult
    public static func buildFromEntries(
        _ entries: [DictionaryEntry],
        to outputDirectory: URL
    ) throws -> [URL] {
        try MozcArtifactIO.buildAndWriteArtifacts(entries: entries, to: outputDirectory)
        return DictionaryKind.main.artifactFileNames
            .filter { $0 != "connection_single_column.bin" }
            .map { outputDirectory.appendingPathComponent($0) }
    }

    // MARK: - Load

    /// Loads a ``MozcDictionary`` for the given kind from its subdirectory
    /// inside `rootDirectory`.
    ///
    /// Equivalent to:
    /// ```swift
    /// try MozcDictionary(artifactsDirectory: rootDirectory.appendingPathComponent(kind.outputDirectoryName))
    /// ```
    ///
    /// - Parameters:
    ///   - kind: The dictionary kind to load.
    ///   - rootDirectory: The root output directory used when building (the same
    ///     directory passed to ``build(kind:from:to:)`` or ``buildAll(from:to:)``.
    public static func load(kind: DictionaryKind, from rootDirectory: URL) throws -> MozcDictionary {
        let kindDirectory = rootDirectory.appendingPathComponent(kind.outputDirectoryName)
        return try MozcDictionary(artifactsDirectory: kindDirectory)
    }

    /// Loads all dictionary kinds present under `rootDirectory`.
    ///
    /// Kinds whose subdirectory is absent are silently skipped.
    ///
    /// - Returns: A dictionary mapping ``DictionaryKind`` to the loaded
    ///   ``MozcDictionary``.
    public static func loadAll(from rootDirectory: URL) throws -> [DictionaryKind: MozcDictionary] {
        var result: [DictionaryKind: MozcDictionary] = [:]
        for kind in DictionaryKind.allCases {
            let kindDirectory = rootDirectory.appendingPathComponent(kind.outputDirectoryName)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: kindDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            // Only load if all required (non-connection) artifact files exist.
            let coreFiles = ["yomi_termid.louds", "tango.louds", "token_array.bin", "pos_table.bin"]
            let allPresent = coreFiles.allSatisfy {
                FileManager.default.fileExists(atPath: kindDirectory.appendingPathComponent($0).path)
            }
            guard allPresent else { continue }
            result[kind] = try MozcDictionary(artifactsDirectory: kindDirectory)
        }
        return result
    }

    // MARK: - Introspection

    /// Returns the artifact file names expected for `kind`.
    public static func artifactFileNames(for kind: DictionaryKind) -> [String] {
        kind.artifactFileNames
    }

    /// Returns the URL of the kind-specific subdirectory inside `rootDirectory`.
    public static func artifactDirectory(kind: DictionaryKind, in rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent(kind.outputDirectoryName)
    }
}
