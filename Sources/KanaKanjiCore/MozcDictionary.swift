import Foundation

public struct MozcDictionary: Sendable {
    public static let artifactFileNames = [
        "yomi_termid.louds",
        "tango.louds",
        "token_array.bin",
        "pos_table.bin",
        "connection_single_column.bin"
    ]

    struct PrefixMatch {
        let length: Int
        let entries: [DictionaryEntry]
        /// omission-aware search 等で生じた置換コスト (単位: replaceCount)。
        /// 通常の common prefix や predictive の結果では 0。
        let penalty: Int

        init(length: Int, entries: [DictionaryEntry], penalty: Int = 0) {
            self.length = length
            self.entries = entries
            self.penalty = penalty
        }
    }

    private enum Storage: Sendable {
        case memory(trie: LOUDSTrie<Int>, entryGroups: [[DictionaryEntry]])
        case artifacts(MozcArtifactDictionary)
    }

    private let storage: Storage

    public let entryCount: Int

    public init(entries: [DictionaryEntry]) {
        var grouped: [String: [DictionaryEntry]] = [:]
        grouped.reserveCapacity(entries.count)

        for entry in entries {
            grouped[entry.yomi, default: []].append(entry)
        }

        for key in grouped.keys {
            grouped[key]?.sort {
                if $0.cost != $1.cost {
                    return $0.cost < $1.cost
                }
                return $0.surface < $1.surface
            }
        }

        let sortedGroups = grouped
            .map { (yomi: $0.key, entries: $0.value) }
            .sorted { $0.yomi < $1.yomi }

        let entryGroups = sortedGroups.map(\.entries)
        let pairs = sortedGroups.enumerated().map { index, group in
            (key: group.yomi, value: index)
        }

        self.storage = .memory(trie: LOUDSTrie(pairs), entryGroups: entryGroups)
        self.entryCount = entries.count
    }

    public init(directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw KanaKanjiError.dictionaryNotFound(directory)
        }

        let fileNames = (0..<10).map { String(format: "dictionary%02d.txt", $0) }
        var entries: [DictionaryEntry] = []

        for fileName in fileNames {
            let fileURL = directory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }
            entries.append(contentsOf: try Self.loadTSV(fileURL))
        }

        guard !entries.isEmpty else {
            throw KanaKanjiError.noDictionaryEntries(directory)
        }

        self.init(entries: entries)
    }

    public init(artifactsDirectory directory: URL) throws {
        self.storage = .artifacts(try MozcArtifactIO.loadDictionary(from: directory))
        self.entryCount = 0
    }

    public static func buildArtifacts(from sourceDirectory: URL, to outputDirectory: URL) throws {
        try MozcArtifactIO.writeDictionaryArtifacts(from: sourceDirectory, to: outputDirectory)
    }

    public static func loadTSV(_ fileURL: URL) throws -> [DictionaryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KanaKanjiError.dictionaryNotFound(fileURL)
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var entries: [DictionaryEntry] = []

        for (offset, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let lineNumber = offset + 1
            let line = String(rawLine)
            if line.isEmpty || line.first == "#" {
                continue
            }

            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 5 else {
                throw KanaKanjiError.invalidDictionaryLine(file: fileURL, line: lineNumber, text: line)
            }

            let yomi = String(columns[0])
            let leftId = try parseInt(columns[1], field: "left_id", file: fileURL, line: lineNumber)
            let rightId = try parseInt(columns[2], field: "right_id", file: fileURL, line: lineNumber)
            let cost = try parseInt(columns[3], field: "cost", file: fileURL, line: lineNumber)
            let surface = String(columns[4])

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

    /// 指定された位置から始まる yomi 候補を収集する。
    ///
    /// - Parameters:
    ///   - characters: 入力全体の文字配列。
    ///   - start: `characters` における検索開始位置。
    ///   - mode: yomi 候補の収集モード。省略時は旧来の common prefix のみ。
    ///   - predictivePrefixLength: predictive search で取り出す接頭辞長 (文字数)。
    /// - Returns: yomi ごとに重複排除済みの `PrefixMatch` のリスト。
    ///   `penalty` は omission 由来の `replaceCount` (common prefix / predictive は 0)。
    func prefixMatches(
        in characters: [Character],
        from start: Int,
        mode: YomiSearchMode = .commonPrefixOnly,
        predictivePrefixLength: Int = 1
    ) -> [PrefixMatch] {
        switch storage {
        case let .memory(trie, entryGroups):
            return memoryMatches(
                trie: trie,
                entryGroups: entryGroups,
                characters: characters,
                start: start,
                mode: mode,
                predictivePrefixLength: predictivePrefixLength
            )
        case let .artifacts(artifacts):
            let suffix = String(characters[start...])
            return artifacts.prefixMatches(
                suffix,
                mode: mode,
                predictivePrefixLength: predictivePrefixLength
            )
        }
    }

    private func memoryMatches(
        trie: LOUDSTrie<Int>,
        entryGroups: [[DictionaryEntry]],
        characters: [Character],
        start: Int,
        mode: YomiSearchMode,
        predictivePrefixLength: Int
    ) -> [PrefixMatch] {
        guard start < characters.count else {
            return []
        }

        let remaining = characters.count - start

        // value (= entry group index) -> (length, penalty)
        var collected: [Int: (length: Int, penalty: Int)] = [:]
        collected.reserveCapacity(32)

        // (A) common prefix search は常に実施
        for match in trie.commonPrefixSearch(in: characters, from: start) {
            if let existing = collected[match.value] {
                if 0 < existing.penalty {
                    collected[match.value] = (match.length, 0)
                }
            } else {
                collected[match.value] = (match.length, 0)
            }
        }

        // (B) predictive search (YomiSearchMode 設定時のみ)
        if mode.includesPredictive, remaining > 0 {
            let k = max(1, min(predictivePrefixLength, remaining))
            let prefixCharacters = characters[start..<(start + k)]
            let prefix = String(prefixCharacters)
            for result in trie.predictiveSearch(prefix: prefix) {
                let length = result.key.count
                guard length <= remaining else {
                    continue
                }
                if collected[result.value] == nil {
                    collected[result.value] = (length, 0)
                }
            }
        }

        // (C) omission-aware search (YomiSearchMode 設定時のみ)
        if mode.includesOmission {
            for match in trie.commonPrefixSearchWithOmission(in: characters, from: start) {
                guard match.length <= remaining else {
                    continue
                }
                if let existing = collected[match.value] {
                    if match.replaceCount < existing.penalty {
                        collected[match.value] = (existing.length, match.replaceCount)
                    }
                } else {
                    collected[match.value] = (match.length, match.replaceCount)
                }
            }
        }

        var result: [PrefixMatch] = []
        result.reserveCapacity(collected.count)
        for (value, tuple) in collected {
            guard value >= 0, value < entryGroups.count else {
                continue
            }
            result.append(PrefixMatch(
                length: tuple.length,
                entries: entryGroups[value],
                penalty: tuple.penalty
            ))
        }
        return result
    }

    private static func parseInt(
        _ value: Substring,
        field: String,
        file: URL,
        line: Int
    ) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed) else {
            throw KanaKanjiError.invalidInteger(field: field, value: trimmed, file: file, line: line)
        }
        return parsed
    }
}
