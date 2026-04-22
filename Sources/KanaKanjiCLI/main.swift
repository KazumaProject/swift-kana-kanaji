import Foundation
import KanaKanjiCore

// MARK: - Option structs

struct CLIOptions {
    var dictionaryDirectory: URL?
    var artifactsDirectory: URL?
    var connectionPath: URL?
    var connectionIsBinary = false
    var skipConnectionHeader = true
    var query: String?
    var limit = 10
    var beamWidth = 50
}

struct DownloadOptions {
    var outputDirectory: URL?
    var overwrite = false
}

struct BuildDictionaryOptions {
    var sourceDirectory: URL?
    var outputDirectory: URL?
}

/// Options for `build-dictionary --kind <kind> --source <dir> --output <dir>`
struct BuildKindOptions {
    var kind: DictionaryKind?
    var sourceDirectory: URL?
    var outputDirectory: URL?
}

/// Options for `build-all-dictionaries --source <dir> --output <dir>`
struct BuildAllOptions {
    var sourceDirectory: URL?
    var outputDirectory: URL?
    var skipMissing = true
}

// MARK: - Usage

func printUsage() {
    print("""
    Usage:
      kana-kanji download --output <dir> [--overwrite]

      # Build main Mozc dictionary (backward-compatible flat output):
      kana-kanji build-dictionary --source <mozc_fetch_dir> --output <artifacts_dir>

      # Build a single supplemental dictionary into <output>/<kind>/:
      kana-kanji build-dictionary --kind <kind> --source <source_dir> --output <root_output_dir>

      # Build all dictionaries into <output>/<kind>/ subdirectories:
      kana-kanji build-all-dictionaries --source <source_dir> --output <root_output_dir>

      # List supported dictionary kinds:
      kana-kanji list-dictionary-kinds

      # Run conversion (artifact mode):
      kana-kanji --artifacts-dir <dir> [--connection <path>] [--connection-binary]
                 [--query <hiragana>] [--limit N] [--beam N]

      # Run conversion (raw TSV mode):
      kana-kanji --dictionary-dir <dir> [--connection <path>] [--connection-binary]
                 [--query <hiragana>] [--limit N] [--beam N]

    Supported dictionary kinds:
    \(DictionaryKind.allCases.map { "  \($0.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)) \($0.description)" }.joined(separator: "\n"))

    Examples:
      kana-kanji download --output ./mozc_fetch
      kana-kanji build-dictionary --source ./mozc_fetch --output ./artifacts
      kana-kanji build-all-dictionaries --source ./bin_dir --output ./dict_root
      kana-kanji build-dictionary --kind emoji --source ./bin_dir --output ./dict_root
      kana-kanji --artifacts-dir ./artifacts \\
                 --connection ./artifacts/connection_single_column.bin \\
                 --connection-binary --query きょうのてんき
      echo きょうのてんき | kana-kanji --artifacts-dir ./artifacts \\
                 --connection ./artifacts/connection_single_column.bin --connection-binary
    """)
}

// MARK: - stderr helper

func stderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - Argument parsers

func parseArguments(_ arguments: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 1

    func requireValue(after flag: String) throws -> String {
        guard index + 1 < arguments.count else {
            throw NSError(domain: "KanaKanjiCLI", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Missing value after \(flag)"
            ])
        }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let arg = arguments[index]
        switch arg {
        case "--dictionary-dir":
            options.dictionaryDirectory = URL(fileURLWithPath: try requireValue(after: arg))
        case "--artifacts-dir":
            options.artifactsDirectory = URL(fileURLWithPath: try requireValue(after: arg))
        case "--connection":
            options.connectionPath = URL(fileURLWithPath: try requireValue(after: arg))
        case "--connection-binary":
            options.connectionIsBinary = true
        case "--no-skip-connection-header":
            options.skipConnectionHeader = false
        case "--query", "-q":
            options.query = try requireValue(after: arg)
        case "--limit", "-n":
            options.limit = Int(try requireValue(after: arg)) ?? options.limit
        case "--beam":
            options.beamWidth = Int(try requireValue(after: arg)) ?? options.beamWidth
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            if options.query == nil {
                options.query = arg
            } else {
                throw NSError(domain: "KanaKanjiCLI", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Unknown argument: \(arg)"
                ])
            }
        }
        index += 1
    }

    return options
}

func parseBuildDictionaryArguments(_ arguments: [String]) throws -> (BuildDictionaryOptions, BuildKindOptions?) {
    var basicOptions = BuildDictionaryOptions()
    var kindOptions = BuildKindOptions()
    var hasKind = false
    var index = 2

    func requireValue(after flag: String) throws -> String {
        guard index + 1 < arguments.count else {
            throw NSError(domain: "KanaKanjiCLI", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Missing value after \(flag)"
            ])
        }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let arg = arguments[index]
        switch arg {
        case "--source", "--dictionary-dir":
            let path = URL(fileURLWithPath: try requireValue(after: arg))
            basicOptions.sourceDirectory = path
            kindOptions.sourceDirectory = path
        case "--output", "-o", "--out-dir":
            let path = URL(fileURLWithPath: try requireValue(after: arg))
            basicOptions.outputDirectory = path
            kindOptions.outputDirectory = path
        case "--kind", "-k":
            let rawKind = try requireValue(after: arg)
            guard let kind = DictionaryKind(rawValue: rawKind) else {
                throw NSError(domain: "KanaKanjiCLI", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Unknown dictionary kind '\(rawKind)'. Run 'list-dictionary-kinds' to see supported kinds."
                ])
            }
            kindOptions.kind = kind
            hasKind = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw NSError(domain: "KanaKanjiCLI", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unknown build-dictionary argument: \(arg)"
            ])
        }
        index += 1
    }

    return (basicOptions, hasKind ? kindOptions : nil)
}

func parseBuildAllArguments(_ arguments: [String]) throws -> BuildAllOptions {
    var options = BuildAllOptions()
    var index = 2

    func requireValue(after flag: String) throws -> String {
        guard index + 1 < arguments.count else {
            throw NSError(domain: "KanaKanjiCLI", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Missing value after \(flag)"
            ])
        }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let arg = arguments[index]
        switch arg {
        case "--source", "-s":
            options.sourceDirectory = URL(fileURLWithPath: try requireValue(after: arg))
        case "--output", "-o":
            options.outputDirectory = URL(fileURLWithPath: try requireValue(after: arg))
        case "--no-skip-missing":
            options.skipMissing = false
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw NSError(domain: "KanaKanjiCLI", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unknown build-all-dictionaries argument: \(arg)"
            ])
        }
        index += 1
    }

    return options
}

func parseDownloadArguments(_ arguments: [String]) throws -> DownloadOptions {
    var options = DownloadOptions()
    var index = 2

    func requireValue(after flag: String) throws -> String {
        guard index + 1 < arguments.count else {
            throw NSError(domain: "KanaKanjiCLI", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Missing value after \(flag)"
            ])
        }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let arg = arguments[index]
        switch arg {
        case "--output", "-o":
            options.outputDirectory = URL(fileURLWithPath: try requireValue(after: arg))
        case "--overwrite":
            options.overwrite = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw NSError(domain: "KanaKanjiCLI", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Unknown download argument: \(arg)"
            ])
        }
        index += 1
    }

    return options
}

// MARK: - Main dispatch

do {
    let command = CommandLine.arguments.dropFirst().first

    // ── list-dictionary-kinds ─────────────────────────────────────────────────
    if command == "list-dictionary-kinds" {
        print("Supported dictionary kinds:\n")
        for kind in DictionaryKind.allCases {
            let connectionNote = kind.requiresConnectionMatrix ? " (requires connection matrix)" : ""
            let sourceFile = kind.defaultSourceFileName ?? "<dictionary00.txt … dictionary09.txt>"
            print("  \(kind.rawValue)")
            print("    description : \(kind.description)\(connectionNote)")
            print("    source file : \(sourceFile)")
            print("    artifacts   : \(kind.artifactFileNames.joined(separator: ", "))")
            print()
        }
        exit(0)
    }

    // ── download ──────────────────────────────────────────────────────────────
    if command == "download" {
        let options = try parseDownloadArguments(CommandLine.arguments)
        guard let outputDirectory = options.outputDirectory else {
            printUsage()
            exit(2)
        }

        let files = try MozcDictionaryDownloader.downloadDictionaryOSS(
            to: outputDirectory,
            overwrite: options.overwrite
        )

        for file in files {
            print(file.path)
        }
        exit(0)
    }

    // ── build-all-dictionaries ────────────────────────────────────────────────
    if command == "build-all-dictionaries" {
        let options = try parseBuildAllArguments(CommandLine.arguments)
        guard let sourceDirectory = options.sourceDirectory,
              let outputDirectory = options.outputDirectory else {
            stderr("Error: --source and --output are required for build-all-dictionaries")
            printUsage()
            exit(2)
        }

        let built = try DictionaryArtifactBuilder.buildAll(
            from: sourceDirectory,
            to: outputDirectory,
            skipMissingSupplemental: options.skipMissing
        )

        for kind in built {
            let kindDir = DictionaryArtifactBuilder.artifactDirectory(kind: kind, in: outputDirectory)
            for fileName in kind.artifactFileNames {
                let fileURL = kindDir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    print(fileURL.path)
                }
            }
        }
        exit(0)
    }

    // ── build-dictionary ──────────────────────────────────────────────────────
    if command == "build-dictionary" {
        let (basicOptions, kindOptions) = try parseBuildDictionaryArguments(CommandLine.arguments)

        if let kindOpts = kindOptions {
            // --kind path: writes to <output>/<kind>/ subdirectory
            guard let sourceDirectory = kindOpts.sourceDirectory,
                  let outputDirectory = kindOpts.outputDirectory,
                  let kind = kindOpts.kind else {
                stderr("Error: --kind, --source, and --output are all required")
                printUsage()
                exit(2)
            }

            let paths = try DictionaryArtifactBuilder.build(
                kind: kind,
                from: sourceDirectory,
                to: outputDirectory
            )
            for url in paths where FileManager.default.fileExists(atPath: url.path) {
                print(url.path)
            }
        } else {
            // Backward-compatible path: flat output for main dictionary
            guard let sourceDirectory = basicOptions.sourceDirectory,
                  let outputDirectory = basicOptions.outputDirectory else {
                printUsage()
                exit(2)
            }

            try MozcDictionary.buildArtifacts(from: sourceDirectory, to: outputDirectory)
            for fileName in MozcDictionary.artifactFileNames {
                print(outputDirectory.appendingPathComponent(fileName).path)
            }
        }
        exit(0)
    }

    // ── conversion mode ───────────────────────────────────────────────────────
    let options = try parseArguments(CommandLine.arguments)

    let dictionary: MozcDictionary
    if let artifactsDirectory = options.artifactsDirectory {
        dictionary = try MozcDictionary(artifactsDirectory: artifactsDirectory)
    } else if let dictionaryDirectory = options.dictionaryDirectory {
        dictionary = try MozcDictionary(directory: dictionaryDirectory)
    } else {
        printUsage()
        exit(2)
    }

    let connectionMatrix: ConnectionMatrix?
    if let connectionPath = options.connectionPath {
        connectionMatrix = options.connectionIsBinary
            ? try ConnectionMatrix.loadBinaryBigEndianInt16(connectionPath)
            : try ConnectionMatrix.loadText(connectionPath, skipFirstLine: options.skipConnectionHeader)
    } else {
        connectionMatrix = nil
    }

    let converter = KanaKanjiConverter(dictionary: dictionary, connectionMatrix: connectionMatrix)
    let conversionOptions = ConversionOptions(limit: options.limit, beamWidth: options.beamWidth)

    if let query = options.query {
        for candidate in converter.convert(query, options: conversionOptions) {
            print("\(candidate.text)\t\(candidate.reading)\t\(candidate.score)")
        }
    } else {
        while let line = readLine() {
            let query = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                continue
            }
            for candidate in converter.convert(query, options: conversionOptions) {
                print("\(candidate.text)\t\(candidate.reading)\t\(candidate.score)")
            }
        }
    }
} catch {
    stderr(error.localizedDescription)
    exit(1)
}
