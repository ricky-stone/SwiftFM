import Foundation
import FoundationModels

/// `SwiftFM` is a beginner-friendly facade over Apple's Foundation Models framework.
///
/// Quick start:
/// ```swift
/// let fm = SwiftFM()
/// let text = try await fm.generateText(for: "Explain a century break in snooker.")
/// ```
public actor SwiftFM {
    /// The system model to use for a request.
    public enum Model: Sendable {
        case `default`
        case general
        case contentTagging
        case custom(SystemLanguageModel)

        fileprivate var resolvedModel: SystemLanguageModel {
            switch self {
            case .default:
                return .default
            case .general:
                return .init(useCase: .general)
            case .contentTagging:
                return .init(useCase: .contentTagging)
            case .custom(let model):
                return model
            }
        }
    }

    /// Sampling controls for deterministic or creative output.
    public enum Sampling: Sendable, Equatable {
        case automatic
        case greedy
        case randomTopK(Int, seed: UInt64? = nil)
        case randomProbability(Double, seed: UInt64? = nil)

        fileprivate var foundationSampling: GenerationOptions.SamplingMode? {
            switch self {
            case .automatic:
                return nil
            case .greedy:
                return .greedy
            case .randomTopK(let topK, let seed):
                return .random(top: topK, seed: seed)
            case .randomProbability(let threshold, let seed):
                return .random(probabilityThreshold: threshold, seed: seed)
            }
        }
    }

    /// Shared defaults for this client.
    public struct Config: Sendable {
        public var system: String?
        public var model: Model
        public var tools: [any Tool]
        public var temperature: Double?
        public var maximumResponseTokens: Int?
        public var sampling: Sampling

        public init(
            system: String? = nil,
            model: Model = .default,
            tools: [any Tool] = [],
            temperature: Double? = 0.6,
            maximumResponseTokens: Int? = nil,
            sampling: Sampling = .automatic
        ) {
            self.system = system
            self.model = model
            self.tools = tools
            self.temperature = temperature
            self.maximumResponseTokens = maximumResponseTokens
            self.sampling = sampling
        }
    }

    /// One-off overrides for a single request.
    public struct RequestConfig: Sendable {
        public var model: Model?
        public var tools: [any Tool]?
        public var temperature: Double?
        public var maximumResponseTokens: Int?
        public var sampling: Sampling?
        public var includeSchemaInPrompt: Bool

        public init(
            model: Model? = nil,
            tools: [any Tool]? = nil,
            temperature: Double? = nil,
            maximumResponseTokens: Int? = nil,
            sampling: Sampling? = nil,
            includeSchemaInPrompt: Bool = true
        ) {
            self.model = model
            self.tools = tools
            self.temperature = temperature
            self.maximumResponseTokens = maximumResponseTokens
            self.sampling = sampling
            self.includeSchemaInPrompt = includeSchemaInPrompt
        }
    }

    /// Common errors surfaced by `SwiftFM`.
    public enum SwiftFMError: Error, LocalizedError {
        case modelUnavailable(SystemLanguageModel.Availability)
        case contextEncodingFailed
        case generationFailed(Error)
        case toolCallFailed(LanguageModelSession.ToolCallError)

        public var errorDescription: String? {
            switch self {
            case .modelUnavailable(let availability):
                return "Foundation model unavailable: \(String(describing: availability))."
            case .contextEncodingFailed:
                return "Failed to encode context into JSON for the prompt."
            case .generationFailed(let error):
                return "Model generation failed: \(error.localizedDescription)"
            case .toolCallFailed(let error):
                return "Tool call failed for '\(error.tool.name)': \(error.localizedDescription)"
            }
        }
    }

    private let config: Config
    private var session: LanguageModelSession

    /// Create a new client.
    public init(config: Config = .init()) {
        self.config = config
        self.session = Self.makeSession(
            model: config.model,
            tools: config.tools,
            instructions: config.system
        )
    }

    /// Generate plain text from a prompt.
    public func generateText(for prompt: String) async throws -> String {
        try await generateText(for: prompt, request: .init())
    }

    /// Generate plain text from a prompt with one-off overrides.
    public func generateText(
        for prompt: String,
        request: RequestConfig
    ) async throws -> String {
        let p = Prompt(prompt)
        return try await generateText(prompt: p, request: request)
    }

    /// Generate plain text and explicitly choose a model for this request.
    public func generateText(
        for prompt: String,
        using model: Model
    ) async throws -> String {
        try await generateText(
            for: prompt,
            request: .init(model: model)
        )
    }

    /// Generate plain text using a prompt plus any Encodable context object.
    ///
    /// This is useful when your app already has structured API data (for example,
    /// a `Match` model) and you want the model to reason over it.
    public func generateText<Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        request: RequestConfig = .init()
    ) async throws -> String {
        let contextJSON = try Self.encodeContext(context)
        let contextualPrompt = Prompt(
            """
            \(prompt)

            Context JSON:
            \(contextJSON)
            """
        )
        return try await generateText(prompt: contextualPrompt, request: request)
    }

    /// Generate a strongly-typed result using guided generation.
    public func generateJSON<T: Decodable & Sendable & Generable>(
        for prompt: String,
        as type: T.Type,
        request: RequestConfig = .init()
    ) async throws -> T {
        let resolved = resolve(request)
        try Self.ensureModelAvailable(resolved.model)

        do {
            let response = try await resolved.session.respond(
                to: prompt,
                generating: T.self,
                includeSchemaInPrompt: request.includeSchemaInPrompt,
                options: resolved.options
            )
            return response.content
        } catch let toolError as LanguageModelSession.ToolCallError {
            throw SwiftFMError.toolCallFailed(toolError)
        } catch {
            throw SwiftFMError.generationFailed(error)
        }
    }

    /// Generate a strongly-typed result from prompt + context model.
    public func generateJSON<Output: Decodable & Sendable & Generable, Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        as type: Output.Type,
        request: RequestConfig = .init()
    ) async throws -> Output {
        let contextJSON = try Self.encodeContext(context)
        let contextualPrompt = """
        \(prompt)

        Context JSON:
        \(contextJSON)
        """

        return try await generateJSON(
            for: contextualPrompt,
            as: type,
            request: request
        )
    }

    /// Stream text as the model generates it.
    public func streamText(for prompt: String) -> AsyncThrowingStream<String, Error> {
        streamText(for: prompt, request: .init())
    }

    /// Stream text with one-off request overrides.
    public func streamText(
        for prompt: String,
        request: RequestConfig
    ) -> AsyncThrowingStream<String, Error> {
        let resolved = resolve(request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Self.ensureModelAvailable(resolved.model)

                    let stream = resolved.session.streamResponse(
                        to: prompt,
                        options: resolved.options
                    )

                    for try await snapshot in stream {
                        if Task.isCancelled { break }
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Warm up the default session to reduce first-token latency.
    public func prewarm(promptPrefix: String? = nil) {
        if let promptPrefix {
            session.prewarm(promptPrefix: Prompt(promptPrefix))
        } else {
            session.prewarm(promptPrefix: nil)
        }
    }

    /// Reset the default session transcript and conversation state.
    public func resetConversation() {
        session = Self.makeSession(
            model: config.model,
            tools: config.tools,
            instructions: config.system
        )
    }

    /// Transcript of the default session.
    public var transcript: Transcript { session.transcript }

    /// Indicates whether the default session is currently responding.
    public var isBusy: Bool { session.isResponding }

    /// True if the default system model is available on this device.
    public static var isModelAvailable: Bool {
        isAvailable(for: .default)
    }

    /// Detailed availability for the default system model.
    public static var modelAvailability: SystemLanguageModel.Availability {
        availability(for: .default)
    }

    /// True if a specific model is available on this device.
    public static func isAvailable(for model: Model = .default) -> Bool {
        model.resolvedModel.isAvailable
    }

    /// Detailed availability for a specific model.
    public static func availability(for model: Model = .default) -> SystemLanguageModel.Availability {
        model.resolvedModel.availability
    }

    private static func makeSession(
        model: Model,
        tools: [any Tool],
        instructions: String?
    ) -> LanguageModelSession {
        let resolved = model.resolvedModel

        if let instructions {
            return LanguageModelSession(
                model: resolved,
                tools: tools,
                instructions: instructions
            )
        }

        return LanguageModelSession(
            model: resolved,
            tools: tools,
            instructions: nil
        )
    }

    private static func encodeContext<Context: Encodable>(_ context: Context) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let json = try? String(
            data: encoder.encode(context),
            encoding: .utf8
        ) else {
            throw SwiftFMError.contextEncodingFailed
        }

        return json
    }

    private static func ensureModelAvailable(_ model: Model) throws {
        let availability = model.resolvedModel.availability
        guard case .available = availability else {
            throw SwiftFMError.modelUnavailable(availability)
        }
    }

    private func generateText(
        prompt: Prompt,
        request: RequestConfig
    ) async throws -> String {
        let resolved = resolve(request)
        try Self.ensureModelAvailable(resolved.model)

        do {
            let response = try await resolved.session.respond(
                to: prompt,
                options: resolved.options
            )
            return response.content
        } catch let toolError as LanguageModelSession.ToolCallError {
            throw SwiftFMError.toolCallFailed(toolError)
        } catch {
            throw SwiftFMError.generationFailed(error)
        }
    }

    private func resolve(_ request: RequestConfig) -> ResolvedRequest {
        let model = request.model ?? config.model
        let options = Self.makeOptions(
            temperature: request.temperature ?? config.temperature,
            maximumResponseTokens: request.maximumResponseTokens ?? config.maximumResponseTokens,
            sampling: request.sampling ?? config.sampling
        )

        if request.model == nil && request.tools == nil {
            return .init(model: model, options: options, session: session)
        }

        let oneShotSession = Self.makeSession(
            model: model,
            tools: request.tools ?? config.tools,
            instructions: config.system
        )

        return .init(model: model, options: options, session: oneShotSession)
    }

    private static func makeOptions(
        temperature: Double?,
        maximumResponseTokens: Int?,
        sampling: Sampling
    ) -> GenerationOptions {
        var options = GenerationOptions()
        options.temperature = temperature
        options.maximumResponseTokens = maximumResponseTokens
        options.sampling = sampling.foundationSampling
        return options
    }

    private static func map(_ error: Error) -> Error {
        if let toolError = error as? LanguageModelSession.ToolCallError {
            return SwiftFMError.toolCallFailed(toolError)
        }
        if let fmError = error as? SwiftFMError {
            return fmError
        }
        return SwiftFMError.generationFailed(error)
    }

    private struct ResolvedRequest {
        let model: Model
        let options: GenerationOptions
        let session: LanguageModelSession
    }
}
