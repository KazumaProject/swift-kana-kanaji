import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MozcDictionaryDownloader {
    public static let defaultBaseURL = URL(
        string: "https://raw.githubusercontent.com/google/mozc/master/src/data/dictionary_oss"
    )!

    public static let dictionaryFileNames: [String] = (0..<10).map {
        String(format: "dictionary%02d.txt", $0)
    }

    public static let connectionFileName = "connection_single_column.txt"

    @discardableResult
    public static func downloadDictionaryOSS(
        to outputDirectory: URL,
        baseURL: URL = defaultBaseURL,
        includeConnection: Bool = true,
        overwrite: Bool = false
    ) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        var fileNames = dictionaryFileNames
        if includeConnection {
            fileNames.append(connectionFileName)
        }

        var writtenFiles: [URL] = []
        writtenFiles.reserveCapacity(fileNames.count)

        for fileName in fileNames {
            let destination = outputDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path), !overwrite {
                writtenFiles.append(destination)
                continue
            }

            let source = baseURL.appendingPathComponent(fileName)
            let data = try Data(contentsOf: source)
            try data.write(to: destination, options: .atomic)
            writtenFiles.append(destination)
        }

        return writtenFiles
    }
}
