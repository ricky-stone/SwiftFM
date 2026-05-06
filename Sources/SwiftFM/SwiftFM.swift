import Foundation
import FoundationModels
import Observation

/// `SwiftFM` is a beginner-friendly facade over Apple's Foundation Models framework.
///
/// Quick start:
/// ```swift
/// let fm = SwiftFM(
///     config: SwiftFM.configuration()
///         .system("You are clear and concise.")
///         .postProcessing(.readableParagraphs)
/// )
///
/// let text = try await fm.generateText(
///     for: "Explain a century break in snooker."
/// )
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

        /// Build a model from a compiled Foundation Models adapter.
        public static func adapter(
            _ adapter: SystemLanguageModel.Adapter,
            guardrails: SystemLanguageModel.Guardrails = .default
        ) -> Self {
            .custom(.init(adapter: adapter, guardrails: guardrails))
        }

        /// Load a Foundation Models adapter by name.
        public static func adapter(
            named name: String,
            guardrails: SystemLanguageModel.Guardrails = .default
        ) throws -> Self {
            try .adapter(.init(name: name), guardrails: guardrails)
        }

        /// Load a Foundation Models adapter from disk.
        public static func adapter(
            fileURL: URL,
            guardrails: SystemLanguageModel.Guardrails = .default
        ) throws -> Self {
            try .adapter(.init(fileURL: fileURL), guardrails: guardrails)
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

    /// Controls whether calls share conversation context or start clean.
    public enum SessionPolicy: Sendable, Equatable {
        /// Every request gets a new Foundation Models session. This is the v3 default.
        case freshPerRequest
        /// Requests reuse the actor's session and transcript until reset.
        case reused
        /// Same reuse behavior, named for apps that want explicit reset control.
        case manual

        fileprivate var usesSharedSession: Bool {
            switch self {
            case .freshPerRequest:
                return false
            case .reused, .manual:
                return true
            }
        }
    }

    /// Conservative fallback actions for common real-app failures.
    public enum FallbackAction: Sendable, Equatable {
        case fail
        case fallbackText(String)
        case retryWithFreshSession
        case retryWithoutOptionalTools
    }

    /// Simple fallback policy for repetitive Foundation Models failure cases.
    public struct FallbackPolicy: Sendable, Equatable {
        public var guardrailViolation: FallbackAction
        public var unavailableModel: FallbackAction
        public var contextOverflow: FallbackAction
        public var toolFailure: FallbackAction

        public init(
            guardrailViolation: FallbackAction = .fail,
            unavailableModel: FallbackAction = .fail,
            contextOverflow: FallbackAction = .fail,
            toolFailure: FallbackAction = .fail
        ) {
            self.guardrailViolation = guardrailViolation
            self.unavailableModel = unavailableModel
            self.contextOverflow = contextOverflow
            self.toolFailure = toolFailure
        }

        public static var none: Self { .init() }

        public func onGuardrailViolation(_ action: FallbackAction) -> Self {
            var copy = self
            copy.guardrailViolation = action
            return copy
        }

        public func onUnavailableModel(_ action: FallbackAction) -> Self {
            var copy = self
            copy.unavailableModel = action
            return copy
        }

        public func retryWithReducedContext() -> Self {
            var copy = self
            copy.contextOverflow = .retryWithFreshSession
            return copy
        }

        public func retryWithoutOptionalTools() -> Self {
            var copy = self
            copy.toolFailure = .retryWithoutOptionalTools
            return copy
        }

        public func fallbackText(_ text: String) -> Self {
            var copy = self
            let action = FallbackAction.fallbackText(text)
            copy.guardrailViolation = action
            copy.unavailableModel = action
            return copy
        }
    }

    /// Opt-in diagnostics for development and testing.
    public struct DebugOptions: Sendable, Equatable {
        public var isEnabled: Bool
        public var printsToConsole: Bool
        public var keepsEvents: Bool
        public var contextWarningRatio: Double

        public init(
            isEnabled: Bool = false,
            printsToConsole: Bool = false,
            keepsEvents: Bool = false,
            contextWarningRatio: Double = 0.8
        ) {
            self.isEnabled = isEnabled
            self.printsToConsole = printsToConsole
            self.keepsEvents = keepsEvents
            self.contextWarningRatio = min(max(contextWarningRatio, 0.1), 1.0)
        }

        public static var disabled: Self { .init() }

        public static var console: Self {
            .init(isEnabled: true, printsToConsole: true, keepsEvents: true)
        }

        public func enabled(_ enabled: Bool = true) -> Self {
            var copy = self
            copy.isEnabled = enabled
            return copy
        }

        public func printingToConsole(_ enabled: Bool = true) -> Self {
            var copy = self
            copy.printsToConsole = enabled
            return copy
        }

        public func keepingEvents(_ enabled: Bool = true) -> Self {
            var copy = self
            copy.keepsEvents = enabled
            return copy
        }

        public func warningNearContextLimit(_ ratio: Double = 0.8) -> Self {
            var copy = self
            copy.contextWarningRatio = min(max(ratio, 0.1), 1.0)
            return copy
        }
    }

    /// A recorded debug event. Events are stored only when debug options ask for them.
    public struct DebugEvent: Sendable, Equatable {
        public let category: String
        public let message: String

        public init(category: String, message: String) {
            self.category = category
            self.message = message
        }
    }

    /// Prompt and context-size information for development diagnostics.
    public struct RequestDiagnostics: Sendable, Equatable {
        public let promptCharacterCount: Int
        public let promptTokenCount: Int?
        public let contextSize: Int
        public let toolCount: Int
        public let sessionPolicy: SessionPolicy

        public var contextUsageRatio: Double? {
            guard let promptTokenCount else { return nil }
            return Double(promptTokenCount) / Double(contextSize)
        }

        public var isNearContextLimit: Bool {
            guard let contextUsageRatio else { return false }
            return contextUsageRatio >= 0.8
        }
    }

    /// A named group of related tools.
    public struct ToolGroup: Sendable {
        public var name: String
        public var tools: [any Tool]

        public init(name: String = "Tools", tools: [any Tool] = []) {
            self.name = name
            self.tools = tools
        }

        public func tool(_ tool: any Tool) -> Self {
            var copy = self
            copy.tools.append(tool)
            return copy
        }

        public func tools(_ tools: [any Tool]) -> Self {
            var copy = self
            copy.tools.append(contentsOf: tools)
            return copy
        }
    }

    /// A small registry for composing shared tool groups.
    public struct ToolRegistry: Sendable {
        public var groups: [ToolGroup]

        public init(groups: [ToolGroup] = []) {
            self.groups = groups
        }

        public var tools: [any Tool] {
            groups.flatMap(\.tools)
        }

        public func group(_ group: ToolGroup) -> Self {
            var copy = self
            copy.groups.append(group)
            return copy
        }

        public func group(named name: String, tools: [any Tool]) -> Self {
            group(.init(name: name, tools: tools))
        }
    }

    /// One generic mixed-content block for structured app UIs.
    @Generable
    public struct ResponseBlock: Decodable, Sendable {
        @Guide(description: "Block kind: text, reference, metadata, or custom", .anyOf(["text", "reference", "metadata", "custom"]))
        public let kind: String

        @Guide(description: "Plain text for text blocks or a short label for other blocks")
        public let text: String?

        @Guide(description: "Stable reference id for app data, documents, records, or external objects")
        public let referenceID: String?

        @Guide(description: "Custom block name when kind is custom or metadata")
        public let name: String?

        @Guide(description: "Small JSON string for metadata or custom payloads")
        public let metadataJSON: String?

        public init(
            kind: String,
            text: String? = nil,
            referenceID: String? = nil,
            name: String? = nil,
            metadataJSON: String? = nil
        ) {
            self.kind = kind
            self.text = text
            self.referenceID = referenceID
            self.name = name
            self.metadataJSON = metadataJSON
        }

        public static func text(_ text: String) -> Self {
            .init(kind: "text", text: text)
        }

        public static func reference(id: String, text: String? = nil) -> Self {
            .init(kind: "reference", text: text, referenceID: id)
        }

        public static func metadata(name: String, json: String) -> Self {
            .init(kind: "metadata", name: name, metadataJSON: json)
        }

        public static func custom(name: String, text: String? = nil, json: String? = nil) -> Self {
            .init(kind: "custom", text: text, name: name, metadataJSON: json)
        }
    }

    /// Ordered mixed-content output for app UIs.
    @Generable
    public struct BlockResponse: Decodable, Sendable {
        @Guide(description: "Ordered blocks to render in the app UI")
        public let blocks: [ResponseBlock]

        public init(blocks: [ResponseBlock]) {
            self.blocks = blocks
        }
    }

    /// Builder for hand-authored block responses in tests or fallbacks.
    public struct BlockResponseBuilder: Sendable {
        public var blocks: [ResponseBlock]

        public init(blocks: [ResponseBlock] = []) {
            self.blocks = blocks
        }

        public func text(_ text: String) -> Self {
            var copy = self
            copy.blocks.append(.text(text))
            return copy
        }

        public func reference(id: String, text: String? = nil) -> Self {
            var copy = self
            copy.blocks.append(.reference(id: id, text: text))
            return copy
        }

        public func metadata(name: String, json: String) -> Self {
            var copy = self
            copy.blocks.append(.metadata(name: name, json: json))
            return copy
        }

        public func custom(name: String, text: String? = nil, json: String? = nil) -> Self {
            var copy = self
            copy.blocks.append(.custom(name: name, text: text, json: json))
            return copy
        }

        public func response() -> BlockResponse {
            .init(blocks: blocks)
        }
    }

    /// Lightweight structured workflow for one clear app task.
    public struct Workflow<Output: Decodable & Sendable & Generable>: Sendable {
        public var config: Config
        public var request: RequestConfig
        public var outputType: Output.Type
        public var fallbackOutput: Output?

        public init(
            generating outputType: Output.Type,
            config: Config = .init(),
            request: RequestConfig = .init(),
            fallbackOutput: Output? = nil
        ) {
            self.outputType = outputType
            self.config = config
            self.request = request
            self.fallbackOutput = fallbackOutput
        }

        public func instructions(_ instructions: String?) -> Self {
            var copy = self
            copy.config = copy.config.system(instructions)
            return copy
        }

        public func model(_ model: Model) -> Self {
            var copy = self
            copy.config = copy.config.model(model)
            return copy
        }

        public func tool(_ tool: any Tool) -> Self {
            var copy = self
            copy.config = copy.config.tool(tool)
            return copy
        }

        public func toolGroup(_ group: ToolGroup) -> Self {
            var copy = self
            copy.config = copy.config.toolGroup(group)
            return copy
        }

        public func request(_ request: RequestConfig) -> Self {
            var copy = self
            copy.request = request
            return copy
        }

        public func fallback(_ output: Output?) -> Self {
            var copy = self
            copy.fallbackOutput = output
            return copy
        }

        public func run(_ prompt: String) async throws -> Output {
            let fm = SwiftFM(config: config)
            do {
                return try await fm.generateJSON(for: prompt, as: outputType, request: request)
            } catch {
                if let fallbackOutput {
                    return fallbackOutput
                }
                throw error
            }
        }

        public func run(_ spec: PromptSpec) async throws -> Output {
            try await run(spec.render())
        }
    }

    /// Begin a beginner-friendly fluent config chain.
    public static func configuration() -> Config { .init() }

    /// Begin a beginner-friendly fluent request chain.
    public static func request() -> RequestConfig { .init() }

    /// Begin a beginner-friendly prompt chain.
    public static func prompt(_ task: String) -> PromptSpec { .init(task: task) }

    /// Begin a named tool group.
    public static func toolGroup(_ name: String = "Tools") -> ToolGroup {
        .init(name: name)
    }

    /// Begin a tool registry.
    public static func toolRegistry() -> ToolRegistry { .init() }

    /// Begin a hand-authored mixed block response.
    public static func blocks() -> BlockResponseBuilder { .init() }

    /// Begin a lightweight structured workflow.
    public static func workflow<Output: Decodable & Sendable & Generable>(
        generating type: Output.Type
    ) -> Workflow<Output> {
        .init(generating: type)
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

        /// Replace the task while keeping the rest of the prompt spec intact.
        public func task(_ task: String) -> Self {
            var copy = self
            copy.task = task
            return copy
        }

        /// Append a single rule in a SwiftUI-like modifier style.
        public func rule(_ rule: String) -> Self {
            var copy = self
            copy.rules.append(rule)
            return copy
        }

        /// Append multiple rules in a SwiftUI-like modifier style.
        public func rules(_ rules: [String]) -> Self {
            var copy = self
            copy.rules.append(contentsOf: rules)
            return copy
        }

        /// Append a single output requirement.
        public func requirement(_ requirement: String) -> Self {
            var copy = self
            copy.outputRequirements.append(requirement)
            return copy
        }

        /// Append multiple output requirements.
        public func requirements(_ requirements: [String]) -> Self {
            var copy = self
            copy.outputRequirements.append(contentsOf: requirements)
            return copy
        }

        /// Set or clear the preferred tone.
        public func tone(_ tone: String?) -> Self {
            var copy = self
            copy.tone = tone
            return copy
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

        /// Set the heading used above the embedded JSON context.
        public func heading(_ heading: String) -> Self {
            var copy = self
            copy.heading = heading
            return copy
        }

        /// Set the JSON formatting used for embedded context.
        public func jsonFormatting(_ formatting: JSONFormatting) -> Self {
            var copy = self
            copy.jsonFormatting = formatting
            return copy
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

        /// Enable or disable outer whitespace trimming.
        public func trimmingWhitespace(_ enabled: Bool = true) -> Self {
            var copy = self
            copy.trimWhitespace = enabled
            return copy
        }

        /// Enable or disable collapsing repeated spaces and tabs.
        public func collapsingSpacesAndTabs(_ enabled: Bool = true) -> Self {
            var copy = self
            copy.collapseSpacesAndTabs = enabled
            return copy
        }

        /// Limit the number of consecutive blank lines in the final text.
        public func limitingConsecutiveNewlines(to count: Int?) -> Self {
            var copy = self
            if let count {
                copy.maximumConsecutiveNewlines = max(1, count)
            } else {
                copy.maximumConsecutiveNewlines = nil
            }
            return copy
        }

        /// Round decimal numbers found in the output text.
        public func roundingFloatingPointNumbers(to places: Int?) -> Self {
            var copy = self
            if let places {
                copy.roundFloatingPointNumbersTo = max(0, places)
            } else {
                copy.roundFloatingPointNumbersTo = nil
            }
            return copy
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
        public var optionalTools: [any Tool]
        public var temperature: Double?
        public var maximumResponseTokens: Int?
        public var sampling: Sampling
        public var contextOptions: ContextOptions
        public var postProcessing: TextPostProcessing
        public var sessionPolicy: SessionPolicy
        public var fallbackPolicy: FallbackPolicy
        public var debugOptions: DebugOptions

        public init(
            system: String? = nil,
            model: Model = .default,
            tools: [any Tool] = [],
            optionalTools: [any Tool] = [],
            temperature: Double? = 0.6,
            maximumResponseTokens: Int? = nil,
            sampling: Sampling = .automatic,
            contextOptions: ContextOptions = .init(),
            postProcessing: TextPostProcessing = .none,
            sessionPolicy: SessionPolicy = .freshPerRequest,
            fallbackPolicy: FallbackPolicy = .none,
            debugOptions: DebugOptions = .disabled
        ) {
            self.system = system
            self.model = model
            self.tools = tools
            self.optionalTools = optionalTools
            self.temperature = temperature
            self.maximumResponseTokens = maximumResponseTokens
            self.sampling = sampling
            self.contextOptions = contextOptions
            self.postProcessing = postProcessing
            self.sessionPolicy = sessionPolicy
            self.fallbackPolicy = fallbackPolicy
            self.debugOptions = debugOptions
        }

        /// A beginner-friendly preset that keeps outputs tidy for UI work.
        public static var beginnerFriendly: Self {
            .init(postProcessing: .readableParagraphs)
        }

        /// Set or clear system instructions.
        public func system(_ system: String?) -> Self {
            var copy = self
            copy.system = system
            return copy
        }

        /// Set the default model for the client.
        public func model(_ model: Model) -> Self {
            var copy = self
            copy.model = model
            return copy
        }

        /// Replace the client tools.
        public func tools(_ tools: [any Tool]) -> Self {
            var copy = self
            copy.tools = tools
            return copy
        }

        /// Append a single tool to the client configuration.
        public func tool(_ tool: any Tool) -> Self {
            var copy = self
            copy.tools.append(tool)
            return copy
        }

        /// Append a related group of tools.
        public func toolGroup(_ group: ToolGroup) -> Self {
            var copy = self
            copy.tools.append(contentsOf: group.tools)
            return copy
        }

        /// Append all tools from a registry.
        public func toolRegistry(_ registry: ToolRegistry) -> Self {
            var copy = self
            copy.tools.append(contentsOf: registry.tools)
            return copy
        }

        /// Replace optional tools. Optional tools can be dropped by fallback retries.
        public func optionalTools(_ optionalTools: [any Tool]) -> Self {
            var copy = self
            copy.optionalTools = optionalTools
            return copy
        }

        /// Append one optional tool.
        public func optionalTool(_ tool: any Tool) -> Self {
            var copy = self
            copy.optionalTools.append(tool)
            return copy
        }

        /// Append an optional tool group.
        public func optionalToolGroup(_ group: ToolGroup) -> Self {
            var copy = self
            copy.optionalTools.append(contentsOf: group.tools)
            return copy
        }

        /// Set temperature.
        public func temperature(_ temperature: Double?) -> Self {
            var copy = self
            copy.temperature = temperature
            return copy
        }

        /// Set a response token limit.
        public func maximumResponseTokens(_ maximumResponseTokens: Int?) -> Self {
            var copy = self
            copy.maximumResponseTokens = maximumResponseTokens
            return copy
        }

        /// Set the sampling strategy.
        public func sampling(_ sampling: Sampling) -> Self {
            var copy = self
            copy.sampling = sampling
            return copy
        }

        /// Replace context embedding options.
        public func contextOptions(_ contextOptions: ContextOptions) -> Self {
            var copy = self
            copy.contextOptions = contextOptions
            return copy
        }

        /// Replace text post-processing options.
        public func postProcessing(_ postProcessing: TextPostProcessing) -> Self {
            var copy = self
            copy.postProcessing = postProcessing
            return copy
        }

        /// Use a clean Foundation Models session for every request.
        public func freshSessionPerRequest() -> Self {
            sessionPolicy(.freshPerRequest)
        }

        /// Reuse the session transcript across requests for conversation-style apps.
        public func reusingSession() -> Self {
            sessionPolicy(.reused)
        }

        /// Reuse the session, with reset/clear calls controlled by the developer.
        public func manualSession() -> Self {
            sessionPolicy(.manual)
        }

        /// Set session/context behavior.
        public func sessionPolicy(_ sessionPolicy: SessionPolicy) -> Self {
            var copy = self
            copy.sessionPolicy = sessionPolicy
            return copy
        }

        /// Set fallback behavior.
        public func fallbackPolicy(_ fallbackPolicy: FallbackPolicy) -> Self {
            var copy = self
            copy.fallbackPolicy = fallbackPolicy
            return copy
        }

        /// Convenience for guardrail fallback text.
        public func onGuardrailViolation(_ action: FallbackAction) -> Self {
            fallbackPolicy(fallbackPolicy.onGuardrailViolation(action))
        }

        /// Convenience for unavailable-model fallback behavior.
        public func onUnavailableModel(_ action: FallbackAction) -> Self {
            fallbackPolicy(fallbackPolicy.onUnavailableModel(action))
        }

        /// Set one fallback text for guardrail and unavailable-model failures.
        public func fallbackText(_ text: String) -> Self {
            fallbackPolicy(fallbackPolicy.fallbackText(text))
        }

        /// Retry context-window failures with a fresh session.
        public func retryWithReducedContext() -> Self {
            fallbackPolicy(fallbackPolicy.retryWithReducedContext())
        }

        /// Retry tool failures without optional tools.
        public func retryWithoutOptionalTools() -> Self {
            fallbackPolicy(fallbackPolicy.retryWithoutOptionalTools())
        }

        /// Set development diagnostics.
        public func debug(_ debugOptions: DebugOptions = .console) -> Self {
            var copy = self
            copy.debugOptions = debugOptions
            return copy
        }
    }

    /// One-off overrides for a single request.
    public struct RequestConfig: Sendable {
        public var model: Model?
        public var tools: [any Tool]?
        public var optionalTools: [any Tool]?
        public var temperature: Double?
        public var maximumResponseTokens: Int?
        public var sampling: Sampling?
        public var includeSchemaInPrompt: Bool
        public var contextOptions: ContextOptions?
        public var postProcessing: TextPostProcessing?
        public var sessionPolicy: SessionPolicy?
        public var fallbackPolicy: FallbackPolicy?
        public var debugOptions: DebugOptions?

        public init(
            model: Model? = nil,
            tools: [any Tool]? = nil,
            optionalTools: [any Tool]? = nil,
            temperature: Double? = nil,
            maximumResponseTokens: Int? = nil,
            sampling: Sampling? = nil,
            includeSchemaInPrompt: Bool = true,
            contextOptions: ContextOptions? = nil,
            postProcessing: TextPostProcessing? = nil,
            sessionPolicy: SessionPolicy? = nil,
            fallbackPolicy: FallbackPolicy? = nil,
            debugOptions: DebugOptions? = nil
        ) {
            self.model = model
            self.tools = tools
            self.optionalTools = optionalTools
            self.temperature = temperature
            self.maximumResponseTokens = maximumResponseTokens
            self.sampling = sampling
            self.includeSchemaInPrompt = includeSchemaInPrompt
            self.contextOptions = contextOptions
            self.postProcessing = postProcessing
            self.sessionPolicy = sessionPolicy
            self.fallbackPolicy = fallbackPolicy
            self.debugOptions = debugOptions
        }

        /// A beginner-friendly request preset that keeps text outputs tidy.
        public static var beginnerFriendly: Self {
            .init(postProcessing: .readableParagraphs)
        }

        /// Override the model for this request.
        public func model(_ model: Model?) -> Self {
            var copy = self
            copy.model = model
            return copy
        }

        /// Replace the request-scoped tools.
        public func tools(_ tools: [any Tool]?) -> Self {
            var copy = self
            copy.tools = tools
            return copy
        }

        /// Append a request-scoped tool.
        public func tool(_ tool: any Tool) -> Self {
            var copy = self
            copy.tools = (copy.tools ?? []) + [tool]
            return copy
        }

        /// Append a related group of request-scoped tools.
        public func toolGroup(_ group: ToolGroup) -> Self {
            var copy = self
            copy.tools = (copy.tools ?? []) + group.tools
            return copy
        }

        /// Append all tools from a registry.
        public func toolRegistry(_ registry: ToolRegistry) -> Self {
            var copy = self
            copy.tools = (copy.tools ?? []) + registry.tools
            return copy
        }

        /// Replace optional request-scoped tools.
        public func optionalTools(_ optionalTools: [any Tool]?) -> Self {
            var copy = self
            copy.optionalTools = optionalTools
            return copy
        }

        /// Append an optional request-scoped tool.
        public func optionalTool(_ tool: any Tool) -> Self {
            var copy = self
            copy.optionalTools = (copy.optionalTools ?? []) + [tool]
            return copy
        }

        /// Append an optional request-scoped tool group.
        public func optionalToolGroup(_ group: ToolGroup) -> Self {
            var copy = self
            copy.optionalTools = (copy.optionalTools ?? []) + group.tools
            return copy
        }

        /// Override temperature for this request.
        public func temperature(_ temperature: Double?) -> Self {
            var copy = self
            copy.temperature = temperature
            return copy
        }

        /// Override the response token limit for this request.
        public func maximumResponseTokens(_ maximumResponseTokens: Int?) -> Self {
            var copy = self
            copy.maximumResponseTokens = maximumResponseTokens
            return copy
        }

        /// Override sampling for this request.
        public func sampling(_ sampling: Sampling?) -> Self {
            var copy = self
            copy.sampling = sampling
            return copy
        }

        /// Control whether Foundation Models injects the schema into the prompt.
        public func includeSchemaInPrompt(_ includeSchemaInPrompt: Bool) -> Self {
            var copy = self
            copy.includeSchemaInPrompt = includeSchemaInPrompt
            return copy
        }

        /// Override context embedding options.
        public func contextOptions(_ contextOptions: ContextOptions?) -> Self {
            var copy = self
            copy.contextOptions = contextOptions
            return copy
        }

        /// Override text post-processing options.
        public func postProcessing(_ postProcessing: TextPostProcessing?) -> Self {
            var copy = self
            copy.postProcessing = postProcessing
            return copy
        }

        /// Use a clean Foundation Models session for this request.
        public func freshSession() -> Self {
            sessionPolicy(.freshPerRequest)
        }

        /// Reuse the actor's session for this request.
        public func reusedSession() -> Self {
            sessionPolicy(.reused)
        }

        /// Set request-level session behavior.
        public func sessionPolicy(_ sessionPolicy: SessionPolicy?) -> Self {
            var copy = self
            copy.sessionPolicy = sessionPolicy
            return copy
        }

        /// Set request-level fallback behavior.
        public func fallbackPolicy(_ fallbackPolicy: FallbackPolicy?) -> Self {
            var copy = self
            copy.fallbackPolicy = fallbackPolicy
            return copy
        }

        /// Convenience for request-level guardrail fallback behavior.
        public func onGuardrailViolation(_ action: FallbackAction) -> Self {
            fallbackPolicy((fallbackPolicy ?? .none).onGuardrailViolation(action))
        }

        /// Convenience for request-level unavailable-model fallback behavior.
        public func onUnavailableModel(_ action: FallbackAction) -> Self {
            fallbackPolicy((fallbackPolicy ?? .none).onUnavailableModel(action))
        }

        /// Set one fallback text for guardrail and unavailable-model failures.
        public func fallbackText(_ text: String) -> Self {
            fallbackPolicy((fallbackPolicy ?? .none).fallbackText(text))
        }

        /// Retry context-window failures with a fresh session.
        public func retryWithReducedContext() -> Self {
            fallbackPolicy((fallbackPolicy ?? .none).retryWithReducedContext())
        }

        /// Retry tool failures without optional tools.
        public func retryWithoutOptionalTools() -> Self {
            fallbackPolicy((fallbackPolicy ?? .none).retryWithoutOptionalTools())
        }

        /// Set request-level diagnostics.
        public func debug(_ debugOptions: DebugOptions? = .console) -> Self {
            var copy = self
            copy.debugOptions = debugOptions
            return copy
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
                if let generationError = error as? LanguageModelSession.GenerationError {
                    return Self.describe(generationError)
                }
                return "Model generation failed: \(error.localizedDescription)"
            case .toolCallFailed(let error):
                return "Tool call failed for '\(error.tool.name)': \(error.localizedDescription)"
            }
        }

        /// The underlying Foundation Models generation error when available.
        public var generationError: LanguageModelSession.GenerationError? {
            guard case .generationFailed(let error) = self else { return nil }
            return error as? LanguageModelSession.GenerationError
        }

        /// The underlying error payload when available.
        public var underlyingError: Error? {
            switch self {
            case .generationFailed(let error):
                return error
            case .toolCallFailed(let error):
                return error
            case .modelUnavailable, .contextEncodingFailed:
                return nil
            }
        }

        private static func describe(_ error: LanguageModelSession.GenerationError) -> String {
            switch error {
            case .exceededContextWindowSize:
                return "The prompt and transcript are too large for the current model context window."
            case .assetsUnavailable:
                return "The selected Foundation Models assets are not currently available on this device."
            case .guardrailViolation:
                return "Safety guardrails were triggered by the prompt or generated response."
            case .unsupportedGuide:
                return "The request uses a generation guide that the current model does not support."
            case .unsupportedLanguageOrLocale:
                return "The current language or locale is not supported by the selected model."
            case .decodingFailure:
                return "The model response could not be decoded into the requested structure."
            case .rateLimited:
                return "The model is temporarily rate limited. Please try again."
            case .concurrentRequests:
                return "The current session is already handling another request."
            case .refusal:
                return "The model refused to answer this request."
            @unknown default:
                return "Model generation failed: \(error.localizedDescription)"
            }
        }
    }

    private let config: Config
    private var session: LanguageModelSession
    private var debugEventsStorage: [DebugEvent] = []

    /// Create a new client.
    public init(config: Config = .init()) {
        self.config = config
        self.session = Self.makeSession(
            model: config.model,
            tools: config.tools + config.optionalTools,
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
        try await generateText(promptText: prompt, request: request)
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
        let contextualPrompt = try contextPrompt(basePrompt: prompt, context: context, request: request)
        return try await generateText(promptText: contextualPrompt, request: request)
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
        try await inspectIfNeeded(promptText: prompt, resolved: resolved)

        do {
            try Self.ensureModelAvailable(resolved.model)
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
            throw Self.map(error)
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

    /// Generate runtime-structured content using a Foundation Models schema.
    public func generateContent(
        for prompt: String,
        schema: GenerationSchema,
        request: RequestConfig = .init()
    ) async throws -> GeneratedContent {
        try await generateContent(prompt: prompt, schema: schema, request: request)
    }

    /// Generate runtime-structured content from a prompt spec.
    public func generateContent(
        from spec: PromptSpec,
        schema: GenerationSchema,
        request: RequestConfig = .init()
    ) async throws -> GeneratedContent {
        try await generateContent(for: spec.render(), schema: schema, request: request)
    }

    /// Generate runtime-structured content from prompt + context.
    public func generateContent<Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        schema: GenerationSchema,
        request: RequestConfig = .init()
    ) async throws -> GeneratedContent {
        let contextualPrompt = try contextPrompt(basePrompt: prompt, context: context, request: request)
        return try await generateContent(for: contextualPrompt, schema: schema, request: request)
    }

    /// Generate runtime-structured content from prompt spec + context.
    public func generateContent<Context: Encodable & Sendable>(
        from spec: PromptSpec,
        context: Context,
        schema: GenerationSchema,
        request: RequestConfig = .init()
    ) async throws -> GeneratedContent {
        try await generateContent(
            for: spec.render(),
            context: context,
            schema: schema,
            request: request
        )
    }

    /// Generate runtime-structured content from a dynamic schema tree.
    public func generateContent(
        for prompt: String,
        dynamicSchema: DynamicGenerationSchema,
        dependencies: [DynamicGenerationSchema] = [],
        request: RequestConfig = .init()
    ) async throws -> GeneratedContent {
        let schema = try GenerationSchema(root: dynamicSchema, dependencies: dependencies)
        return try await generateContent(for: prompt, schema: schema, request: request)
    }

    /// Generate runtime-structured content from a prompt spec and dynamic schema.
    public func generateContent(
        from spec: PromptSpec,
        dynamicSchema: DynamicGenerationSchema,
        dependencies: [DynamicGenerationSchema] = [],
        request: RequestConfig = .init()
    ) async throws -> GeneratedContent {
        try await generateContent(
            for: spec.render(),
            dynamicSchema: dynamicSchema,
            dependencies: dependencies,
            request: request
        )
    }

    /// Generate runtime-structured content from prompt + context using a dynamic schema.
    public func generateContent<Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        dynamicSchema: DynamicGenerationSchema,
        dependencies: [DynamicGenerationSchema] = [],
        request: RequestConfig = .init()
    ) async throws -> GeneratedContent {
        let schema = try GenerationSchema(root: dynamicSchema, dependencies: dependencies)
        return try await generateContent(
            for: prompt,
            context: context,
            schema: schema,
            request: request
        )
    }

    /// Generate runtime-structured content from prompt spec + context using a dynamic schema.
    public func generateContent<Context: Encodable & Sendable>(
        from spec: PromptSpec,
        context: Context,
        dynamicSchema: DynamicGenerationSchema,
        dependencies: [DynamicGenerationSchema] = [],
        request: RequestConfig = .init()
    ) async throws -> GeneratedContent {
        try await generateContent(
            for: spec.render(),
            context: context,
            dynamicSchema: dynamicSchema,
            dependencies: dependencies,
            request: request
        )
    }

    /// Stream guided generation snapshots for a typed `@Generable` model.
    public func streamJSON<T: Decodable & Sendable & Generable>(
        for prompt: String,
        as type: T.Type,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<T.PartiallyGenerated, Error> where T.PartiallyGenerated: Sendable {
        streamGenerated(for: prompt, as: type, request: request)
    }

    /// Stream guided generation snapshots from a prompt spec.
    public func streamJSON<T: Decodable & Sendable & Generable>(
        from spec: PromptSpec,
        as type: T.Type,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<T.PartiallyGenerated, Error> where T.PartiallyGenerated: Sendable {
        streamJSON(for: spec.render(), as: type, request: request)
    }

    /// Stream guided generation snapshots from prompt + context.
    public func streamJSON<Output: Decodable & Sendable & Generable, Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        as type: Output.Type,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<Output.PartiallyGenerated, Error> where Output.PartiallyGenerated: Sendable {
        do {
            let contextualPrompt = try contextPrompt(basePrompt: prompt, context: context, request: request)
            return streamJSON(for: contextualPrompt, as: type, request: request)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    /// Stream guided generation snapshots from prompt spec + context.
    public func streamJSON<Output: Decodable & Sendable & Generable, Context: Encodable & Sendable>(
        from spec: PromptSpec,
        context: Context,
        as type: Output.Type,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<Output.PartiallyGenerated, Error> where Output.PartiallyGenerated: Sendable {
        streamJSON(for: spec.render(), context: context, as: type, request: request)
    }

    /// Stream runtime-structured content snapshots for a Foundation Models schema.
    public func streamContent(
        for prompt: String,
        schema: GenerationSchema,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<GeneratedContent, Error> {
        streamGeneratedContent(for: prompt, schema: schema, request: request)
    }

    /// Stream runtime-structured content snapshots from a prompt spec.
    public func streamContent(
        from spec: PromptSpec,
        schema: GenerationSchema,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<GeneratedContent, Error> {
        streamContent(for: spec.render(), schema: schema, request: request)
    }

    /// Stream runtime-structured content snapshots from prompt + context.
    public func streamContent<Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        schema: GenerationSchema,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<GeneratedContent, Error> {
        do {
            let contextualPrompt = try contextPrompt(basePrompt: prompt, context: context, request: request)
            return streamContent(for: contextualPrompt, schema: schema, request: request)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    /// Stream runtime-structured content snapshots from prompt spec + context.
    public func streamContent<Context: Encodable & Sendable>(
        from spec: PromptSpec,
        context: Context,
        schema: GenerationSchema,
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<GeneratedContent, Error> {
        streamContent(for: spec.render(), context: context, schema: schema, request: request)
    }

    /// Stream runtime-structured content snapshots from a dynamic schema tree.
    public func streamContent(
        for prompt: String,
        dynamicSchema: DynamicGenerationSchema,
        dependencies: [DynamicGenerationSchema] = [],
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<GeneratedContent, Error> {
        do {
            let schema = try GenerationSchema(root: dynamicSchema, dependencies: dependencies)
            return streamContent(for: prompt, schema: schema, request: request)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    /// Stream runtime-structured content snapshots from a prompt spec and dynamic schema.
    public func streamContent(
        from spec: PromptSpec,
        dynamicSchema: DynamicGenerationSchema,
        dependencies: [DynamicGenerationSchema] = [],
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<GeneratedContent, Error> {
        streamContent(
            for: spec.render(),
            dynamicSchema: dynamicSchema,
            dependencies: dependencies,
            request: request
        )
    }

    /// Stream runtime-structured content snapshots from prompt + context using a dynamic schema.
    public func streamContent<Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        dynamicSchema: DynamicGenerationSchema,
        dependencies: [DynamicGenerationSchema] = [],
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<GeneratedContent, Error> {
        do {
            let contextualPrompt = try contextPrompt(basePrompt: prompt, context: context, request: request)
            return streamContent(
                for: contextualPrompt,
                dynamicSchema: dynamicSchema,
                dependencies: dependencies,
                request: request
            )
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    /// Stream runtime-structured content snapshots from prompt spec + context using a dynamic schema.
    public func streamContent<Context: Encodable & Sendable>(
        from spec: PromptSpec,
        context: Context,
        dynamicSchema: DynamicGenerationSchema,
        dependencies: [DynamicGenerationSchema] = [],
        request: RequestConfig = .init()
    ) -> AsyncThrowingStream<GeneratedContent, Error> {
        streamContent(
            for: spec.render(),
            context: context,
            dynamicSchema: dynamicSchema,
            dependencies: dependencies,
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

    /// Warm up the shared reusable session to reduce first-token latency.
    public func prewarm(promptPrefix: String? = nil) {
        if let promptPrefix {
            session.prewarm(promptPrefix: Prompt(promptPrefix))
        } else {
            session.prewarm(promptPrefix: nil)
        }
    }

    /// Export a feedback attachment for the current session transcript.
    @discardableResult
    public func feedbackAttachment(
        sentiment: LanguageModelFeedback.Sentiment? = nil,
        issues: [LanguageModelFeedback.Issue] = [],
        desiredOutput: Transcript.Entry? = nil
    ) -> Data {
        session.logFeedbackAttachment(
            sentiment: sentiment,
            issues: issues,
            desiredOutput: desiredOutput
        )
    }

    /// Export a feedback attachment with plain-text desired output.
    @discardableResult
    public func feedbackAttachment(
        sentiment: LanguageModelFeedback.Sentiment? = nil,
        issues: [LanguageModelFeedback.Issue] = [],
        desiredResponseText: String?
    ) -> Data {
        session.logFeedbackAttachment(
            sentiment: sentiment,
            issues: issues,
            desiredResponseText: desiredResponseText
        )
    }

    /// Export a feedback attachment with structured desired output.
    @discardableResult
    public func feedbackAttachment(
        sentiment: LanguageModelFeedback.Sentiment? = nil,
        issues: [LanguageModelFeedback.Issue] = [],
        desiredResponseContent: (any ConvertibleToGeneratedContent)?
    ) -> Data {
        session.logFeedbackAttachment(
            sentiment: sentiment,
            issues: issues,
            desiredResponseContent: desiredResponseContent
        )
    }

    /// Reset the shared reusable session transcript and conversation state.
    public func resetConversation() {
        session = Self.makeSession(
            model: config.model,
            tools: config.tools + config.optionalTools,
            instructions: config.system
        )
    }

    /// Alias for `resetConversation()` that reads naturally with manual sessions.
    public func clearSession() {
        resetConversation()
    }

    /// Transcript of the shared reusable session.
    public var transcript: Transcript { session.transcript }

    /// Indicates whether the shared reusable session is currently responding.
    public var isBusy: Bool { session.isResponding }

    /// Stored debug events for this actor, when enabled by `DebugOptions`.
    public var debugEvents: [DebugEvent] { debugEventsStorage }

    /// Clear stored debug events.
    public func clearDebugEvents() {
        debugEventsStorage.removeAll()
    }

    /// Inspect prompt size and context usage without sending a generation request.
    @available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
    public func inspectRequest(
        for prompt: String,
        request: RequestConfig = .init()
    ) async throws -> RequestDiagnostics {
        let resolved = resolve(request)
        return try await diagnostics(for: prompt, resolved: resolved)
    }

    /// Inspect prompt + encoded context size without sending a generation request.
    @available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
    public func inspectRequest<Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        request: RequestConfig = .init()
    ) async throws -> RequestDiagnostics {
        let contextualPrompt = try contextPrompt(basePrompt: prompt, context: context, request: request)
        return try await inspectRequest(for: contextualPrompt, request: request)
    }

    /// Estimate the token count for a plain-text prompt using the resolved request model.
    @available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
    public func tokenCount(
        for prompt: String,
        request: RequestConfig = .init()
    ) async throws -> Int {
        let model = resolve(request).model.resolvedModel
        return try await model.tokenCount(for: Prompt(prompt))
    }

    /// Estimate the token count for a prompt spec.
    @available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
    public func tokenCount(
        from spec: PromptSpec,
        request: RequestConfig = .init()
    ) async throws -> Int {
        try await tokenCount(for: spec.render(), request: request)
    }

    /// Estimate the token count for a prompt that includes encoded context.
    @available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
    public func tokenCount<Context: Encodable & Sendable>(
        for prompt: String,
        context: Context,
        request: RequestConfig = .init()
    ) async throws -> Int {
        let contextualPrompt = try contextPrompt(basePrompt: prompt, context: context, request: request)
        return try await tokenCount(for: contextualPrompt, request: request)
    }

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

    /// Languages supported by a specific model.
    public static func supportedLanguages(for model: Model = .default) -> Set<Locale.Language> {
        model.resolvedModel.supportedLanguages
    }

    /// Whether a model supports a specific locale.
    public static func supports(
        locale: Locale = .current,
        for model: Model = .default
    ) -> Bool {
        model.resolvedModel.supportsLocale(locale)
    }

    /// Whether a model supports the current locale.
    public static func supportsCurrentLocale(for model: Model = .default) -> Bool {
        supports(locale: .current, for: model)
    }

    /// Estimate the token count for a prompt using a specific model.
    @available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
    public static func tokenCount(
        for prompt: String,
        model: Model = .default
    ) async throws -> Int {
        try await model.resolvedModel.tokenCount(for: Prompt(prompt))
    }

    /// Estimate the token count for configured tools.
    @available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
    public static func tokenCount(
        for tools: [any Tool],
        model: Model = .default
    ) async throws -> Int {
        try await model.resolvedModel.tokenCount(for: tools)
    }

    /// Estimate the token count for a generation schema.
    @available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
    public static func tokenCount(
        for schema: GenerationSchema,
        model: Model = .default
    ) async throws -> Int {
        try await model.resolvedModel.tokenCount(for: schema)
    }

    /// Estimate the token count for transcript entries.
    @available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
    public static func tokenCount(
        for transcriptEntries: [Transcript.Entry],
        model: Model = .default
    ) async throws -> Int {
        try await model.resolvedModel.tokenCount(for: transcriptEntries)
    }

    /// Tool call names found in a transcript.
    public static func toolCallNames(in transcript: Transcript) -> [String] {
        transcript.flatMap { entry -> [String] in
            guard case .toolCalls(let calls) = entry else { return [] }
            return calls.map(\.toolName)
        }
    }

    /// Tool output names found in a transcript.
    public static func toolOutputNames(in transcript: Transcript) -> [String] {
        transcript.compactMap { entry -> String? in
            guard case .toolOutput(let output) = entry else { return nil }
            return output.toolName
        }
    }

    /// Readable structured-output shape for logs and tests.
    public static func structuredOutputDescription(_ content: GeneratedContent) -> String {
        content.debugDescription
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
        promptText: String,
        request: RequestConfig,
        forcedSessionPolicy: SessionPolicy? = nil,
        includeOptionalTools: Bool = true,
        retryCount: Int = 0
    ) async throws -> String {
        let resolved = resolve(
            request,
            forcedSessionPolicy: forcedSessionPolicy,
            includeOptionalTools: includeOptionalTools
        )
        try await inspectIfNeeded(promptText: promptText, resolved: resolved)

        do {
            try Self.ensureModelAvailable(resolved.model)
            let response = try await resolved.session.respond(
                to: Prompt(promptText),
                options: resolved.options
            )
            return resolved.postProcessing.apply(to: response.content)
        } catch {
            return try await recoverText(
                from: Self.map(error),
                promptText: promptText,
                request: request,
                resolved: resolved,
                includeOptionalTools: includeOptionalTools,
                retryCount: retryCount
            )
        }
    }

    private func generateContent(
        prompt: String,
        schema: GenerationSchema,
        request: RequestConfig
    ) async throws -> GeneratedContent {
        let resolved = resolve(request)
        try await inspectIfNeeded(promptText: prompt, resolved: resolved)

        do {
            try Self.ensureModelAvailable(resolved.model)
            let response = try await resolved.session.respond(
                to: prompt,
                schema: schema,
                includeSchemaInPrompt: request.includeSchemaInPrompt,
                options: resolved.options
            )
            return response.content
        } catch let toolError as LanguageModelSession.ToolCallError {
            throw SwiftFMError.toolCallFailed(toolError)
        } catch {
            throw Self.map(error)
        }
    }

    private func streamGenerated<Content: Generable>(
        for prompt: String,
        as type: Content.Type,
        request: RequestConfig
    ) -> AsyncThrowingStream<Content.PartiallyGenerated, Error> where Content.PartiallyGenerated: Sendable {
        let resolved = resolve(request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Self.ensureModelAvailable(resolved.model)
                    let stream = resolved.session.streamResponse(
                        to: prompt,
                        generating: type,
                        includeSchemaInPrompt: request.includeSchemaInPrompt,
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

    private func streamGeneratedContent(
        for prompt: String,
        schema: GenerationSchema,
        request: RequestConfig
    ) -> AsyncThrowingStream<GeneratedContent, Error> {
        let resolved = resolve(request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Self.ensureModelAvailable(resolved.model)
                    let stream = resolved.session.streamResponse(
                        to: prompt,
                        schema: schema,
                        includeSchemaInPrompt: request.includeSchemaInPrompt,
                        options: resolved.options
                    )

                    for try await snapshot in stream {
                        if Task.isCancelled { break }
                        continuation.yield(snapshot.rawContent)
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

    private func recoverText(
        from error: Error,
        promptText: String,
        request: RequestConfig,
        resolved: ResolvedRequest,
        includeOptionalTools: Bool,
        retryCount: Int
    ) async throws -> String {
        guard retryCount == 0 else { throw error }

        let action = fallbackAction(for: error, policy: resolved.fallbackPolicy)

        switch action {
        case .fail:
            throw error
        case .fallbackText(let text):
            recordDebug("fallback", "Returned fallback text for \(type(of: error)).", options: resolved.debugOptions)
            return resolved.postProcessing.apply(to: text)
        case .retryWithFreshSession:
            recordDebug("fallback", "Retrying with a fresh session.", options: resolved.debugOptions)
            return try await generateText(
                promptText: promptText,
                request: request,
                forcedSessionPolicy: .freshPerRequest,
                includeOptionalTools: includeOptionalTools,
                retryCount: retryCount + 1
            )
        case .retryWithoutOptionalTools:
            guard includeOptionalTools, !resolved.optionalTools.isEmpty else { throw error }
            recordDebug("fallback", "Retrying without optional tools.", options: resolved.debugOptions)
            return try await generateText(
                promptText: promptText,
                request: request,
                forcedSessionPolicy: .freshPerRequest,
                includeOptionalTools: false,
                retryCount: retryCount + 1
            )
        }
    }

    private func fallbackAction(for error: Error, policy: FallbackPolicy) -> FallbackAction {
        if case .modelUnavailable = error as? SwiftFMError {
            return policy.unavailableModel
        }

        if case .toolCallFailed = error as? SwiftFMError {
            return policy.toolFailure
        }

        guard let generationError = (error as? SwiftFMError)?.generationError else {
            return .fail
        }

        switch generationError {
        case .guardrailViolation:
            return policy.guardrailViolation
        case .exceededContextWindowSize:
            return policy.contextOverflow
        default:
            return .fail
        }
    }

    private func inspectIfNeeded(promptText: String, resolved: ResolvedRequest) async throws {
        guard resolved.debugOptions.isEnabled else { return }

        if #available(iOS 26.4, macOS 26.4, visionOS 26.4, *) {
            let info = try await diagnostics(for: promptText, resolved: resolved)
            var message = "Prompt: \(info.promptCharacterCount) characters"
            if let promptTokenCount = info.promptTokenCount {
                message += ", \(promptTokenCount) tokens of \(info.contextSize)"
            }
            message += ", \(info.toolCount) tools, session: \(info.sessionPolicy)"
            recordDebug("request", message, options: resolved.debugOptions)

            if let ratio = info.contextUsageRatio,
               ratio >= resolved.debugOptions.contextWarningRatio {
                recordDebug("context", "Prompt is using \(Int(ratio * 100))% of the context window.", options: resolved.debugOptions)
            }
        } else {
            recordDebug("request", "Prompt: \(promptText.count) characters, \(resolved.tools.count) tools, session: \(resolved.sessionPolicy)", options: resolved.debugOptions)
        }
    }

    @available(iOS 26.4, macOS 26.4, visionOS 26.4, *)
    private func diagnostics(
        for promptText: String,
        resolved: ResolvedRequest
    ) async throws -> RequestDiagnostics {
        let model = resolved.model.resolvedModel
        let promptTokenCount = try? await model.tokenCount(for: Prompt(promptText))
        return .init(
            promptCharacterCount: promptText.count,
            promptTokenCount: promptTokenCount,
            contextSize: model.contextSize,
            toolCount: resolved.tools.count,
            sessionPolicy: resolved.sessionPolicy
        )
    }

    private func recordDebug(_ category: String, _ message: String, options: DebugOptions) {
        guard options.isEnabled else { return }
        if options.printsToConsole {
            print("[SwiftFM] \(category): \(message)")
        }
        if options.keepsEvents {
            debugEventsStorage.append(.init(category: category, message: message))
            if debugEventsStorage.count > 100 {
                debugEventsStorage.removeFirst(debugEventsStorage.count - 100)
            }
        }
    }

    private func resolve(
        _ request: RequestConfig,
        forcedSessionPolicy: SessionPolicy? = nil,
        includeOptionalTools: Bool = true
    ) -> ResolvedRequest {
        let model = request.model ?? config.model
        let options = Self.makeOptions(
            temperature: request.temperature ?? config.temperature,
            maximumResponseTokens: request.maximumResponseTokens ?? config.maximumResponseTokens,
            sampling: request.sampling ?? config.sampling
        )
        let postProcessing = request.postProcessing ?? config.postProcessing
        let sessionPolicy = forcedSessionPolicy ?? request.sessionPolicy ?? config.sessionPolicy
        let fallbackPolicy = request.fallbackPolicy ?? config.fallbackPolicy
        let debugOptions = request.debugOptions ?? config.debugOptions
        let baseTools = request.tools ?? config.tools
        let optionalTools = includeOptionalTools ? (request.optionalTools ?? config.optionalTools) : []
        let tools = baseTools + optionalTools

        if sessionPolicy.usesSharedSession
            && request.model == nil
            && request.tools == nil
            && request.optionalTools == nil
            && includeOptionalTools {
            return .init(
                model: model,
                options: options,
                session: session,
                postProcessing: postProcessing,
                sessionPolicy: sessionPolicy,
                fallbackPolicy: fallbackPolicy,
                debugOptions: debugOptions,
                tools: tools,
                optionalTools: optionalTools
            )
        }

        let oneShotSession = Self.makeSession(
            model: model,
            tools: tools,
            instructions: config.system
        )

        return .init(
            model: model,
            options: options,
            session: oneShotSession,
            postProcessing: postProcessing,
            sessionPolicy: sessionPolicy,
            fallbackPolicy: fallbackPolicy,
            debugOptions: debugOptions,
            tools: tools,
            optionalTools: optionalTools
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
        let sessionPolicy: SessionPolicy
        let fallbackPolicy: FallbackPolicy
        let debugOptions: DebugOptions
        let tools: [any Tool]
        let optionalTools: [any Tool]
    }
}

/// Tiny Observable runner for SwiftUI and Observation-based apps.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@MainActor
@Observable
public final class SwiftFMRunner<Output: Sendable> {
    public private(set) var isLoading: Bool
    public private(set) var output: Output?
    public private(set) var errorMessage: String?

    public init(
        isLoading: Bool = false,
        output: Output? = nil,
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
        self.output = output
        self.errorMessage = errorMessage
    }

    public func run(_ operation: @Sendable () async throws -> Output) async {
        isLoading = true
        errorMessage = nil

        do {
            output = try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    public func reset() {
        isLoading = false
        output = nil
        errorMessage = nil
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension SwiftFMRunner where Output == String {
    public func runText(
        _ prompt: String,
        using fm: SwiftFM,
        request: SwiftFM.RequestConfig = .init()
    ) async {
        await run {
            try await fm.generateText(for: prompt, request: request)
        }
    }

    public func runText(
        from spec: SwiftFM.PromptSpec,
        using fm: SwiftFM,
        request: SwiftFM.RequestConfig = .init()
    ) async {
        await run {
            try await fm.generateText(from: spec, request: request)
        }
    }
}
