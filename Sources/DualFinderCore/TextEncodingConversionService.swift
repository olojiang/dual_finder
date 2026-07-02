import Foundation

public enum TextEncodingConversionStatus: Sendable, Equatable {
    case alreadyUTF8
    case converted
    case renamedUnknown
    case skipped
    case failed
}

public struct TextEncodingConversionResult: Sendable, Equatable {
    public let originalURL: URL
    public let finalURL: URL
    public let detectedEncoding: String?
    public let status: TextEncodingConversionStatus
    public let usedCache: Bool
    public let diagnostic: String?

    public init(
        originalURL: URL,
        finalURL: URL,
        detectedEncoding: String?,
        status: TextEncodingConversionStatus,
        usedCache: Bool = false,
        diagnostic: String? = nil
    ) {
        self.originalURL = originalURL
        self.finalURL = finalURL
        self.detectedEncoding = detectedEncoding
        self.status = status
        self.usedCache = usedCache
        self.diagnostic = diagnostic
    }
}

public struct TextEncodingBatchConversionResult: Sendable, Equatable {
    public let results: [TextEncodingConversionResult]

    public init(results: [TextEncodingConversionResult]) {
        self.results = results
    }

    public var convertedCount: Int {
        results.filter { $0.status == .converted }.count
    }

    public var alreadyUTF8Count: Int {
        results.filter { $0.status == .alreadyUTF8 }.count
    }

    public var renamedUnknownCount: Int {
        results.filter { $0.status == .renamedUnknown }.count
    }

    public var skippedCount: Int {
        results.filter { $0.status == .skipped }.count
    }

    public var failedCount: Int {
        results.filter { $0.status == .failed }.count
    }

    public var cachedUTF8Count: Int {
        results.filter(\.usedCache).count
    }

    public var renamedUnknownResults: [TextEncodingConversionResult] {
        results.filter { $0.status == .renamedUnknown }
    }

    public var failedResults: [TextEncodingConversionResult] {
        results.filter { $0.status == .failed }
    }

    public var problemResults: [TextEncodingConversionResult] {
        results.filter { $0.status == .renamedUnknown || $0.status == .failed }
    }
}

public struct TextEncodingCacheLookup: Sendable, Equatable {
    public let encoding: String
    public let needsMigration: Bool

    public init(encoding: String, needsMigration: Bool) {
        self.encoding = encoding
        self.needsMigration = needsMigration
    }
}

public final class TextEncodingConversionCache: @unchecked Sendable {
    public static let defaultMaxEntries = 10_000

    private struct Entry: Codable, Equatable {
        var size: Int64
        var modifiedAt: Date
        var encoding: String
    }

    private let storageURL: URL
    private let fileManager: FileManager
    private let maxEntries: Int
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var accessOrder: [String] = []
    private var entriesLoaded = false
    private var batchDepth = 0
    private var isDirty = false

    public init(
        storageURL: URL = TextEncodingConversionCache.defaultStorageURL(),
        fileManager: FileManager = .default,
        maxEntries: Int = TextEncodingConversionCache.defaultMaxEntries
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
        self.maxEntries = max(1, maxEntries)
    }

    public var isLoadedInMemory: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entriesLoaded
    }

    public var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        guard entriesLoaded else { return 0 }
        return entries.count
    }

    public func releaseLoadedEntries() {
        lock.lock()
        defer { lock.unlock() }
        guard entriesLoaded, batchDepth == 0, !isDirty else { return }
        entries = [:]
        accessOrder = []
        entriesLoaded = false
    }

    private func ensureEntriesLoaded() {
        guard !entriesLoaded else { return }
        entries = Self.load(from: storageURL)
        accessOrder = Array(entries.keys)
        trimEntriesIfNeeded()
        entriesLoaded = true
    }

    private func touchEntry(key: String) {
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)
    }

    private func trimEntriesIfNeeded() {
        while entries.count > maxEntries, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            entries.removeValue(forKey: oldest)
            isDirty = true
        }
    }

    public func beginBatch() {
        lock.lock()
        batchDepth += 1
        lock.unlock()
    }

    public func endBatch() throws {
        lock.lock()
        batchDepth = max(0, batchDepth - 1)
        let shouldFlush = batchDepth == 0 && isDirty
        let snapshot = shouldFlush ? entries : nil
        if shouldFlush {
            isDirty = false
        }
        lock.unlock()
        if let snapshot {
            try save(snapshot)
        }
    }

    public func cachedEncoding(for file: URL, size: Int64?, modifiedAt: Date?) -> String? {
        guard let size, let modifiedAt else { return nil }
        lock.lock()
        defer { lock.unlock() }
        ensureEntriesLoaded()
        let candidateKeys = [
            cacheKey(for: file, size: size, modifiedAt: modifiedAt),
            legacyPathCacheKey(for: file)
        ]
        guard let entry = candidateKeys.compactMap({ entries[$0] }).first(where: {
            $0.size == size && Self.matchesStoredModificationDate($0.modifiedAt, modifiedAt)
        }) else {
            return nil
        }
        if let hitKey = candidateKeys.first(where: { entries[$0] == entry }) {
            touchEntry(key: hitKey)
        }
        return entry.encoding
    }

    public func cachedUTF8Encoding(for file: URL, size: Int64?, modifiedAt: Date?) -> String? {
        lookupEncoding(for: file, size: size, modifiedAt: modifiedAt)
            .flatMap { $0.encoding == "utf-8" ? $0.encoding : nil }
    }

    public func lookupEncoding(for file: URL, size: Int64?, modifiedAt: Date?) -> TextEncodingCacheLookup? {
        guard let size, let modifiedAt else { return nil }
        lock.lock()
        defer { lock.unlock() }
        ensureEntriesLoaded()
        let fingerprintKey = cacheKey(for: file, size: size, modifiedAt: modifiedAt)
        if let entry = entries[fingerprintKey],
           entry.size == size,
           Self.matchesStoredModificationDate(entry.modifiedAt, modifiedAt) {
            touchEntry(key: fingerprintKey)
            return TextEncodingCacheLookup(encoding: entry.encoding, needsMigration: false)
        }
        let legacyKey = legacyPathCacheKey(for: file)
        if let entry = entries[legacyKey],
           entry.size == size,
           Self.matchesStoredModificationDate(entry.modifiedAt, modifiedAt) {
            touchEntry(key: legacyKey)
            return TextEncodingCacheLookup(encoding: entry.encoding, needsMigration: true)
        }
        return nil
    }

    public func markEncoding(_ encoding: String, for file: URL, size: Int64?, modifiedAt: Date?) throws {
        guard let size, let modifiedAt else { return }
        let key = cacheKey(for: file, size: size, modifiedAt: modifiedAt)
        let entry = Entry(size: size, modifiedAt: modifiedAt, encoding: encoding)
        lock.lock()
        ensureEntriesLoaded()
        if entries[key] == entry {
            lock.unlock()
            return
        }
        entries[key] = entry
        touchEntry(key: key)
        trimEntriesIfNeeded()
        isDirty = true
        let shouldSaveNow = batchDepth == 0
        let snapshot = shouldSaveNow ? entries : nil
        if shouldSaveNow {
            isDirty = false
        }
        lock.unlock()
        if let snapshot {
            try save(snapshot)
        }
    }

    public func markUTF8(_ encoding: String = "utf-8", for file: URL, size: Int64?, modifiedAt: Date?) throws {
        try markEncoding(encoding, for: file, size: size, modifiedAt: modifiedAt)
    }

    public static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("DualFinder", isDirectory: true)
            .appendingPathComponent("text-encoding-cache.json")
    }

    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else {
            return [:]
        }
        return entries
    }

    private func save(_ entries: [String: Entry]) throws {
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: storageURL, options: [.atomic])
    }

    private func cacheKey(for file: URL, size: Int64, modifiedAt: Date) -> String {
        [
            file.lastPathComponent,
            String(size),
            String(Self.modificationDateCacheToken(for: modifiedAt))
        ].joined(separator: "\u{1f}")
    }

    private func legacyPathCacheKey(for file: URL) -> String {
        file.standardizedFileURL.path
    }

    private static func modificationDateCacheToken(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func matchesStoredModificationDate(_ stored: Date, _ current: Date) -> Bool {
        abs(stored.timeIntervalSince(current)) < 0.001
    }
}

public struct TextEncodingConversionService {
    public typealias ProgressHandler = (_ completedCount: Int, _ totalCount: Int, _ result: TextEncodingConversionResult) -> Void

    public static let defaultCacheHitProgressStride = 64

    public static func shouldReportBatchProgress(
        result: TextEncodingConversionResult,
        completedCount: Int,
        totalCount: Int,
        cacheHitStride: Int = defaultCacheHitProgressStride
    ) -> Bool {
        if completedCount == totalCount { return true }
        if !result.usedCache { return true }
        return completedCount.isMultiple(of: cacheHitStride)
    }

    private static let supportedTextFileExtensions: Set<String> = [
        "adoc", "asc", "bash", "bat", "c", "cc", "cfg", "conf", "cpp", "cs",
        "css", "csv", "cxx", "diff", "env", "go", "h", "hpp", "htm", "html",
        "ini", "java", "js", "json", "jsx", "kt", "less", "log", "lua", "m",
        "md", "mdown", "markdown", "mm", "patch", "php", "properties", "py",
        "rb", "rs", "sass", "scpt", "scss", "sh", "sql", "swift", "tex", "toml",
        "ts", "tsx", "txt", "xml", "yaml", "yml", "zsh"
    ]

    private let fileManager: FileManager
    private let logger: AppLogging?
    private let cache: TextEncodingConversionCache?

    public init(
        fileManager: FileManager = .default,
        logger: AppLogging?,
        cache: TextEncodingConversionCache? = nil
    ) {
        self.fileManager = fileManager
        self.logger = logger
        self.cache = cache
    }

    public func convertFilesToUTF8(
        _ urls: [URL],
        progress: ProgressHandler? = nil
    ) throws -> TextEncodingBatchConversionResult {
        cache?.beginBatch()
        defer {
            try? cache?.endBatch()
        }

        var results: [TextEncodingConversionResult] = []
        results.reserveCapacity(urls.count)
        for (index, url) in urls.enumerated() {
            let result: TextEncodingConversionResult
            do {
                result = try convertFileToUTF8(url)
            } catch {
                let standardizedURL = url.standardizedFileURL
                let message = error.localizedDescription
                logger?.error("text-encoding", "file.failed", metadata: [
                    "path": standardizedURL.path,
                    "error": message
                ])
                result = TextEncodingConversionResult(
                    originalURL: standardizedURL,
                    finalURL: standardizedURL,
                    detectedEncoding: nil,
                    status: .failed,
                    diagnostic: message
                )
            }
            results.append(result)
            if Self.shouldReportBatchProgress(
                result: result,
                completedCount: index + 1,
                totalCount: urls.count
            ) {
                progress?(index + 1, urls.count, result)
            }
        }

        let batchResult = TextEncodingBatchConversionResult(results: results)
        if batchResult.cachedUTF8Count > 0 {
            logger?.info("text-encoding", "batch.cache-hits", metadata: [
                "count": "\(batchResult.cachedUTF8Count)",
                "total": "\(urls.count)"
            ])
        }
        return batchResult
    }

    public func convertFileToUTF8(_ url: URL) throws -> TextEncodingConversionResult {
        let standardizedURL = url.standardizedFileURL

        guard isSupportedTextFileCandidate(standardizedURL) else {
            logger?.info("text-encoding", "file.skipped", metadata: [
                "path": standardizedURL.path,
                "reason": "unsupported-extension"
            ])
            return TextEncodingConversionResult(
                originalURL: standardizedURL,
                finalURL: standardizedURL,
                detectedEncoding: nil,
                status: .skipped
            )
        }

        let initialFingerprint = fileFingerprint(for: standardizedURL)
        guard initialFingerprint?.isRegularFile == true else {
            logger?.info("text-encoding", "file.skipped", metadata: ["path": standardizedURL.path])
            return TextEncodingConversionResult(
                originalURL: standardizedURL,
                finalURL: standardizedURL,
                detectedEncoding: nil,
                status: .skipped
            )
        }

        if let lookup = cache?.lookupEncoding(
            for: standardizedURL,
            size: initialFingerprint?.size,
            modifiedAt: initialFingerprint?.modifiedAt
        ), lookup.encoding == "utf-8" {
            if needsUnknownEncodingNameRestore(standardizedURL) {
                let finalURL = try restoreUnknownEncodingNameIfNeeded(standardizedURL)
                let finalFingerprint = fileFingerprint(for: finalURL)
                try cache?.markUTF8(for: finalURL, size: finalFingerprint?.size, modifiedAt: finalFingerprint?.modifiedAt)
                logger?.debug("text-encoding", "file.cache-hit", metadata: [
                    "path": finalURL.path,
                    "encoding": lookup.encoding,
                    "restoredName": "true"
                ])
                return TextEncodingConversionResult(
                    originalURL: standardizedURL,
                    finalURL: finalURL,
                    detectedEncoding: lookup.encoding,
                    status: .alreadyUTF8,
                    usedCache: true
                )
            }

            if lookup.needsMigration {
                try cache?.markUTF8(
                    for: standardizedURL,
                    size: initialFingerprint?.size,
                    modifiedAt: initialFingerprint?.modifiedAt
                )
            }
            return TextEncodingConversionResult(
                originalURL: standardizedURL,
                finalURL: standardizedURL,
                detectedEncoding: lookup.encoding,
                status: .alreadyUTF8,
                usedCache: true
            )
        }

        let data = try Data(contentsOf: standardizedURL)
        guard !data.isEmpty else {
            let finalURL = try restoreUnknownEncodingNameIfNeeded(standardizedURL)
            let finalFingerprint = finalURL == standardizedURL ? initialFingerprint : fileFingerprint(for: finalURL)
            try cache?.markUTF8(for: finalURL, size: finalFingerprint?.size, modifiedAt: finalFingerprint?.modifiedAt)
            return TextEncodingConversionResult(
                originalURL: standardizedURL,
                finalURL: finalURL,
                detectedEncoding: "utf-8",
                status: .alreadyUTF8
            )
        }

        guard let detected = detectEncoding(for: data) else {
            let diagnostic = unknownEncodingDiagnostic(for: data)
            let moved = try moveUnknownEncodingFile(standardizedURL)
            logger?.warning("text-encoding", "file.unknown-moved", metadata: [
                "source": standardizedURL.path,
                "destination": moved.path,
                "reason": diagnostic,
                "byteCount": "\(data.count)",
                "sampleHex": hexSample(for: data)
            ])
            return TextEncodingConversionResult(
                originalURL: standardizedURL,
                finalURL: moved,
                detectedEncoding: nil,
                status: .renamedUnknown,
                diagnostic: diagnostic
            )
        }

        guard detected.label != "utf-8" else {
            let finalURL = try restoreUnknownEncodingNameIfNeeded(standardizedURL)
            let finalFingerprint = finalURL == standardizedURL ? initialFingerprint : fileFingerprint(for: finalURL)
            logger?.info("text-encoding", "file.already-utf8", metadata: ["path": finalURL.path])
            try cache?.markUTF8(for: finalURL, size: finalFingerprint?.size, modifiedAt: finalFingerprint?.modifiedAt)
            return TextEncodingConversionResult(
                originalURL: standardizedURL,
                finalURL: finalURL,
                detectedEncoding: detected.label,
                status: .alreadyUTF8
            )
        }

        let utf8Data = Data(detected.text.utf8)
        try utf8Data.write(to: standardizedURL, options: .atomic)
        let finalURL = try restoreUnknownEncodingNameIfNeeded(standardizedURL)
        let updatedFingerprint = fileFingerprint(for: finalURL)
        try cache?.markUTF8(for: finalURL, size: updatedFingerprint?.size, modifiedAt: updatedFingerprint?.modifiedAt)
        var metadata = [
            "path": finalURL.path,
            "sourceEncoding": detected.label,
            "destinationEncoding": "utf-8"
        ]
        if detected.label.contains("repaired-nul") {
            metadata["removedNULBytes"] = "\(data.filter { $0 == 0 }.count)"
        }
        if detected.label.contains("lossy") {
            metadata["lossyByteCount"] = "\(detected.lossyByteCount ?? 0)"
        }
        logger?.info("text-encoding", "file.converted", metadata: metadata)
        return TextEncodingConversionResult(
            originalURL: standardizedURL,
            finalURL: finalURL,
            detectedEncoding: detected.label,
            status: .converted
        )
    }

    public func detectFileEncoding(_ url: URL) throws -> String? {
        let standardizedURL = url.standardizedFileURL
        let fingerprint = fileFingerprint(for: standardizedURL)
        guard fingerprint?.isRegularFile == true else { return nil }
        guard isSupportedTextFileCandidate(standardizedURL) else { return nil }

        if let cachedEncoding = cache?.cachedEncoding(
            for: standardizedURL,
            size: fingerprint?.size,
            modifiedAt: fingerprint?.modifiedAt
        ) {
            return cachedEncoding
        }

        let data = try Data(contentsOf: standardizedURL)
        let label = data.isEmpty ? "utf-8" : (detectEncoding(for: data)?.label ?? "unknown")
        try cache?.markEncoding(label, for: standardizedURL, size: fingerprint?.size, modifiedAt: fingerprint?.modifiedAt)
        return label
    }

    private func detectEncoding(for data: Data) -> DetectedTextEncoding? {
        if let text = String(data: data, encoding: .utf8),
           let cleaned = cleanedTextIfLikelyText(text),
           textLooksReadable(cleaned) {
            return DetectedTextEncoding(label: "utf-8", text: cleaned)
        }

        if let repaired = repairedUTF8TextWithNULPadding(for: data) {
            return repaired
        }

        if hasUTF16SignatureOrPattern(data) {
            if let repaired = repairedUTF16Text(for: data) {
                return repaired
            }
            for candidate in EncodingCandidate.unicodeCandidates {
                guard let text = String(data: data, encoding: candidate.encoding),
                      let cleaned = cleanedTextIfLikelyText(text),
                      textLooksReadable(cleaned) else {
                    continue
                }
                return DetectedTextEncoding(label: candidate.label, text: cleaned)
            }
        }

        guard !data.contains(0) else {
            return detectEncodingAfterRemovingLimitedNULBytes(for: data)
        }

        if let detected = detectMixedLineEncoding(for: data) {
            return detected
        }

        if let detected = detectEncodingWithFoundation(for: data) {
            return detected
        }

        for candidate in EncodingCandidate.legacyCandidates {
            guard let text = String(data: data, encoding: candidate.encoding),
                  let cleaned = cleanedTextIfLikelyText(text),
                  textLooksReadable(cleaned) else {
                continue
            }
            return DetectedTextEncoding(label: candidate.label, text: cleaned)
        }

        return nil
    }

    private func detectEncodingAfterRemovingLimitedNULBytes(for data: Data) -> DetectedTextEncoding? {
        let nulCount = data.filter { $0 == 0 }.count
        guard Double(nulCount) / Double(max(data.count, 1)) <= 0.05 else {
            return nil
        }

        let repairedData = Data(data.filter { $0 != 0 })
        guard !repairedData.isEmpty else { return nil }

        if let text = String(data: repairedData, encoding: .utf8),
           let cleaned = cleanedTextIfLikelyText(text),
           textLooksReadable(cleaned) {
            return DetectedTextEncoding(label: "utf-8-repaired-nul", text: cleaned)
        }

        if let detected = detectMixedLineEncoding(for: repairedData) {
            return DetectedTextEncoding(label: "\(detected.label)-repaired-nul", text: detected.text)
        }

        if let detected = detectEncodingWithFoundation(for: repairedData) {
            return DetectedTextEncoding(label: "\(detected.label)-repaired-nul", text: detected.text)
        }

        for candidate in EncodingCandidate.legacyCandidates {
            guard let text = String(data: repairedData, encoding: candidate.encoding),
                  let cleaned = cleanedTextIfLikelyText(text),
                  textLooksReadable(cleaned) else {
                continue
            }
            return DetectedTextEncoding(label: "\(candidate.label)-repaired-nul", text: cleaned)
        }

        return nil
    }

    private func detectMixedLineEncoding(for data: Data) -> DetectedTextEncoding? {
        let lines = splitDataByNewline(data)
        guard lines.count > 1 else { return nil }

        var decodedLines: [String] = []
        decodedLines.reserveCapacity(lines.count)
        var labels: Set<String> = []
        var nonASCIIByteLineCount = 0
        var lossyByteCount = 0
        let lossyLimit = max(data.count / 100, 8)

        for line in lines {
            if line.contains(where: { $0 >= 0x80 }) {
                nonASCIIByteLineCount += 1
            }

            if let decoded = decodeLikelyTextLine(line) {
                decodedLines.append(decoded.text)
                labels.insert(decoded.label)
                continue
            }

            guard lossyByteCount + line.count <= lossyLimit else {
                return nil
            }
            lossyByteCount += line.count
            decodedLines.append(String(decoding: line, as: UTF8.self))
            labels.insert("utf-8-lossy")
        }

        guard labels.count > 1,
              nonASCIIByteLineCount > 0 else {
            return nil
        }

        let text = decodedLines.joined()
        guard let cleaned = cleanedTextIfLikelyText(text),
              textLooksReadable(cleaned, replacementThreshold: lossyByteCount > 0 ? 0.02 : 0.001) else {
            return nil
        }

        let orderedLabels = ["utf-8", "gbk", "gb2312", "gb18030", "big5", "shift_jis", "euc-kr", "utf-8-lossy"]
            .filter { labels.contains($0) }
        return DetectedTextEncoding(
            label: "mixed:\(orderedLabels.joined(separator: "+"))",
            text: cleaned,
            lossyByteCount: lossyByteCount == 0 ? nil : lossyByteCount
        )
    }

    private func splitDataByNewline(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var startIndex = data.startIndex
        var index = startIndex
        while index < data.endIndex {
            if data[index] == 0x0a {
                let nextIndex = data.index(after: index)
                lines.append(data[startIndex..<nextIndex])
                startIndex = nextIndex
            }
            index = data.index(after: index)
        }
        if startIndex < data.endIndex {
            lines.append(data[startIndex..<data.endIndex])
        }
        return lines
    }

    private func decodeLikelyTextLine(_ data: Data) -> DetectedTextEncoding? {
        if let text = String(data: data, encoding: .utf8),
           let cleaned = cleanedTextIfLikelyText(text),
           textLooksReadable(cleaned) {
            return DetectedTextEncoding(label: "utf-8", text: cleaned)
        }

        for candidate in EncodingCandidate.mixedLineCandidates {
            guard let text = String(data: data, encoding: candidate.encoding),
                  let cleaned = cleanedTextIfLikelyText(text),
                  textLooksReadable(cleaned) else {
                continue
            }
            return DetectedTextEncoding(label: candidate.label, text: cleaned)
        }

        return nil
    }

    private func textLooksReadable(_ text: String, replacementThreshold: Double = 0.001) -> Bool {
        guard !text.isEmpty else { return true }
        var replacementScalars = 0
        var privateUseScalars = 0
        var totalScalars = 0

        for scalar in text.unicodeScalars {
            totalScalars += 1
            if scalar == "\u{fffd}" {
                replacementScalars += 1
            }
            if scalar.value >= 0xe000 && scalar.value <= 0xf8ff {
                privateUseScalars += 1
            }
        }

        guard totalScalars > 0 else { return true }
        return Double(replacementScalars) / Double(totalScalars) <= replacementThreshold
            && Double(privateUseScalars) / Double(totalScalars) <= 0.15
    }

    private func repairedUTF8TextWithNULPadding(for data: Data) -> DetectedTextEncoding? {
        guard data.contains(0),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let result = cleanScalars(text)

        guard result.totalCount > 0,
              result.nulCount > 0,
              Double(result.suspiciousControlCount) / Double(result.totalCount) <= 0.02 else {
            return nil
        }

        guard !result.cleaned.isEmpty,
              textLooksReadable(result.cleaned) else {
            return nil
        }

        let nulRatio = Double(result.nulCount) / Double(result.totalCount)
        let label = nulRatio > 0.05 ? "utf-8-repaired-nul-padding" : "utf-8-repaired-nul"
        return DetectedTextEncoding(label: label, text: result.cleaned)
    }

    private func detectEncodingWithFoundation(for data: Data) -> DetectedTextEncoding? {
        var convertedString: NSString?
        var usedLossyConversion = ObjCBool(false)
        let rawEncoding = NSString.stringEncoding(
            for: data,
            encodingOptions: nil,
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )
        guard let convertedString else {
            return nil
        }

        let text = convertedString as String
        let replacementThreshold = usedLossyConversion.boolValue ? 0.06 : 0.001
        guard let cleaned = cleanedTextIfLikelyText(text),
              textLooksReadable(cleaned, replacementThreshold: replacementThreshold),
              let label = label(forFoundationEncoding: rawEncoding, decodedText: text, data: data) else {
            return nil
        }

        guard !usedLossyConversion.boolValue || textHasCJKContent(cleaned) else {
            return nil
        }

        if ["windows-1252", "iso-8859-1"].contains(label),
           let cjkDetected = detectCJKEncoding(for: data) {
            return cjkDetected
        }

        return DetectedTextEncoding(
            label: usedLossyConversion.boolValue ? "\(label)-lossy" : label,
            text: cleaned,
            lossyByteCount: usedLossyConversion.boolValue ? data.count : nil
        )
    }

    private func detectCJKEncoding(for data: Data) -> DetectedTextEncoding? {
        for candidate in EncodingCandidate.cjkCandidates {
            guard let text = String(data: data, encoding: candidate.encoding),
                  let cleaned = cleanedTextIfLikelyText(text),
                  textLooksReadable(cleaned),
                  textHasCJKContent(cleaned) else {
                continue
            }
            return DetectedTextEncoding(label: candidate.label, text: cleaned)
        }
        return nil
    }

    private func textHasCJKContent(_ text: String) -> Bool {
        var cjkScalars = 0
        var letterScalars = 0
        for scalar in text.unicodeScalars {
            guard scalar.properties.isAlphabetic else { continue }
            letterScalars += 1
            let v = Int(scalar.value)
            if (0x4e00...0x9fff).contains(v)
                || (0x3400...0x4dbf).contains(v)
                || (0x3040...0x30ff).contains(v)
                || (0xac00...0xd7af).contains(v) {
                cjkScalars += 1
            }
        }
        guard letterScalars > 0 else { return false }
        return Double(cjkScalars) / Double(letterScalars) >= 0.20
    }

    private func label(forFoundationEncoding rawEncoding: UInt, decodedText: String, data: Data) -> String? {
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(rawEncoding)
        let ianaName = CFStringConvertEncodingToIANACharSetName(cfEncoding).map { String($0) }?.lowercased()

        switch ianaName {
        case "utf-8":
            return "utf-8"
        case "gbk", "gb_2312-80", "gb2312":
            return "gbk"
        case "gb18030":
            return firstMatchingCandidateLabel(in: ["gbk", "gb2312", "gb18030"], decodedText: decodedText, data: data) ?? "gb18030"
        case "big5", "cp950", "big5-hkscs":
            return "big5"
        case "shift_jis", "shift-jis":
            return "shift_jis"
        case "euc-kr":
            return "euc-kr"
        case "windows-1252":
            return "windows-1252"
        case "iso-8859-1":
            return "iso-8859-1"
        default:
            return firstMatchingCandidateLabel(
                in: EncodingCandidate.legacyCandidates.map(\.label),
                decodedText: decodedText,
                data: data
            )
        }
    }

    private func firstMatchingCandidateLabel(in labels: [String], decodedText: String, data: Data) -> String? {
        for label in labels {
            guard let candidate = EncodingCandidate.legacyCandidates.first(where: { $0.label == label }),
                  String(data: data, encoding: candidate.encoding) == decodedText else {
                continue
            }
            return candidate.label
        }
        return nil
    }

    private func fileFingerprint(for url: URL) -> TextEncodingFileFingerprint? {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]) else {
            return nil
        }
        return TextEncodingFileFingerprint(
            isRegularFile: values.isRegularFile == true,
            size: values.fileSize.map(Int64.init),
            modifiedAt: values.contentModificationDate
        )
    }

    private func isSupportedTextFileCandidate(_ url: URL) -> Bool {
        let restoredName = removingUnknownEncodingMarkers(from: url.lastPathComponent)
        let fileExtension = (restoredName as NSString).pathExtension.lowercased()
        guard !fileExtension.isEmpty else { return false }
        return Self.supportedTextFileExtensions.contains(fileExtension)
    }

    private func hasUTF16SignatureOrPattern(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let bytes = Array(data.prefix(256))
        if bytes.starts(with: [0xff, 0xfe]) || bytes.starts(with: [0xfe, 0xff]) {
            return true
        }

        let evenZeroes = stride(from: 0, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
        let oddZeroes = stride(from: 1, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
        let pairCount = max(bytes.count / 2, 1)
        return Double(evenZeroes) / Double(pairCount) > 0.20
            || Double(oddZeroes) / Double(pairCount) > 0.20
    }

    private struct ScalarCleaningResult {
        let cleaned: String
        let nulCount: Int
        let suspiciousControlCount: Int
        let totalCount: Int
    }

    private func cleanScalars(_ text: String) -> ScalarCleaningResult {
        var nulCount = 0
        var suspiciousCount = 0
        var totalCount = 0
        var buffer = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            totalCount += 1
            if scalar.value == 0 {
                nulCount += 1
                continue
            }
            if scalar.properties.generalCategory == .control,
               scalar != "\n", scalar != "\r", scalar != "\t" {
                suspiciousCount += 1
                continue
            }
            buffer.append(scalar)
        }
        return ScalarCleaningResult(
            cleaned: String(buffer),
            nulCount: nulCount,
            suspiciousControlCount: suspiciousCount,
            totalCount: totalCount
        )
    }

    private func cleanedTextIfLikelyText(_ text: String) -> String? {
        guard !text.isEmpty else { return "" }
        let result = cleanScalars(text)
        guard result.totalCount > 0 else { return "" }
        guard Double(result.nulCount) / Double(result.totalCount) <= 0.001,
              Double(result.suspiciousControlCount) / Double(result.totalCount) <= 0.02 else {
            return nil
        }
        return result.cleaned
    }

    private func repairedUTF16Text(for data: Data) -> DetectedTextEncoding? {
        guard data.count >= 2 else { return nil }
        let isLittleEndian: Bool
        let label: String
        if data.starts(with: [0xff, 0xfe]) {
            isLittleEndian = true
            label = "utf-16le-repaired"
        } else if data.starts(with: [0xfe, 0xff]) {
            isLittleEndian = false
            label = "utf-16be-repaired"
        } else {
            return nil
        }

        var codeUnits: [UInt16] = []
        codeUnits.reserveCapacity(data.count / 2)
        var index = 2
        while index + 1 < data.count {
            let first = UInt16(data[index])
            let second = UInt16(data[index + 1])
            let value = isLittleEndian ? first | (second << 8) : (first << 8) | second
            switch value {
            case 0x0000:
                break
            case 0x0a00:
                codeUnits.append(0x000a)
            case 0x0d00:
                codeUnits.append(0x000d)
            case 0x2000:
                codeUnits.append(0x0020)
            default:
                codeUnits.append(value)
            }
            index += 2
        }

        let text = String(decoding: codeUnits, as: Unicode.UTF16.self)
        guard let cleaned = cleanedTextIfLikelyText(text),
              textLooksReadable(cleaned) else { return nil }
        return DetectedTextEncoding(label: label, text: cleaned)
    }

    private func moveUnknownEncodingFile(_ url: URL) throws -> URL {
        guard url.deletingLastPathComponent().lastPathComponent != "unknown_encode" else {
            logger?.warning("text-encoding", "file.unknown-already-marked", metadata: [
                "path": url.path
            ])
            return url.standardizedFileURL
        }

        let directory = url.deletingLastPathComponent()
        let unknownDirectory = directory.appendingPathComponent("unknown_encode", isDirectory: true)
        try fileManager.createDirectory(at: unknownDirectory, withIntermediateDirectories: true)
        var destination = unknownDirectory.appendingPathComponent(url.lastPathComponent)
        var index = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = unknownDirectory.appendingPathComponent("\(url.lastPathComponent) \(index)")
            index += 1
        }
        try fileManager.moveItem(at: url, to: destination)
        return destination.standardizedFileURL
    }

    private func needsUnknownEncodingNameRestore(_ url: URL) -> Bool {
        let hasMarker = removingUnknownEncodingMarkers(from: url.lastPathComponent) != url.lastPathComponent
        let isInUnknownDirectory = url.deletingLastPathComponent().lastPathComponent == "unknown_encode"
        return hasMarker || isInUnknownDirectory
    }

    private func restoreUnknownEncodingNameIfNeeded(_ url: URL) throws -> URL {
        let restoredName = removingUnknownEncodingMarkers(from: url.lastPathComponent)
        let isInUnknownDirectory = url.deletingLastPathComponent().lastPathComponent == "unknown_encode"
        guard restoredName != url.lastPathComponent || isInUnknownDirectory,
              !restoredName.isEmpty else {
            return url.standardizedFileURL
        }

        let destination = uniqueRestoredDestination(
            in: isInUnknownDirectory ? url.deletingLastPathComponent().deletingLastPathComponent() : url.deletingLastPathComponent(),
            restoredName: restoredName,
            currentURL: url
        )
        try fileManager.moveItem(at: url, to: destination)
        logger?.info("text-encoding", "file.unknown-name-restored", metadata: [
            "source": url.path,
            "destination": destination.path
        ])
        return destination.standardizedFileURL
    }

    private func removingUnknownEncodingMarkers(from name: String) -> String {
        var result = name
        while let range = result.range(
            of: #"_unknown_encode(?: \d+)?$"#,
            options: .regularExpression
        ) {
            result.removeSubrange(range)
        }
        return result
    }

    private func uniqueRestoredDestination(in directory: URL, restoredName: String, currentURL: URL) -> URL {
        var destination = directory.appendingPathComponent(restoredName)
        guard destination.standardizedFileURL != currentURL.standardizedFileURL,
              fileManager.fileExists(atPath: destination.path) else {
            return destination
        }

        let restoredURL = URL(fileURLWithPath: restoredName)
        let extensionText = restoredURL.pathExtension
        let stem = extensionText.isEmpty
            ? restoredName
            : restoredURL.deletingPathExtension().lastPathComponent
        var index = 2
        repeat {
            let candidateName = extensionText.isEmpty
                ? "\(stem) \(index)"
                : "\(stem) \(index).\(extensionText)"
            destination = directory.appendingPathComponent(candidateName)
            index += 1
        } while fileManager.fileExists(atPath: destination.path)
        return destination
    }

    private func unknownEncodingDiagnostic(for data: Data) -> String {
        if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) {
            return "looks like a ZIP archive, not a text file"
        }
        if data.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07]) {
            return "looks like a RAR archive, not a text file"
        }
        if data.contains(0) {
            if hasUTF16SignatureOrPattern(data) {
                return "contains NUL bytes but did not decode as supported UTF-16 text"
            }
            return "contains NUL bytes and does not look like supported text"
        }
        return "no supported text encoding decoded cleanly as text"
    }

    private func hexSample(for data: Data, byteCount: Int = 16) -> String {
        data.prefix(byteCount)
            .map { String(format: "%02x", $0) }
            .joined(separator: " ")
    }
}

private struct TextEncodingFileFingerprint {
    let isRegularFile: Bool
    let size: Int64?
    let modifiedAt: Date?
}

private struct DetectedTextEncoding {
    let label: String
    let text: String
    var lossyByteCount: Int?

    init(label: String, text: String, lossyByteCount: Int? = nil) {
        self.label = label
        self.text = text
        self.lossyByteCount = lossyByteCount
    }
}

private struct EncodingCandidate {
    let label: String
    let encoding: String.Encoding

    static let unicodeCandidates: [EncodingCandidate] = [
        EncodingCandidate(label: "utf-16le", encoding: .utf16LittleEndian),
        EncodingCandidate(label: "utf-16be", encoding: .utf16BigEndian),
        EncodingCandidate(label: "utf-16", encoding: .utf16)
    ]

    static let legacyCandidates: [EncodingCandidate] = [
        candidate(label: "gbk", ianaName: "GBK"),
        candidate(label: "gb2312", ianaName: "GB2312"),
        candidate(label: "gb18030", ianaName: "GB18030"),
        candidate(label: "big5", ianaName: "Big5"),
        candidate(label: "shift_jis", ianaName: "Shift_JIS"),
        candidate(label: "euc-kr", ianaName: "EUC-KR"),
        EncodingCandidate(label: "windows-1252", encoding: .windowsCP1252),
        EncodingCandidate(label: "iso-8859-1", encoding: .isoLatin1)
    ].compactMap { $0 }

    static let cjkCandidates: [EncodingCandidate] = legacyCandidates.filter {
        ["gbk", "gb2312", "gb18030", "big5", "shift_jis", "euc-kr"].contains($0.label)
    }

    static let mixedLineCandidates: [EncodingCandidate] = legacyCandidates.filter {
        !["windows-1252", "iso-8859-1"].contains($0.label)
    }

    private static func candidate(label: String, ianaName: String) -> EncodingCandidate? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(ianaName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        guard nsEncoding != UInt(kCFStringEncodingInvalidId) else { return nil }
        return EncodingCandidate(label: label, encoding: String.Encoding(rawValue: nsEncoding))
    }
}
