import Foundation
import KanaKanjiCore

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

func printUsage() {
    print("""
    Usage:
      kana-kanji download --output <dir> [--overwrite]
      kana-kanji build-dictionary --source <mozc_fetch_dir> --output <artifacts_dir>
      kana-kanji --artifacts-dir <artifacts_dir> [--connection <path>] [--connection-binary] [--query <hiragana>]
                 [--limit N] [--beam N] [--no-skip-connection-header]
      kana-kanji --dictionary-dir <dir> [--connection <path>] [--connection-binary] [--query <hiragana>]
                 [--limit N] [--beam N] [--no-skip-connection-header]

    Examples:
      kana-kanji download --output ./mozc_fetch
      kana-kanji build-dictionary --source ./mozc_fetch --output ./artifacts
      kana-kanji --artifacts-dir ./artifacts --connection ./artifacts/connection_single_column.bin --connection-binary --query きょうのてんき
      echo きょうのてんき | kana-kanji --artifacts-dir ./artifacts --connection ./artifacts/connection_single_column.bin --connection-binary
    """)
}

func stderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

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

func parseBuildDictionaryArguments(_ arguments: [String]) throws -> BuildDictionaryOptions {
    var options = BuildDictionaryOptions()
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
            options.sourceDirectory = URL(fileURLWithPath: try requireValue(after: arg))
        case "--output", "-o", "--out-dir":
            options.outputDirectory = URL(fileURLWithPath: try requireValue(after: arg))
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

do {
    let command = CommandLine.arguments.dropFirst().first

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

    if command == "build-dictionary" {
        let options = try parseBuildDictionaryArguments(CommandLine.arguments)
        guard let sourceDirectory = options.sourceDirectory,
              let outputDirectory = options.outputDirectory else {
            printUsage()
            exit(2)
        }

        try MozcDictionary.buildArtifacts(from: sourceDirectory, to: outputDirectory)
        for fileName in MozcDictionary.artifactFileNames {
            print(outputDirectory.appendingPathComponent(fileName).path)
        }
        exit(0)
    }

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
