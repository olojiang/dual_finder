import Foundation

public struct TranslationProvider: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var baseURL: String
    public var token: String
    public var models: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        token: String,
        models: [String]
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.token = token
        self.models = models
    }
}

public struct TranslationModelSelection: Equatable, Sendable {
    public let provider: TranslationProvider
    public let modelName: String

    public init(provider: TranslationProvider, modelName: String) {
        self.provider = provider
        self.modelName = modelName
    }
}

public struct TranslationConfiguration: Codable, Equatable, Sendable {
    public var providers: [TranslationProvider]
    public var defaultProviderID: UUID?
    public var defaultModelName: String?

    public init(
        providers: [TranslationProvider] = [],
        defaultProviderID: UUID? = nil,
        defaultModelName: String? = nil
    ) {
        self.providers = providers
        self.defaultProviderID = defaultProviderID
        self.defaultModelName = defaultModelName
    }

    public var selectedModel: TranslationModelSelection? {
        guard let defaultProviderID,
              let defaultModelName,
              !defaultModelName.isEmpty,
              let provider = providers.first(where: { $0.id == defaultProviderID }),
              provider.models.contains(defaultModelName)
        else {
            return nil
        }
        return TranslationModelSelection(provider: provider, modelName: defaultModelName)
    }
}

public final class TranslationConfigurationStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "textTranslationConfiguration") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> TranslationConfiguration {
        guard let data = defaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(TranslationConfiguration.self, from: data)
        else {
            return TranslationConfiguration()
        }
        return configuration
    }

    public func save(_ configuration: TranslationConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }
}

public enum TranslationMode: String, Codable, Sendable {
    case chineseFile
    case bilingualInPlace
}

public struct TranslationPerformanceOptions: Equatable, Sendable {
    public var maxConcurrentFiles: Int
    public var maxConcurrentRequests: Int
    public var maxCharactersPerChunk: Int
    public var requestTimeout: TimeInterval
    public var maxRetries: Int
    public var retryDelayNanoseconds: UInt64

    public init(
        maxConcurrentFiles: Int = 3,
        maxConcurrentRequests: Int = 1,
        maxCharactersPerChunk: Int = 4_000,
        requestTimeout: TimeInterval = 600,
        maxRetries: Int = 2,
        retryDelayNanoseconds: UInt64 = 500_000_000
    ) {
        self.maxConcurrentFiles = max(1, maxConcurrentFiles)
        self.maxConcurrentRequests = max(1, maxConcurrentRequests)
        self.maxCharactersPerChunk = max(1, maxCharactersPerChunk)
        self.requestTimeout = max(1, requestTimeout)
        self.maxRetries = max(0, maxRetries)
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }
}

public struct TranslationProgress: Sendable {
    public let sourceURL: URL
    public let completedFiles: Int
    public let totalFiles: Int
    public let completedChunks: Int
    public let currentChunk: Int
    public let totalChunks: Int
    public let isStreaming: Bool

    public init(
        sourceURL: URL,
        completedFiles: Int,
        totalFiles: Int,
        completedChunks: Int,
        currentChunk: Int,
        totalChunks: Int,
        isStreaming: Bool = false
    ) {
        self.sourceURL = sourceURL
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.completedChunks = completedChunks
        self.currentChunk = currentChunk
        self.totalChunks = totalChunks
        self.isStreaming = isStreaming
    }
}

public struct TextTranslationResult: Equatable, Sendable {
    public let sourceURL: URL
    public let destinationURL: URL
    public let mode: TranslationMode

    public init(sourceURL: URL, destinationURL: URL, mode: TranslationMode) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.mode = mode
    }
}

public enum TranslationError: LocalizedError, Equatable, Sendable {
    case noDefaultModel
    case invalidProviderURL
    case unsupportedFile(URL)
    case invalidUTF8(URL)
    case emptyResponse
    case invalidResponse
    case httpStatus(Int)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noDefaultModel:
            return "请先在设置中配置并选择默认翻译模型"
        case .invalidProviderURL:
            return "翻译 Provider URL 无效"
        case let .unsupportedFile(url):
            return "仅支持 TXT 或 MD 文件：\(url.lastPathComponent)"
        case let .invalidUTF8(url):
            return "文件不是有效的 UTF-8 文本：\(url.lastPathComponent)"
        case .emptyResponse:
            return "翻译模型返回了空内容"
        case .invalidResponse:
            return "无法解析翻译模型返回的内容"
        case let .httpStatus(status):
            return "翻译接口返回 HTTP \(status)"
        case .cancelled:
            return "翻译已取消"
        }
    }
}

public struct OpenAICompatibleTranslationClient: Sendable {
    public typealias RequestSender = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public typealias StreamingRequestSender = @Sendable (URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>)
    public typealias DiagnosticHandler = @Sendable (_ event: String, _ metadata: [String: String]) -> Void

    private let sender: RequestSender
    private let streamingSender: StreamingRequestSender?
    private let diagnosticHandler: DiagnosticHandler?

    public init(diagnosticHandler: DiagnosticHandler? = nil) {
        self.sender = Self.defaultRequestSender
        self.streamingSender = Self.defaultStreamingRequestSender
        self.diagnosticHandler = diagnosticHandler
    }

    public init(
        sender: @escaping RequestSender,
        streamingSender: StreamingRequestSender? = nil,
        diagnosticHandler: DiagnosticHandler? = nil
    ) {
        self.sender = sender
        self.streamingSender = streamingSender
        self.diagnosticHandler = diagnosticHandler
    }

    public func translateText(
        _ text: String,
        provider: TranslationProvider,
        modelName: String,
        options: TranslationPerformanceOptions = TranslationPerformanceOptions()
    ) async throws -> String {
        let content = """
        请把下面的文本完整翻译成简体中文。保留原文的段落、Markdown 标记、代码、链接、占位符和换行结构，不要添加解释，只返回翻译后的文本。

        原文：
        \(text)
        """
        return try await send(prompt: content, provider: provider, modelName: modelName, options: options)
    }

    public func translateTextStreaming(
        _ text: String,
        provider: TranslationProvider,
        modelName: String,
        options: TranslationPerformanceOptions = TranslationPerformanceOptions(),
        onPartialText: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard streamingSender != nil else {
            return try await translateText(text, provider: provider, modelName: modelName, options: options)
        }
        let content = """
        请把下面的文本完整翻译成简体中文。保留原文的段落、Markdown 标记、代码、链接、占位符和换行结构，不要添加解释，只返回翻译后的文本。

        原文：
        \(text)
        """
        return try await sendStreaming(
            prompt: content,
            provider: provider,
            modelName: modelName,
            options: options,
            onPartialText: onPartialText
        )
    }

    public func translateLines(
        _ lines: [String],
        provider: TranslationProvider,
        modelName: String,
        options: TranslationPerformanceOptions = TranslationPerformanceOptions()
    ) async throws -> [String] {
        var translations: [String] = []
        translations.reserveCapacity(lines.count)
        for line in lines {
            translations.append(try await translateText(
                line,
                provider: provider,
                modelName: modelName,
                options: options
            ))
        }
        return translations
    }

    private func send(
        prompt: String,
        provider: TranslationProvider,
        modelName: String,
        options: TranslationPerformanceOptions
    ) async throws -> String {
        try await retrying(operationName: "text", options: options) {
            try await sendOnce(
                operation: "text",
                prompt: prompt,
                provider: provider,
                modelName: modelName,
                options: options
            )
        }
    }

    private func sendOnce(
        operation: String,
        prompt: String,
        provider: TranslationProvider,
        modelName: String,
        options: TranslationPerformanceOptions
    ) async throws -> String {
        let request = try makeRequest(
            prompt: prompt,
            provider: provider,
            modelName: modelName,
            options: options,
            stream: false
        )
        let (data, response) = try await sender(request)
        emit("response.received", metadata: [
            "operation": operation,
            "provider": provider.name,
            "model": modelName,
            "status": "\(response.statusCode)",
            "bytes": "\(data.count)"
        ])
        guard (200..<300).contains(response.statusCode) else {
            emit("response.http-error", metadata: [
                "operation": operation,
                "provider": provider.name,
                "model": modelName,
                "status": "\(response.statusCode)",
                "body": responseBodySummary(data)
            ])
            throw TranslationError.httpStatus(response.statusCode)
        }
        do {
            let content = try parseCompletion(data)
            emit("response.parsed", metadata: [
                "operation": operation,
                "contentCharacters": "\(content.count)"
            ])
            return content
        } catch {
            emit("response.parse-failed", metadata: [
                "operation": operation,
                "provider": provider.name,
                "model": modelName,
                "bytes": "\(data.count)",
                "error": error.localizedDescription
            ])
            throw error
        }
    }

    private func sendStreaming(
        prompt: String,
        provider: TranslationProvider,
        modelName: String,
        options: TranslationPerformanceOptions,
        onPartialText: (@Sendable (String) -> Void)?
    ) async throws -> String {
        guard let streamingSender else { return try await send(prompt: prompt, provider: provider, modelName: modelName, options: options) }
        return try await retrying(operationName: "text-stream", options: options) {
            let request = try makeRequest(
                prompt: prompt,
                provider: provider,
                modelName: modelName,
                options: options,
                stream: true
            )
            let (response, stream) = try await streamingSender(request)
            self.emit("response.received", metadata: [
                "operation": "text-stream",
                "provider": provider.name,
                "model": modelName,
                "status": "\(response.statusCode)"
            ])
            guard (200..<300).contains(response.statusCode) else {
                throw TranslationError.httpStatus(response.statusCode)
            }
            var result = ""
            for try await line in stream {
                guard let piece = parseStreamLine(line) else { continue }
                result.append(piece)
                onPartialText?(result)
            }
            guard !result.isEmpty else { throw TranslationError.emptyResponse }
            self.emit("response.stream-finished", metadata: [
                "operation": "text-stream",
                "contentCharacters": "\(result.count)"
            ])
            return result
        }
    }

    private func makeRequest(
        prompt: String,
        provider: TranslationProvider,
        modelName: String,
        options: TranslationPerformanceOptions,
        stream: Bool
    ) throws -> URLRequest {
        guard var url = URL(string: provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else {
            throw TranslationError.invalidProviderURL
        }

        if !url.path.lowercased().hasSuffix("/chat/completions") {
            url = url.appendingPathComponent("chat/completions")
        }

        let messages: [[String: String]] = [
            ["role": "system", "content": "你是一个严谨的文本翻译助手。"],
            ["role": "user", "content": prompt]
        ]
        var body: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "temperature": 0.0
        ]
        if stream { body["stream"] = true }
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = options.requestTimeout
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        let token = provider.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func retrying<T>(
        operationName: String,
        options: TranslationPerformanceOptions,
        operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                let canRetry = attempt < options.maxRetries && isRetryable(error) && !Task.isCancelled
                guard canRetry else {
                    emit("request.failed", metadata: [
                        "operation": operationName,
                        "attempt": "\(attempt + 1)",
                        "maxAttempts": "\(options.maxRetries + 1)",
                        "error": error.localizedDescription
                    ])
                    throw error
                }
                attempt += 1
                emit("request.retry", metadata: [
                    "operation": operationName,
                    "attempt": "\(attempt + 1)",
                    "maxAttempts": "\(options.maxRetries + 1)",
                    "error": error.localizedDescription
                ])
                if options.retryDelayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: options.retryDelayNanoseconds)
                }
            }
        }
    }

    private func isRetryable(_ error: Error) -> Bool {
        if let error = error as? TranslationError {
            if case let .httpStatus(status) = error {
                return status == 408 || status == 429 || (500...599).contains(status)
            }
            switch error {
            case .emptyResponse, .invalidResponse:
                return true
            default:
                return false
            }
        }
        if let error = error as? URLError {
            return error.code != .cancelled
        }
        return true
    }

    private func emit(_ event: String, metadata: [String: String]) {
        diagnosticHandler?(event, metadata)
    }

    private func responseBodySummary(_ data: Data) -> String {
        guard let body = String(data: data, encoding: .utf8) else { return "non-utf8" }
        let compact = body
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return String(compact.prefix(240))
    }

    private func parseCompletion(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.invalidResponse
        }
        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw TranslationError.invalidResponse
        }
        guard let content = message["content"] as? String, !content.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return content
    }

    private func parseStreamLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "data: [DONE]" else { return nil }
        let payload = trimmed.hasPrefix("data:")
            ? String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            : trimmed
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (root["choices"] as? [[String: Any]])?.first
        else { return nil }
        if let delta = choice["delta"] as? [String: Any] {
            return delta["content"] as? String
        }
        return (choice["message"] as? [String: Any])?["content"] as? String
    }

    private static let defaultRequestSender: RequestSender = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        return (data, response)
    }

    private static let defaultStreamingRequestSender: StreamingRequestSender = { request in
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let producer = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
        return (response, stream)
    }

}

public struct TextTranslationService: Sendable {
    public typealias ProgressHandler = @Sendable (_ completedCount: Int, _ totalCount: Int, _ sourceURL: URL) -> Void
    public typealias DetailedProgressHandler = @Sendable (_ progress: TranslationProgress) -> Void
    public typealias DiagnosticHandler = @Sendable (_ event: String, _ metadata: [String: String]) -> Void

    private let client: OpenAICompatibleTranslationClient
    private let diagnosticHandler: DiagnosticHandler?

    public init(
        client: OpenAICompatibleTranslationClient = OpenAICompatibleTranslationClient(),
        diagnosticHandler: DiagnosticHandler? = nil
    ) {
        self.client = client
        self.diagnosticHandler = diagnosticHandler
    }

    public func translate(
        files: [URL],
        mode: TranslationMode,
        configuration: TranslationConfiguration,
        cancellation: FileOperationCancellation? = nil,
        progress: ProgressHandler? = nil,
        options: TranslationPerformanceOptions = TranslationPerformanceOptions(),
        detailedProgress: DetailedProgressHandler? = nil
    ) async throws -> [TextTranslationResult] {
        guard let selection = configuration.selectedModel else {
            throw TranslationError.noDefaultModel
        }
        for file in files {
            try validate(file)
        }

        let workerCount = min(options.maxConcurrentFiles, files.count)
        let requestLimiter = TranslationRequestLimiter(limit: options.maxConcurrentRequests)
        var nextIndex = 0
        var completedFiles = 0
        var results = Array<TextTranslationResult?>(repeating: nil, count: files.count)

        return try await withThrowingTaskGroup(of: IndexedTranslationResult.self) { group in
            for _ in 0..<workerCount {
                let index = nextIndex
                nextIndex += 1
                group.addTask {
                    try await self.translateOne(
                        index: index,
                        file: files[index],
                        mode: mode,
                        selection: selection,
                        cancellation: cancellation,
                        options: options,
                        requestLimiter: requestLimiter,
                        detailedProgress: detailedProgress,
                        totalFiles: files.count
                    )
                }
            }

            while let result = try await group.next() {
                results[result.index] = result.value
                completedFiles += 1
                progress?(completedFiles, files.count, result.value.sourceURL)
                if nextIndex < files.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        try await self.translateOne(
                            index: index,
                            file: files[index],
                            mode: mode,
                            selection: selection,
                            cancellation: cancellation,
                            options: options,
                            requestLimiter: requestLimiter,
                            detailedProgress: detailedProgress,
                            totalFiles: files.count
                        )
                    }
                }
            }
            return results.compactMap { $0 }
        }
    }

    private struct IndexedTranslationResult: Sendable {
        let index: Int
        let value: TextTranslationResult
    }

    private func translateOne(
        index: Int,
        file: URL,
        mode: TranslationMode,
        selection: TranslationModelSelection,
        cancellation: FileOperationCancellation?,
        options: TranslationPerformanceOptions,
        requestLimiter: TranslationRequestLimiter,
        detailedProgress: DetailedProgressHandler?,
        totalFiles: Int
    ) async throws -> IndexedTranslationResult {
        try throwIfCancelled(cancellation)
        let source = file.standardizedFileURL
        let data = try Data(contentsOf: source)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TranslationError.invalidUTF8(source)
        }

        let destination: URL
        let translated: String
        switch mode {
        case .chineseFile:
            destination = chineseDestination(for: source)
            translated = try await chineseText(
                from: text,
                source: source,
                selection: selection,
                cancellation: cancellation,
                options: options,
                requestLimiter: requestLimiter,
                detailedProgress: detailedProgress,
                totalFiles: totalFiles
            )
        case .bilingualInPlace:
            destination = source
            translated = try await bilingualText(
                from: text,
                source: source,
                selection: selection,
                cancellation: cancellation,
                options: options,
                requestLimiter: requestLimiter,
                detailedProgress: detailedProgress,
                totalFiles: totalFiles
            )
        }
        try throwIfCancelled(cancellation)
        try translated.write(to: destination, atomically: true, encoding: .utf8)
        return IndexedTranslationResult(
            index: index,
            value: TextTranslationResult(sourceURL: source, destinationURL: destination, mode: mode)
        )
    }

    private func chineseText(
        from text: String,
        source: URL,
        selection: TranslationModelSelection,
        cancellation: FileOperationCancellation?,
        options: TranslationPerformanceOptions,
        requestLimiter: TranslationRequestLimiter,
        detailedProgress: DetailedProgressHandler?,
        totalFiles: Int
    ) async throws -> String {
        let chunks = lineChunks(from: text, maxCharacters: options.maxCharactersPerChunk)
        guard !chunks.isEmpty else { return text }
        var translatedChunks = Array(repeating: "", count: chunks.count)
        var completedChunks = 0
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    try throwIfCancelled(cancellation)
                    let progressThrottle = ProgressThrottle()
                    reportProgress(
                        detailedProgress,
                        source: source,
                        completedFiles: 0,
                        totalFiles: totalFiles,
                        completedChunks: index,
                        currentChunk: index + 1,
                        totalChunks: chunks.count
                    )
                    let translated = try await withRequestPermit(requestLimiter) {
                        try await client.translateTextStreaming(
                            chunk.text,
                            provider: selection.provider,
                            modelName: selection.modelName,
                            options: options,
                            onPartialText: { _ in
                                guard progressThrottle.shouldReport() else { return }
                                reportProgress(
                                    detailedProgress,
                                    source: source,
                                    completedFiles: 0,
                                    totalFiles: totalFiles,
                                    completedChunks: index,
                                    currentChunk: index + 1,
                                    totalChunks: chunks.count,
                                    isStreaming: true
                                )
                            }
                        )
                    }
                    return (index, translated)
                }
            }
            while let (index, translated) = try await group.next() {
                translatedChunks[index] = translated
                completedChunks += 1
                reportProgress(
                    detailedProgress,
                    source: source,
                    completedFiles: 0,
                    totalFiles: totalFiles,
                    completedChunks: completedChunks,
                    currentChunk: index + 1,
                    totalChunks: chunks.count
                )
            }
        }
        return joinLineChunks(translatedChunks, hasTrailingNewline: text.hasSuffix("\n"))
    }

    private func bilingualText(
        from text: String,
        source: URL,
        selection: TranslationModelSelection,
        cancellation: FileOperationCancellation?,
        options: TranslationPerformanceOptions,
        requestLimiter: TranslationRequestLimiter,
        detailedProgress: DetailedProgressHandler?,
        totalFiles: Int
    ) async throws -> String {
        guard !text.isEmpty else { return text }
        let hasTrailingNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        if hasTrailingNewline { _ = lines.popLast() }
        guard !lines.isEmpty else { return text }

        var translatedLines: [String] = []
        translatedLines.reserveCapacity(lines.count)
        var completedLines = 0
        for (index, line) in lines.enumerated() {
            try throwIfCancelled(cancellation)
            reportProgress(
                detailedProgress,
                source: source,
                completedFiles: 0,
                totalFiles: totalFiles,
                completedChunks: completedLines,
                currentChunk: index + 1,
                totalChunks: lines.count
            )
            let translation: String
            if isBlankLine(line) {
                translation = ""
            } else {
                translation = try await withRequestPermit(requestLimiter) {
                    try await client.translateText(
                        line,
                        provider: selection.provider,
                        modelName: selection.modelName,
                        options: options
                    )
                }
            }
            translatedLines.append(translation)
            completedLines += 1
            reportProgress(
                detailedProgress,
                source: source,
                completedFiles: 0,
                totalFiles: totalFiles,
                completedChunks: completedLines,
                currentChunk: index + 1,
                totalChunks: lines.count
            )
        }
        var output: [String] = []
        output.reserveCapacity(lines.count * 2)
        for (original, translation) in zip(lines, translatedLines) {
            output.append(original)
            output.append(translation)
        }
        var result = output.joined(separator: "\n")
        if hasTrailingNewline { result.append("\n") }
        return result
    }

    private func emit(_ event: String, metadata: [String: String]) {
        diagnosticHandler?(event, metadata)
    }

    private struct LineChunk: Sendable {
        let lines: [String]
        let text: String
    }

    private func lineChunks(from text: String, maxCharacters: Int) -> [LineChunk] {
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { _ = lines.popLast() }
        return lineChunks(from: lines, maxCharacters: maxCharacters)
    }

    private func lineChunks(from lines: [String], maxCharacters: Int) -> [LineChunk] {
        guard !lines.isEmpty else { return [] }
        var chunks: [LineChunk] = []
        var current: [String] = []
        var currentCharacters = 0
        for line in lines {
            let addedCharacters = line.count + (current.isEmpty ? 0 : 1)
            if !current.isEmpty && currentCharacters + addedCharacters > maxCharacters {
                chunks.append(LineChunk(lines: current, text: current.joined(separator: "\n")))
                current = []
                currentCharacters = 0
            }
            current.append(line)
            currentCharacters += line.count + (current.count == 1 ? 0 : 1)
        }
        if !current.isEmpty {
            chunks.append(LineChunk(lines: current, text: current.joined(separator: "\n")))
        }
        return chunks
    }

    private func joinLineChunks(_ chunks: [String], hasTrailingNewline: Bool) -> String {
        var result = chunks.joined(separator: "\n")
        if hasTrailingNewline { result.append("\n") }
        return result
    }

    private func reportProgress(
        _ handler: DetailedProgressHandler?,
        source: URL,
        completedFiles: Int,
        totalFiles: Int,
        completedChunks: Int,
        currentChunk: Int,
        totalChunks: Int,
        isStreaming: Bool = false
    ) {
        handler?(TranslationProgress(
            sourceURL: source,
            completedFiles: completedFiles,
            totalFiles: totalFiles,
            completedChunks: completedChunks,
            currentChunk: currentChunk,
            totalChunks: totalChunks,
            isStreaming: isStreaming
        ))
    }

    private func isBlankLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func validate(_ file: URL) throws {
        let ext = file.pathExtension.lowercased()
        guard ext == "txt" || ext == "md" else {
            throw TranslationError.unsupportedFile(file)
        }
    }

    private func chineseDestination(for source: URL) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        let name = "\(stem)_cn.\(source.pathExtension)"
        return source.deletingLastPathComponent().appendingPathComponent(name)
    }

    private func throwIfCancelled(_ cancellation: FileOperationCancellation?) throws {
        if cancellation?.isCancelled == true {
            throw TranslationError.cancelled
        }
    }

    private func withRequestPermit<T>(
        _ limiter: TranslationRequestLimiter,
        operation: () async throws -> T
    ) async throws -> T {
        await limiter.acquire()
        do {
            let result = try await operation()
            await limiter.release()
            return result
        } catch {
            await limiter.release()
            throw error
        }
    }
}

private actor TranslationRequestLimiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        available = max(1, limit)
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            available += 1
        }
    }
}

private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReport = Date.distantPast

    func shouldReport() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(lastReport) >= 0.25 else { return false }
        lastReport = now
        return true
    }
}
