import Foundation

public enum TextEncodingConversionStatus: Sendable, Equatable {
    case alreadyUTF8
    case converted
    case renamedUnknown
    case skipped
}

public struct TextEncodingConversionResult: Sendable, Equatable {
    public let originalURL: URL
    public let finalURL: URL
    public let detectedEncoding: String?
    public let status: TextEncodingConversionStatus

    public init(
        originalURL: URL,
        finalURL: URL,
        detectedEncoding: String?,
        status: TextEncodingConversionStatus
    ) {
        self.originalURL = originalURL
        self.finalURL = finalURL
        self.detectedEncoding = detectedEncoding
        self.status = status
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
}

public struct TextEncodingConversionService {
    public typealias ProgressHandler = (_ completedCount: Int, _ totalCount: Int, _ result: TextEncodingConversionResult) -> Void

    private let fileManager: FileManager
    private let logger: AppLogging?

    public init(fileManager: FileManager = .default, logger: AppLogging?) {
        self.fileManager = fileManager
        self.logger = logger
    }

    public func convertFilesToUTF8(
        _ urls: [URL],
        progress: ProgressHandler? = nil
    ) throws -> TextEncodingBatchConversionResult {
        var results: [TextEncodingConversionResult] = []
        for (index, url) in urls.enumerated() {
            let result = try convertFileToUTF8(url)
            results.append(result)
            progress?(index + 1, urls.count, result)
        }
        return TextEncodingBatchConversionResult(results: results)
    }

    public func convertFileToUTF8(_ url: URL) throws -> TextEncodingConversionResult {
        let standardizedURL = url.standardizedFileURL
        guard isRegularFile(standardizedURL) else {
            logger?.info("text-encoding", "file.skipped", metadata: ["path": standardizedURL.path])
            return TextEncodingConversionResult(
                originalURL: standardizedURL,
                finalURL: standardizedURL,
                detectedEncoding: nil,
                status: .skipped
            )
        }

        let data = try Data(contentsOf: standardizedURL)
        guard !data.isEmpty else {
            return TextEncodingConversionResult(
                originalURL: standardizedURL,
                finalURL: standardizedURL,
                detectedEncoding: "utf-8",
                status: .alreadyUTF8
            )
        }

        guard let detected = detectEncoding(for: data) else {
            let renamed = try renameUnknownEncodingFile(standardizedURL)
            logger?.warning("text-encoding", "file.unknown-renamed", metadata: [
                "source": standardizedURL.path,
                "destination": renamed.path
            ])
            return TextEncodingConversionResult(
                originalURL: standardizedURL,
                finalURL: renamed,
                detectedEncoding: nil,
                status: .renamedUnknown
            )
        }

        guard detected.label != "utf-8" else {
            logger?.info("text-encoding", "file.already-utf8", metadata: ["path": standardizedURL.path])
            return TextEncodingConversionResult(
                originalURL: standardizedURL,
                finalURL: standardizedURL,
                detectedEncoding: detected.label,
                status: .alreadyUTF8
            )
        }

        let utf8Data = Data(detected.text.utf8)
        try utf8Data.write(to: standardizedURL, options: .atomic)
        logger?.info("text-encoding", "file.converted", metadata: [
            "path": standardizedURL.path,
            "sourceEncoding": detected.label,
            "destinationEncoding": "utf-8"
        ])
        return TextEncodingConversionResult(
            originalURL: standardizedURL,
            finalURL: standardizedURL,
            detectedEncoding: detected.label,
            status: .converted
        )
    }

    private func detectEncoding(for data: Data) -> DetectedTextEncoding? {
        if let text = String(data: data, encoding: .utf8), isLikelyText(text) {
            return DetectedTextEncoding(label: "utf-8", text: text)
        }

        if hasUTF16SignatureOrPattern(data) {
            for candidate in EncodingCandidate.unicodeCandidates {
                guard let text = String(data: data, encoding: candidate.encoding),
                      isLikelyText(text) else {
                    continue
                }
                return DetectedTextEncoding(label: candidate.label, text: text)
            }
        }

        guard !data.contains(0) else {
            return nil
        }

        if let detected = detectEncodingWithFoundation(for: data) {
            return detected
        }

        for candidate in EncodingCandidate.legacyCandidates {
            guard let text = String(data: data, encoding: candidate.encoding),
                  isLikelyText(text) else {
                continue
            }
            return DetectedTextEncoding(label: candidate.label, text: text)
        }

        return nil
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
        guard usedLossyConversion.boolValue == false,
              let convertedString else {
            return nil
        }

        let text = convertedString as String
        guard isLikelyText(text),
              let label = label(forFoundationEncoding: rawEncoding, decodedText: text, data: data) else {
            return nil
        }
        return DetectedTextEncoding(label: label, text: text)
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
            return firstMatchingCandidateLabel(in: ["gbk", "gb2312", "gb18030"], decodedText: decodedText, data: data)
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

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
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

    private func isLikelyText(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        var suspiciousScalars = 0
        var totalScalars = 0
        for scalar in text.unicodeScalars {
            totalScalars += 1
            if scalar.value == 0 {
                return false
            }
            if scalar.properties.generalCategory == .control,
               scalar != "\n",
               scalar != "\r",
               scalar != "\t" {
                suspiciousScalars += 1
            }
        }
        guard totalScalars > 0 else { return true }
        return Double(suspiciousScalars) / Double(totalScalars) <= 0.02
    }

    private func renameUnknownEncodingFile(_ url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent + "_unknown_encode"
        var destination = directory.appendingPathComponent(baseName)
        var index = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(baseName) \(index)")
            index += 1
        }
        try fileManager.moveItem(at: url, to: destination)
        return destination.standardizedFileURL
    }
}

private struct DetectedTextEncoding {
    let label: String
    let text: String
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

    private static func candidate(label: String, ianaName: String) -> EncodingCandidate? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(ianaName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        guard nsEncoding != UInt(kCFStringEncodingInvalidId) else { return nil }
        return EncodingCandidate(label: label, encoding: String.Encoding(rawValue: nsEncoding))
    }
}
