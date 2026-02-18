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

    /// Controls the shape of text emitted by streaming APIs.
    public enum StreamMode: Sendable, Equatable {
        /// Emit the full text generated so far on every update.
        case snapshots
        /// Emit only newly generated text on each update.
        case deltas
    }

    /// Structured prompt builder for better model instruction-following.
    ///
    /// Example:
    /// ```swift
    /// let spec = SwiftFM.PromptSpec(
    ///     task: "Write a short match preview.",
    ///     rules: [
    ///         "Use plain text only",
    ///         "Do not use markdown"
    ///     ],
    ///     outputRequirements: [
    ///         "Exactly 3 short paragraphs"
    ///     ],
    ///     tone: "Professional and engaging"
    /// )
    /// ```
    public struct PromptSpec: Sendable, Equatable {
        public var task: String
        public var rules: [String]
        public var outputRequirements: [String]
        public var tone: String?

        public init(
            task: String,
            rules: [String] = [],
            outputRequirements: [String] = [],
            tone: String? = nil
        ) {
            self.task = task
            self.rules = rules
            self.outputRequirements = outputRequirements
            self.tone = tone
        }

        public func render() -> String {
            var sections: [String] = []
            sections.append("Task:\n\(task)")

            if !rules.isEmpty {
                sections.append("Rules:\n\(Self.numberedList(rules))")
            }

            if !outputRequirements.isEmpty {
                sections.append("Output Requirements:\n\(Self.numberedList(outputRequirements))")
            }

            if let tone, !tone.isEmpty {
                sections.append("Tone:\n\(tone)")
            }

            return sections.joined(separator: "\n\n")
        }

        private static func numberedList(_ items: [String]) -> String {
            items.enumerated().map { index, value in
                "\(index + 1). \(value)"
            }.joined(separator: "\n")
        }
    }

    /// Controls how context models are embedded into prompt text.
    public struct ContextOptions: Sendable, Equatable {
        public enum JSONFormatting: Sendable, Equatable {
            case prettyPrintedSorted
            case compactSorted
            case compact
        }

        public var heading: String
        public var jsonFormatting: JSONFormatting

        public init(
            heading: String = "Context JSON",
            jsonFormatting: JSONFormatting = .prettyPrintedSorted
        ) {
            self.heading = heading
            self.jsonFormatting = jsonFormatting
        }
    }

    /// Optional text cleanup and normalization after model output.
    ///
    /// This is useful for UI-ready output requirements such as:
    /// - removing extra whitespace
    /// - enforcing cleaner paragraph spacing
    /// - rounding decimal numbers for human-readable output
    public struct TextPostProcessing: Sendable, Equatable {
        public var trimWhitespace: Bool
        public var collapseSpacesAndTabs: Bool
        public var maximumConsecutiveNewlines: Int?
        public var roundFloatingPointNumbersTo: Int?

        public init(
            trimWhitespace: Bool = false,
            collapseSpacesAndTabs: Bool = false,
            maximumConsecutiveNewlines: Int? = nil,
            roundFloatingPointNumbersTo: Int? = nil
        ) {
            self.trimWhitespace = trimWhitespace
            self.collapseSpacesAndTabs = collapseSpacesAndTabs

            if let maximumConsecutiveNewlines {
                self.maximumConsecutiveNewlines = max(1, maximumConsecutiveNewlines)
            } else {
                self.maximumConsecutiveNewlines = nil
            }

            if let roundFloatingPointNumbersTo {
                self.roundFloatingPointNumbersTo = max(0, roundFloatingPointNumbersTo)
            } else {
                self.roundFloatingPointNumbersTo = nil
            }
        }

        public static var none: Self { .init() }

        /// Good default for UI text.
        public static var readableParagraphs: Self {
            .init(
                trimWhitespace: true,
                collapseSpacesAndTabs: true,
                maximumConsecutiveNewlines: 2
            )
        }

        /// Round all decimal numbers in text to a fixed number of decimal places.
        /// `0` means whole numbers.
        public static func roundedNumbers(_ places: Int = 0) -> Self {
            .init(roundFloatingPointNumbersTo: places)
        }

        public func apply(to text: String) -> String {
            guard isEnabled else { return text }

            var result = text

            if let places = roundFloatingPointNumbersTo {
                result = Self.roundFloatingPointNumbers(in: result, places: places)
            }

            if collapseSpacesAndTabs {
                result = Self.regexReplacing(
                    pattern: #"[ \t]{2,}"#,
                    with: " ",
                    in: result
                )
            }

            if let maximumConsecutiveNewlines {
                let pattern = "\n{\(maximumConsecutiveNewlines + 1),}"
                let replacement = String(repeating: "\n", count: maximumConsecutiveNewlines)
                result = Self.regexReplacing(
                    pattern: pattern,
                    with: replacement,
                    in: result
                )
            }

            if trimWhitespace {
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return result
        }

        fileprivate var isEnabled: Bool {
            trimWhitespace
                || collapseSpacesAndTabs
                || maximumConsecutiveNewlines != nil
                || roundFloatingPointNumbersTo != nil
        }

        private static func roundFloatingPointNumbers(
            in text: String,
            places: Int
        ) -> String {
            let pattern = #"-?\d+\.\d+(?!\.\d)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return text
            }

            let mutable = NSMutableString(string: text)
            let nsText = text as NSString
            let matches = regex.matches(
                in: text,
                range: NSRange(location: 0, length: nsText.length)
            )

            for match in matches.reversed() {
                let token = nsText.substring(with: match.range)
                guard let value = Double(token) else { continue }

                let rounded = roundedValue(value, places: places)
                let replacement: String

                if places == 0 {
                    replacement = String(Int(rounded))
                } else {
                    replacement = String(format: "%.\(places)f", rounded)
                }

                mutable.replaceCharacters(in: match.range, with: replacement)
            }

            return mutable as String
        }

        private static func roundedValue(_ value: Double, places: Int) -> Double {
            guard places > 0 else {
                return value.rounded()
            }

            let divisor = pow(10.0, Double(places))
            return (value * divisor).rounded() / divisor
        }

        private static func regexReplacing(
            pattern: String,
            with template: String,
            in text: String
        ) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return text
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.stringByReplacingMatches(
                in: text,
                options: [],
                range: range,
                withTemplate: template
            )
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
        public var contextOptions: ContextOptions
        public var postProcessing: TextPostProcessing

        public init(
            system: String? = nil,
            model: Model = .default,
            tools: [any Tool] = [],
            temperature: Double? = 0.6,
            maximumResponseTokens: Int? = nil,
            sampling: Sampling = .automatic,
            contextOptions: ContextOptions = .init(),
            postProcessing: TextPostProcessing = .none
        ) {
            self.system = system
            self.model = model
            self.tools = tools
            self.temperature = temperature
            self.maximumResponseTokens = maximumResponseTokens
            self.sampling = sampling
            self.contextOptions = contextOptions
            self.postProcessing = postProcessing
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
        public var contextOptions: ContextOptions?
        public var postProcessing: TextPostProcessing?

        public init(
            model: Model? = nil,
            tools: [any Tool]? = nil,
            temperature: Double? = nil,
            maximumResponseTokens: Int? = nil,
            sampling: Sampling? = nil,
            includeSchemaInPrompt: Bool = true,
            contextOptions: ContextOptions? = nil,
            postProcessing: TextPostProcessing? = nil
        ) {
            self.model = model
            self.tools = tools
            self.temperature = temperature
            self.maximumResponseTokens = maximumResponseTokens
            self.sampling = sampling
            self.includeSchemaInPrompt = includeSchemaInPrompt
            self.contextOptions = contextOptions
            self.postProcessing = postProcessing
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

    /// Generate plain text from a structured prompt spec.
    public func generateText(
        from spec: PromptSpec,
        request: RequestConfig = .init()
    ) async throws -> String {
        try await generateText(for: spec.render(), request: request)
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
        let contextualPrompt = Prompt(
            try contextPrompt(basePrompt: prompt, context: context, request: request)
        )
        return try await generateText(prompt: contextualPrompt, request: request)
    }

    /// Generate text from a structured prompt spec plus context model.
    public func generateText<Context: Encodable & Sendable>(
        from spec: PromptSpec,
        context: Context,
        request: RequestConfig = .init()
    ) async throws -> String {
        try await generateText(for: spec.render(), context: context, request: request)
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

    /// Generate strongly-typed output from a structured prompt spec.
    public func generateJSON<T: Decodable & Sendable & Generable>(
        from spec: PromptSpec,
        as type: T.Type,
        request: RequestConfig = .init()
    ) async throws -> T {
        try await generateJSON(for: spec.render(), as: type, request: request)
    }

    /// Generate a strongly-typed result from prompt + context model.
    public func generateJSON<Output: Decodable & Sendable & Generable, Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        as type: Output.Type,
        request: RequestConfig = .init()
    ) async throws -> Output {
        let contextualPrompt = try contextPrompt(basePrompt: prompt, context: context, request: request)

        return try await generateJSON(
            for: contextualPrompt,
            as: type,
            request: request
        )
    }

    /// Generate strongly-typed output from structured prompt spec plus context.
    public func generateJSON<Output: Decodable & Sendable & Generable, Context: Encodable & Sendable>(
        from spec: PromptSpec,
        context: Context,
        as type: Output.Type,
        request: RequestConfig = .init()
    ) async throws -> Output {
        try await generateJSON(
            for: spec.render(),
            context: context,
            as: type,
            request: request
        )
    }

    /// Stream text as the model generates it.
    public func streamText(for prompt: String) -> AsyncThrowingStream<String, Error> {
        streamText(for: prompt, request: .init(), mode: .snapshots)
    }

    /// Stream text from a structured prompt spec.
    public func streamText(
        from spec: PromptSpec,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<String, Error> {
        streamText(for: spec.render(), request: request, mode: .snapshots)
    }

    /// Stream text with one-off request overrides.
    public func streamText(
        for prompt: String,
        request: RequestConfig
    ) -> AsyncThrowingStream<String, Error> {
        streamText(for: prompt, request: request, mode: .snapshots)
    }

    /// Stream text with an explicit model for this request.
    public func streamText(
        for prompt: String,
        using model: Model
    ) -> AsyncThrowingStream<String, Error> {
        streamText(for: prompt, request: .init(model: model), mode: .snapshots)
    }

    /// Stream text from prompt + context object.
    ///
    /// This is useful when your app has structured API data and you want
    /// streamed language output without manually encoding context into the prompt.
    public func streamText<Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<String, Error> {
        do {
            let contextualPrompt = try contextPrompt(basePrompt: prompt, context: context, request: request)
            return streamText(for: contextualPrompt, request: request, mode: .snapshots)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    /// Stream text from a structured prompt spec plus context.
    public func streamText<Context: Encodable & Sendable>(
        from spec: PromptSpec,
        context: Context,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<String, Error> {
        streamText(for: spec.render(), context: context, request: request)
    }

    /// Stream text from prompt + context object using an explicit model.
    public func streamText<Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        using model: Model
    ) -> AsyncThrowingStream<String, Error> {
        streamText(for: prompt, context: context, request: .init(model: model))
    }

    /// Stream only newly-generated text chunks (delta updates).
    ///
    /// This is convenient for UI append workflows.
    public func streamTextDeltas(for prompt: String) -> AsyncThrowingStream<String, Error> {
        streamText(for: prompt, request: .init(), mode: .deltas)
    }

    /// Stream delta chunks from a structured prompt spec.
    public func streamTextDeltas(
        from spec: PromptSpec,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<String, Error> {
        streamText(for: spec.render(), request: request, mode: .deltas)
    }

    /// Stream only newly-generated text chunks (delta updates) with request overrides.
    public func streamTextDeltas(
        for prompt: String,
        request: RequestConfig
    ) -> AsyncThrowingStream<String, Error> {
        streamText(for: prompt, request: request, mode: .deltas)
    }

    /// Stream only newly-generated text chunks (delta updates) using prompt + context.
    public func streamTextDeltas<Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<String, Error> {
        do {
            let contextualPrompt = try contextPrompt(basePrompt: prompt, context: context, request: request)
            return streamText(for: contextualPrompt, request: request, mode: .deltas)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    /// Stream delta chunks from a structured prompt spec plus context.
    public func streamTextDeltas<Context: Encodable & Sendable>(
        from spec: PromptSpec,
        context: Context,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<String, Error> {
        streamTextDeltas(for: spec.render(), context: context, request: request)
    }

    private func streamText(
        for prompt: String,
        request: RequestConfig,
        mode: StreamMode
    ) -> AsyncThrowingStream<String, Error> {
        let resolved = resolve(request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Self.ensureModelAvailable(resolved.model)
                    var lastSnapshot = ""

                    let stream = resolved.session.streamResponse(
                        to: prompt,
                        options: resolved.options
                    )

                    for try await snapshot in stream {
                        if Task.isCancelled { break }
                        let current = resolved.postProcessing.apply(to: snapshot.content)

                        switch mode {
                        case .snapshots:
                            continuation.yield(current)
                        case .deltas:
                            if current.hasPrefix(lastSnapshot) {
                                let delta = String(current.dropFirst(lastSnapshot.count))
                                if !delta.isEmpty {
                                    continuation.yield(delta)
                                }
                            } else {
                                continuation.yield(current)
                            }
                            lastSnapshot = current
                        }
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

    private static func encodeContext<Context: Encodable>(
        _ context: Context,
        options: ContextOptions
    ) throws -> String {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.withoutEscapingSlashes]

        switch options.jsonFormatting {
        case .prettyPrintedSorted:
            formatting.formUnion([.prettyPrinted, .sortedKeys])
        case .compactSorted:
            formatting.formUnion([.sortedKeys])
        case .compact:
            break
        }

        encoder.outputFormatting = formatting

        guard let json = try? String(
            data: encoder.encode(context),
            encoding: .utf8
        ) else {
            throw SwiftFMError.contextEncodingFailed
        }

        return json
    }

    private func contextPrompt<Context: Encodable>(
        basePrompt: String,
        context: Context,
        request: RequestConfig
    ) throws -> String {
        let options = request.contextOptions ?? config.contextOptions
        let contextJSON = try Self.encodeContext(context, options: options)
        let heading = options.heading
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHeading = heading.isEmpty ? "Context JSON" : heading

        return """
        \(basePrompt)

        \(resolvedHeading):
        \(contextJSON)
        """
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
            return resolved.postProcessing.apply(to: response.content)
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
        let postProcessing = request.postProcessing ?? config.postProcessing

        if request.model == nil && request.tools == nil {
            return .init(
                model: model,
                options: options,
                session: session,
                postProcessing: postProcessing
            )
        }

        let oneShotSession = Self.makeSession(
            model: model,
            tools: request.tools ?? config.tools,
            instructions: config.system
        )

        return .init(
            model: model,
            options: options,
            session: oneShotSession,
            postProcessing: postProcessing
        )
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
        let postProcessing: TextPostProcessing
    }
}
