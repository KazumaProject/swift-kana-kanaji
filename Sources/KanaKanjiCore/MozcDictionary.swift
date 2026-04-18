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

    func prefixMatches(in characters: [Character], from start: Int) -> [PrefixMatch] {
        switch storage {
        case let .memory(trie, entryGroups):
            return trie.commonPrefixSearch(in: characters, from: start).compactMap {
                guard $0.value >= 0, $0.value < entryGroups.count else {
                    return nil
                }
                return PrefixMatch(length: $0.length, entries: entryGroups[$0.value])
            }
        case let .artifacts(artifacts):
            let suffix = String(characters[start...])
            return artifacts.prefixMatches(suffix)
        }
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
