import Foundation

public struct RecursiveFileSearchOptions: Sendable {
    public var includeHidden: Bool
    public var searchContents: Bool
    public var maxContentBytes: Int

    public init(includeHidden: Bool = false, searchContents: Bool = false, maxContentBytes: Int = 2 * 1024 * 1024) {
        self.includeHidden = includeHidden
        self.searchContents = searchContents
        self.maxContentBytes = maxContentBytes
    }
}

public struct RecursiveFileSearchResult: Identifiable, Hashable, Sendable {
    public let id: URL
    public let url: URL
    public let matchedContent: Bool

    public init(url: URL, matchedContent: Bool) {
        self.id = url
        self.url = url
        self.matchedContent = matchedContent
    }
}

public struct RecursiveFileSearchService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func search(
        root: URL,
        query rawQuery: String,
        options: RecursiveFileSearchOptions = RecursiveFileSearchOptions(),
        cancellation: FileOperationCancellation? = nil,
        progress: ((Int) -> Void)? = nil
    ) throws -> [RecursiveFileSearchResult] {
        let matcher = FileNameSearch.Matcher(query: rawQuery)
        guard !matcher.isEmpty else { return [] }
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isRegularFileKey, .fileSizeKey, .isHiddenKey]
        let enumerationOptions: FileManager.DirectoryEnumerationOptions = options.includeHidden ? [] : [.skipsHiddenFiles]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: enumerationOptions
        ) else {
            return []
        }

        var results: [RecursiveFileSearchResult] = []
        var scannedCount = 0
        for case let url as URL in enumerator {
            if cancellation?.isCancelled == true {
                throw FileOperationError.cancelled
            }
            scannedCount += 1
            if scannedCount.isMultiple(of: 100) {
                progress?(scannedCount)
            }

            let values = try url.resourceValues(forKeys: keys)
            guard options.includeHidden || values.isHidden != true else { continue }
            if values.isDirectory == true, values.isPackage == true {
                if matcher.matches(url.lastPathComponent) {
                    results.append(RecursiveFileSearchResult(url: url.standardizedFileURL, matchedContent: false))
                }
                enumerator.skipDescendants()
                continue
            }

            if matcher.matches(url.lastPathComponent) {
                results.append(RecursiveFileSearchResult(url: url.standardizedFileURL, matchedContent: false))
                continue
            }

            guard options.searchContents,
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) <= options.maxContentBytes,
                  fileContainsText(url, query: query)
            else {
                continue
            }
            results.append(RecursiveFileSearchResult(url: url.standardizedFileURL, matchedContent: true))
        }

        progress?(scannedCount)
        return results
    }

    private func fileContainsText(_ url: URL, query: String) -> Bool {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .ascii)
        else {
            return false
        }
        return text.localizedStandardContains(query)
    }
}
