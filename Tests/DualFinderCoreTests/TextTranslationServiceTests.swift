import Foundation
import Testing
@testable import DualFinderCore

@Suite("TextTranslationService")
struct TextTranslationServiceTests {
    @Test("uses a long default timeout for local LLM requests")
    func usesLongDefaultRequestTimeout() {
        #expect(TranslationPerformanceOptions().requestTimeout == 600)
        #expect(TranslationPerformanceOptions().maxCharactersPerChunk == 4_000)
        #expect(TranslationPerformanceOptions().maxConcurrentRequests == 1)
    }

    @Test("persists providers and the selected provider model")
    func persistsProvidersAndSelectedModel() throws {
        let suiteName = "TextTranslationServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let provider = TranslationProvider(
            name: "本地网关",
            baseURL: "https://example.com/v1",
            token: "secret",
            models: ["model-a", "model-b"]
        )
        let secondProvider = TranslationProvider(
            name: "云端网关",
            baseURL: "https://cloud.example.com/v1",
            token: "other-secret",
            models: ["cloud-model"]
        )
        let configuration = TranslationConfiguration(
            providers: [provider, secondProvider],
            defaultProviderID: secondProvider.id,
            defaultModelName: "cloud-model"
        )
        let store = TranslationConfigurationStore(defaults: defaults)
        store.save(configuration)

        #expect(store.load() == configuration)
        #expect(store.load().selectedModel?.provider.name == "云端网关")
        #expect(store.load().selectedModel?.modelName == "cloud-model")
    }

    @Test("creates a Chinese file with the requested suffix")
    func createsChineseFileWithRequestedSuffix() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("chapter.txt")
        try "Hello\nWorld".write(to: source, atomically: true, encoding: .utf8)
        let provider = makeProvider()
        let client = OpenAICompatibleTranslationClient { request in
            #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["model"] as? String == "model-a")

            return (completionResponse(content: "你好\n世界"), HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!)
        }
        let service = TextTranslationService(client: client)

        let results = try await service.translate(
            files: [source],
            mode: .chineseFile,
            configuration: makeConfiguration(provider: provider)
        )

        let destination = root.url.appendingPathComponent("chapter_cn.txt")
        #expect(results.map(\.destinationURL) == [destination])
        let translated = try String(contentsOf: destination, encoding: .utf8)
        #expect(translated == "你好\n世界")
    }

    @Test("writes each original line followed by its Chinese translation")
    func writesBilingualLinesInOriginalOrder() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("notes.md")
        try "First\nSecond".write(to: source, atomically: true, encoding: .utf8)
        let provider = makeProvider()
        let requestCount = RequestCount()
        let client = OpenAICompatibleTranslationClient { request in
            await requestCount.increment()
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try #require(json["messages"] as? [[String: Any]])
            let prompt = try #require(messages.last?["content"] as? String)
            #expect(!prompt.contains("JSON"))
            #expect(!prompt.contains("输入 JSON 数组"))
            let translation = prompt.contains("First") ? "第一行" : "第二行"
            return (completionResponse(content: translation), HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!)
        }

        _ = try await TextTranslationService(client: client).translate(
            files: [source],
            mode: .bilingualInPlace,
            configuration: makeConfiguration(provider: provider)
        )

        let bilingual = try String(contentsOf: source, encoding: .utf8)
        #expect(await requestCount.value == 2)
        #expect(bilingual == "First\n第一行\nSecond\n第二行")
    }

    @Test("translates each line with one plain-text request")
    func translatesEachLineWithOnePlainTextRequest() async throws {
        let requestCount = RequestCount()
        let client = OpenAICompatibleTranslationClient { request in
            await requestCount.increment()
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try #require(json["messages"] as? [[String: Any]])
            let prompt = try #require(messages.last?["content"] as? String)
            #expect(!prompt.contains("JSON"))
            let translation = prompt.contains("First") ? "第一行" : "第二行"
            return (completionResponse(content: translation), HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!)
        }

        let translations = try await client.translateLines(
            ["First", "Second"],
            provider: makeProvider(),
            modelName: "model-a",
            options: TranslationPerformanceOptions(maxRetries: 2, retryDelayNanoseconds: 0)
        )

        #expect(translations == ["第一行", "第二行"])
        #expect(await requestCount.value == 2)
    }

    @Test("preserves blank bilingual lines without asking the model to translate them")
    func preservesBlankBilingualLines() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("notes.md")
        try "First\n\nSecond".write(to: source, atomically: true, encoding: .utf8)
        let requestCount = RequestCount()
        let client = OpenAICompatibleTranslationClient { request in
            await requestCount.increment()
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try #require(json["messages"] as? [[String: Any]])
            let prompt = try #require(messages.last?["content"] as? String)
            #expect(!prompt.contains("JSON"))
            #expect(!prompt.contains("\n\nSecond"))
            let line = prompt.contains("First") ? "First" : "Second"
            return (completionResponse(content: "中\(line)"), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        _ = try await TextTranslationService(client: client).translate(
            files: [source],
            mode: .bilingualInPlace,
            configuration: makeConfiguration(provider: makeProvider()),
            options: TranslationPerformanceOptions(maxConcurrentFiles: 1, maxCharactersPerChunk: 100)
        )

        #expect(await requestCount.value == 2)
        #expect(try String(contentsOf: source, encoding: .utf8) == "First\n中First\n\n\nSecond\n中Second")
    }

    @Test("rejects a configuration without a selected model")
    func rejectsConfigurationWithoutSelectedModel() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("chapter.txt")
        try "Hello".write(to: source, atomically: true, encoding: .utf8)

        await #expect(throws: TranslationError.noDefaultModel) {
            try await TextTranslationService().translate(
                files: [source],
                mode: .chineseFile,
                configuration: TranslationConfiguration()
            )
        }
    }

    @Test("translates bilingual files one line at a time and reports line progress")
    func translatesBilingualFilesOneLineAtATime() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("notes.md")
        try "one\ntwo\nthree".write(to: source, atomically: true, encoding: .utf8)
        let requestCount = RequestCount()
        let progress = TranslationProgressCollector()
        let client = OpenAICompatibleTranslationClient { request in
            await requestCount.increment()
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try #require(json["messages"] as? [[String: Any]])
            let prompt = try #require(messages.last?["content"] as? String)
            #expect(!prompt.contains("JSON"))
            #expect(!prompt.contains("\none\n\ntwo"))
            let line = try #require(["one", "two", "three"].first(where: { prompt.contains($0) }))
            return (completionResponse(content: "中\(line)"), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let service = TextTranslationService(client: client)
        let options = TranslationPerformanceOptions(maxConcurrentFiles: 1, maxCharactersPerChunk: 4, maxRetries: 0)

        _ = try await service.translate(
            files: [source],
            mode: .bilingualInPlace,
            configuration: makeConfiguration(provider: makeProvider()),
            options: options,
            detailedProgress: { event in
                progress.append(event)
            }
        )

        #expect(await requestCount.value == 3)
        #expect(try String(contentsOf: source, encoding: .utf8) == "one\n中one\ntwo\n中two\nthree\n中three")
        #expect(progress.chunkIndexes.sorted() == [1, 1, 2, 2, 3, 3])
    }

    @Test("translates multiple files with bounded concurrency")
    func translatesFilesWithBoundedConcurrency() async throws {
        let root = try TemporaryDirectory()
        let sources = try (0..<4).map { index in
            let url = root.url.appendingPathComponent("chapter\(index).txt")
            try "Hello \(index)".write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        let stats = ConcurrentRequestStats()
        let client = OpenAICompatibleTranslationClient { request in
            await stats.started()
            try await Task.sleep(for: .milliseconds(20))
            await stats.finished()
            return (completionResponse(content: "你好"), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let options = TranslationPerformanceOptions(maxConcurrentFiles: 2, maxConcurrentRequests: 2, maxCharactersPerChunk: 10_000, maxRetries: 0)

        let results = try await TextTranslationService(client: client).translate(
            files: sources,
            mode: .chineseFile,
            configuration: makeConfiguration(provider: makeProvider()),
            options: options
        )

        #expect(results.count == 4)
        #expect(await stats.value().calls == 4)
        #expect(await stats.value().maxActive == 2)
    }

    @Test("retries transient HTTP failures and applies the request timeout")
    func retriesTransientFailures() async throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("chapter.txt")
        try "Hello".write(to: source, atomically: true, encoding: .utf8)
        let stats = RetryRequestStats()
        let client = OpenAICompatibleTranslationClient { request in
            await stats.record(timeout: request.timeoutInterval)
            let status = await stats.nextStatusCode()
            return (completionResponse(content: "你好"), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let options = TranslationPerformanceOptions(requestTimeout: 17, maxRetries: 1, retryDelayNanoseconds: 0)

        _ = try await TextTranslationService(client: client).translate(
            files: [source],
            mode: .chineseFile,
            configuration: makeConfiguration(provider: makeProvider()),
            options: options
        )

        let value = await stats.value()
        #expect(value.calls == 2)
        #expect(value.timeout == 17)
    }

    @Test("assembles streaming chat completion deltas")
    func assemblesStreamingDeltas() async throws {
        let response = HTTPURLResponse(url: URL(string: "https://example.com/v1/chat/completions")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let client = OpenAICompatibleTranslationClient(
            sender: { _ in fatalError("streaming sender should be used") },
            streamingSender: { request in
                let body = try #require(request.httpBody)
                let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(json["stream"] as? Bool == true)
                let stream = AsyncThrowingStream<String, Error> { continuation in
                    continuation.yield("data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}")
                    continuation.yield("data: {\"choices\":[{\"delta\":{\"content\":\"好\"}}]}")
                    continuation.yield("data: [DONE]")
                    continuation.finish()
                }
                return (response, stream)
            }
        )

        let result = try await client.translateTextStreaming("Hello", provider: makeProvider(), modelName: "model-a")
        #expect(result == "你好")
    }

    private func makeProvider() -> TranslationProvider {
        TranslationProvider(
            name: "测试 Provider",
            baseURL: "https://example.com/v1",
            token: "secret",
            models: ["model-a"]
        )
    }

    private func makeConfiguration(provider: TranslationProvider) -> TranslationConfiguration {
        TranslationConfiguration(
            providers: [provider],
            defaultProviderID: provider.id,
            defaultModelName: provider.models[0]
        )
    }

    private func completionResponse(content: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]]
        ])
    }
}

private actor RequestCount {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private final class TranslationProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [TranslationProgress] = []

    func append(_ event: TranslationProgress) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    var chunkIndexes: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return events.filter { !$0.isStreaming }.map(\.currentChunk)
    }
}

private actor ConcurrentRequestStats {
    private(set) var calls = 0
    private var active = 0
    private(set) var maxActive = 0

    func started() {
        calls += 1
        active += 1
        maxActive = max(maxActive, active)
    }

    func finished() {
        active -= 1
    }

    func value() -> (calls: Int, maxActive: Int) {
        (calls, maxActive)
    }
}

private actor RetryRequestStats {
    private(set) var callCount = 0
    private(set) var timeout: TimeInterval?

    func record(timeout: TimeInterval) {
        callCount += 1
        self.timeout = timeout
    }

    func nextStatusCode() -> Int {
        callCount == 1 ? 503 : 200
    }

    func value() -> (calls: Int, timeout: TimeInterval?) {
        (callCount, timeout)
    }
}
