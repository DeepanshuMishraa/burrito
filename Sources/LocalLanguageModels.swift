import AI
import Foundation
import FoundationModels
import MLXLLM
import MLXLMCommon
import Observation
import Synchronization
import Tokenizers

actor LocalModelInferenceGate {
    struct Lease: Equatable, Sendable {
        fileprivate let id: UUID
    }

    static let shared = LocalModelInferenceGate()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Lease, any Error>
    }

    private var activeLease: Lease?
    private var waiters: [Waiter] = []

    func acquire() async throws -> Lease {
        try Task.checkCancellation()
        if activeLease == nil {
            let lease = Lease(id: UUID())
            activeLease = lease
            return lease
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
    }

    func release(_ lease: Lease) {
        guard activeLease == lease else { return }
        if waiters.isEmpty {
            activeLease = nil
            return
        }
        let waiter = waiters.removeFirst()
        let nextLease = Lease(id: UUID())
        activeLease = nextLease
        waiter.continuation.resume(returning: nextLease)
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

enum LocalLanguageModelState: Equatable {
    case notInstalled
    case paused(progress: Double)
    case downloading(progress: Double)
    case installed
    case failed(message: String)
}

@MainActor
@Observable
final class LocalLanguageModelStore {
    static let shared = LocalLanguageModelStore()

    private(set) var states: [LocalLanguageModelVariant: LocalLanguageModelState] = [:]
    private(set) var selection: GenerationModelSelection
    @ObservationIgnored private var downloads: [LocalLanguageModelVariant: Download] = [:]

    private struct Download {
        let id: UUID
        let task: Task<Void, Never>
    }

    private init() {
        selection = GenerationModelSelection.resolve(
            persistedValue: UserDefaults.standard.string(
                forKey: GenerationModelSelection.storageKey
            ),
            isInstalled: Self.isInstalled
        )
        refresh()
    }

    func refresh() {
        for variant in LocalLanguageModelVariant.allCases {
            guard !isDownloading(variant) else { continue }
            states[variant] = Self.persistedState(for: variant)
        }
        if case .local(let variant) = selection, !Self.isInstalled(variant) {
            select(.apple)
        }
    }

    func state(for variant: LocalLanguageModelVariant) -> LocalLanguageModelState {
        states[variant] ?? Self.persistedState(for: variant)
    }

    func select(_ newSelection: GenerationModelSelection) {
        if case .local(let variant) = newSelection, !Self.isInstalled(variant) {
            return
        }
        selection = newSelection
        UserDefaults.standard.set(
            newSelection.rawValue,
            forKey: GenerationModelSelection.storageKey
        )
        if newSelection == .apple {
            Task { await LocalLanguageModelRuntime.shared.release() }
        }
    }

    func install(_ variant: LocalLanguageModelVariant) async {
        guard downloads[variant] == nil else { return }
        Self.activeInstallationDirectories.withLock {
            _ = $0.insert(variant.modelDirectory)
        }
        let downloadID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performInstall(variant, downloadID: downloadID)
        }
        downloads[variant] = Download(id: downloadID, task: task)
        await task.value
        if downloads[variant]?.id == downloadID {
            downloads[variant] = nil
        }
        Self.activeInstallationDirectories.withLock {
            _ = $0.remove(variant.modelDirectory)
        }
    }

    func cancelInstallation(_ variant: LocalLanguageModelVariant) {
        downloads[variant]?.task.cancel()
    }

    private func performInstall(
        _ variant: LocalLanguageModelVariant,
        downloadID: UUID
    ) async {
        states[variant] = .downloading(progress: 0)
        let configuration = variant.remoteConfiguration
        do {
            try Self.markInstallationStarted(at: variant.modelDirectory)
            _ = try await downloadModel(
                hub: defaultHubApi,
                configuration: configuration
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.downloads[variant]?.id == downloadID,
                          case .downloading = self.states[variant]
                    else {
                        return
                    }
                    self.states[variant] = .downloading(
                        progress: min(1, max(0, progress.fractionCompleted))
                    )
                }
            }
            guard Self.containsRuntimeFiles(at: variant.modelDirectory) else {
                throw LocalLanguageModelError.incompleteDownload(variant.displayName)
            }
            try Self.markInstallationComplete(
                at: variant.modelDirectory,
                revision: variant.revision
            )
            guard Self.isInstalled(variant) else {
                throw LocalLanguageModelError.incompleteDownload(variant.displayName)
            }
            states[variant] = .installed
            select(.local(variant))
        } catch is CancellationError {
            states[variant] = Self.persistedState(for: variant)
        } catch {
            states[variant] = .failed(message: error.localizedDescription)
        }
    }

    nonisolated static func currentSelection() -> GenerationModelSelection {
        GenerationModelSelection.resolve(
            persistedValue: UserDefaults.standard.string(
                forKey: GenerationModelSelection.storageKey
            ),
            isInstalled: isInstalled
        )
    }

    nonisolated static func isInstalled(_ variant: LocalLanguageModelVariant) -> Bool {
        activeInstallationDirectories.withLock { activeDirectories in
            containsInstalledModel(
                at: variant.modelDirectory,
                expectedRevision: variant.revision,
                legacyRevision: variant.markerlessBundleRevision,
                installationInProgress: activeDirectories.contains(variant.modelDirectory)
            )
        }
    }

    nonisolated static func containsInstalledModel(
        at directory: URL,
        expectedRevision: String,
        legacyRevision: String,
        installationInProgress: Bool
    ) -> Bool {
        if containsCompleteModel(at: directory, expectedRevision: expectedRevision) {
            return true
        }
        guard !installationInProgress else { return false }
        try? migrateLegacyInstallation(at: directory, revision: legacyRevision)
        return containsCompleteModel(at: directory, expectedRevision: expectedRevision)
    }

    nonisolated static func containsCompleteModel(
        at directory: URL,
        expectedRevision: String
    ) -> Bool {
        guard let markerData = try? Data(
            contentsOf: directory.appending(path: installationMarkerName)
        ),
        let marker = try? JSONDecoder().decode(InstallationMarker.self, from: markerData),
        marker.revision == expectedRevision
        else {
            return false
        }
        return containsRuntimeFiles(at: directory)
    }

    nonisolated static func markInstallationComplete(
        at directory: URL,
        revision: String
    ) throws {
        let data = try JSONEncoder().encode(InstallationMarker(revision: revision))
        try data.write(
            to: directory.appending(path: installationMarkerName),
            options: .atomic
        )
        try? FileManager.default.removeItem(
            at: directory.appending(path: incompleteInstallationMarkerName)
        )
    }

    nonisolated static func markInstallationStarted(at directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data().write(
            to: directory.appending(path: incompleteInstallationMarkerName),
            options: .atomic
        )
    }

    nonisolated static func migrateLegacyInstallation(
        at directory: URL,
        revision: String
    ) throws {
        guard !FileManager.default.fileExists(
            atPath: directory.appending(path: installationMarkerName).path
        ),
        !FileManager.default.fileExists(
            atPath: directory.appending(path: incompleteInstallationMarkerName).path
        ),
        containsRuntimeFiles(at: directory)
        else {
            return
        }
        try markInstallationComplete(at: directory, revision: revision)
    }

    nonisolated private static func containsRuntimeFiles(at directory: URL) -> Bool {
        guard isNonEmptyFile(directory.appending(path: "config.json")),
              isNonEmptyFile(directory.appending(path: "tokenizer.json")),
              isNonEmptyFile(directory.appending(path: "tokenizer_config.json")),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.fileSizeKey]
              )
        else {
            return false
        }
        let safetensors = files.filter { $0.pathExtension == "safetensors" }
        guard !safetensors.isEmpty else { return false }

        let indexURL = directory.appending(path: "model.safetensors.index.json")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            guard let data = try? Data(contentsOf: indexURL),
                  let index = try? JSONDecoder().decode(SafetensorsIndex.self, from: data)
            else {
                return false
            }
            let expectedShards = Set(index.weightMap.values)
            guard !expectedShards.isEmpty else { return false }
            return expectedShards.allSatisfy { shard in
                isNonEmptyFile(directory.appending(path: shard))
            }
        }

        guard safetensors.allSatisfy({ !$0.lastPathComponent.contains("-of-") }) else {
            return false
        }
        return safetensors.allSatisfy(isNonEmptyFile)
    }

    nonisolated private static func isNonEmptyFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        else {
            return false
        }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }

    nonisolated private static func persistedState(
        for variant: LocalLanguageModelVariant
    ) -> LocalLanguageModelState {
        if isInstalled(variant) { return .installed }
        let progress = cachedDownloadFraction(for: variant)
        return progress > 0 ? .paused(progress: progress) : .notInstalled
    }

    nonisolated private static func cachedDownloadFraction(
        for variant: LocalLanguageModelVariant
    ) -> Double {
        guard let enumerator = FileManager.default.enumerator(
            at: variant.modelDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var bytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ),
            values.isRegularFile == true,
            let fileSize = values.fileSize
            else {
                continue
            }
            bytes += Int64(fileSize)
        }
        return min(0.99, max(0, Double(bytes) / Double(variant.downloadSizeBytes)))
    }

    private func isDownloading(_ variant: LocalLanguageModelVariant) -> Bool {
        guard case .downloading = states[variant] else { return false }
        return true
    }

    private struct SafetensorsIndex: Decodable {
        let weightMap: [String: String]

        private enum CodingKeys: String, CodingKey {
            case weightMap = "weight_map"
        }
    }

    private struct InstallationMarker: Codable {
        let revision: String
    }

    private nonisolated static let installationMarkerName = ".burrito-installation.json"
    private nonisolated static let incompleteInstallationMarkerName =
        ".burrito-installation-incomplete"
    private nonisolated static let activeInstallationDirectories = Mutex<Set<URL>>([])
}

extension LocalLanguageModelVariant {
    fileprivate var remoteConfiguration: ModelConfiguration {
        ModelConfiguration(id: repositoryID, revision: revision)
    }

    fileprivate var modelDirectory: URL {
        remoteConfiguration.modelDirectory(hub: defaultHubApi)
    }

    // Markerless bundles predate revision tracking. Keep these pins separate so a
    // future model update cannot certify old files as the new revision.
    fileprivate var markerlessBundleRevision: String {
        switch self {
        case .small: "674aaa7240b91e8012fcad5d791b7dfe5ba90207"
        case .medium: "0e7ffd5c629ef7719d4cbc04069232580bfa9d9c"
        case .large: "8b2b98c00a6b4d291155e4890773ca8f769aee53"
        }
    }
}

enum LocalLanguageModelError: LocalizedError {
    case incompleteDownload(String)
    case unsupportedContent

    var errorDescription: String? {
        switch self {
        case .incompleteDownload(let name):
            "The download for \(name) did not contain all required model files. Retry the download."
        case .unsupportedContent:
            "This local model supports text and tool messages only. Remove image or file input and try again."
        }
    }
}

actor LocalLanguageModelRuntime {
    static let shared = LocalLanguageModelRuntime()
    // Keep prompt prefill bounded. Large Qwen prefill graphs can retain several
    // gigabytes of Metal buffers even though the model itself is only 4-bit.
    static let contextSize = 4_096
    private static let prefillStepSize = 64

    private var loadedVariant: LocalLanguageModelVariant?
    private var container: ModelContainer?
    private var idleReleaseTask: Task<Void, Never>?

    func release() {
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
        container = nil
        loadedVariant = nil
    }

    func tokenCount(_ text: String, using variant: LocalLanguageModelVariant) async throws -> Int {
        let lease = try await LocalModelInferenceGate.shared.acquire()
        do {
            try Task.checkCancellation()
            await ParakeetTranscriber.shared.release()
            let container = try await container(for: variant)
            let count = await container.encode(text).count
            scheduleIdleRelease()
            await LocalModelInferenceGate.shared.release(lease)
            return count
        } catch {
            await LocalModelInferenceGate.shared.release(lease)
            throw error
        }
    }

    func generate(
        request: LanguageModelRequest,
        using variant: LocalLanguageModelVariant
    ) async throws -> AsyncStream<Generation> {
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
        let container = try await container(for: variant)
        let input = try await container.prepare(
            input: try MLXRequestMapper.input(from: request)
        )
        let parameters = GenerateParameters(
            maxTokens: request.maxOutputTokens,
            maxKVSize: Self.contextSize,
            kvBits: 8,
            temperature: Float(request.temperature ?? 0.6),
            topP: Float(request.topP ?? 1),
            topK: request.topK ?? 0,
            presencePenalty: request.presencePenalty.map(Float.init),
            frequencyPenalty: request.frequencyPenalty.map(Float.init),
            prefillStepSize: Self.prefillStepSize
        )
        return try await container.generate(input: input, parameters: parameters)
    }

    private func container(
        for variant: LocalLanguageModelVariant
    ) async throws -> ModelContainer {
        if let container, loadedVariant == variant { return container }
        guard LocalLanguageModelStore.isInstalled(variant) else {
            throw LocalLanguageModelError.incompleteDownload(variant.displayName)
        }
        container = nil
        loadedVariant = nil
        let loaded = try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(directory: variant.modelDirectory)
        )
        container = loaded
        loadedVariant = variant
        return loaded
    }

    private func scheduleIdleRelease() {
        idleReleaseTask?.cancel()
        idleReleaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.release()
        }
    }
}

struct MLXLanguageModel: AI.LanguageModel {
    let variant: LocalLanguageModelVariant
    let runtime: LocalLanguageModelRuntime

    init(
        variant: LocalLanguageModelVariant,
        runtime: LocalLanguageModelRuntime = .shared
    ) {
        self.variant = variant
        self.runtime = runtime
    }

    var provider: String { "mlx" }
    var modelID: String { variant.repositoryID }

    func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let lease = try await LocalModelInferenceGate.shared.acquire()
                    do {
                        try Task.checkCancellation()
                        await ParakeetTranscriber.shared.release()
                        let generations = try await runtime.generate(
                            request: request,
                            using: variant
                        )
                        var emittedToolCall = false
                        for await generation in generations {
                            switch generation {
                            case .chunk(let text):
                                continuation.yield(.textDelta(text))
                            case .toolCall(let toolCall):
                                emittedToolCall = true
                                continuation.yield(
                                    .toolCall(
                                        AI.ToolCall(
                                            id: UUID().uuidString,
                                            name: toolCall.function.name,
                                            arguments: try MLXRequestMapper.aiJSON(
                                                from: toolCall.function.arguments
                                            )
                                        )
                                    )
                                )
                            case .info(let info):
                                let reason: FinishReason
                                if emittedToolCall {
                                    reason = .toolCalls
                                } else {
                                    reason = switch info.stopReason {
                                    case .stop: .stop
                                    case .length: .length
                                    case .cancelled: .error
                                    }
                                }
                                continuation.yield(
                                    .finish(
                                        reason: reason,
                                        usage: Usage(
                                            inputTokens: info.promptTokenCount,
                                            outputTokens: info.generationTokenCount
                                        )
                                    )
                                )
                            }
                        }
                        await runtime.release()
                        await LocalModelInferenceGate.shared.release(lease)
                        continuation.finish()
                    } catch {
                        await runtime.release()
                        await LocalModelInferenceGate.shared.release(lease)
                        throw error
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum MLXRequestMapper {
    static func input(from request: LanguageModelRequest) throws -> UserInput {
        UserInput(
            messages: try request.messages.flatMap(rawMessages),
            tools: toolSpecs(from: request),
            additionalContext: ["enable_thinking": false]
        )
    }

    static func aiJSON(
        from value: [String: MLXLMCommon.JSONValue]
    ) throws -> AI.JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(AI.JSONValue.self, from: data)
    }

    private static func rawMessages(from message: AI.Message) throws -> [MLXLMCommon.Message] {
        let text = message.content.compactMap { part -> String? in
            guard case .text(let value) = part else { return nil }
            return value
        }.joined()
        let toolCalls = message.content.compactMap { part -> AI.ToolCall? in
            guard case .toolCall(let value) = part else { return nil }
            return value
        }
        let toolResults = message.content.compactMap { part -> AI.ToolResult? in
            guard case .toolResult(let value) = part else { return nil }
            return value
        }
        let containsUnsupportedContent = message.content.contains { part in
            switch part {
            case .image, .file, .toolApprovalResponse: true
            case .text, .toolCall, .toolResult: false
            }
        }
        guard !containsUnsupportedContent else {
            throw LocalLanguageModelError.unsupportedContent
        }

        if message.role == .tool || !toolResults.isEmpty {
            return try toolResults.map { result in
                [
                    "role": "tool",
                    "content": try jsonString(result.output),
                ] as MLXLMCommon.Message
            }
        }

        var raw: MLXLMCommon.Message = [
            "role": message.role.rawValue,
            "content": text,
        ]
        if !toolCalls.isEmpty {
            raw["tool_calls"] = try toolCalls.map { call in
                [
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": sendableJSON(call.arguments),
                    ] as [String: any Sendable],
                ] as [String: any Sendable]
            }
        }
        return [raw]
    }

    private static func toolSpecs(
        from request: LanguageModelRequest
    ) -> [ToolSpec]? {
        let tools: [any AIToolProtocol]
        switch request.toolChoice {
        case .none:
            tools = []
        case .tool(let name):
            tools = request.tools.filter { $0.name == name }
        case .auto, .required:
            tools = request.tools
        }
        guard !tools.isEmpty else { return nil }
        return tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": sendableJSON(tool.parameters),
                ] as [String: any Sendable],
            ] as ToolSpec
        }
    }

    private static func jsonString(_ value: AI.JSONValue) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return string
    }

    private static func sendableJSON(_ value: AI.JSONValue) -> any Sendable {
        switch value {
        case .null: NSNull()
        case .bool(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(sendableJSON)
        case .object(let values): values.mapValues(sendableJSON)
        }
    }
}

actor SelectedLanguageModelAdapter {
    static let shared = SelectedLanguageModelAdapter()

    func resolve(languageIdentifier: String) async -> Result<FoundationModelAdapter, BurritoError> {
        switch LocalLanguageModelStore.currentSelection() {
        case .apple:
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                guard model.supportsLocale(Locale(identifier: languageIdentifier)) else {
                    return .failure(
                        .appleIntelligenceUnavailable(
                            reason: "The selected language is not supported by the on-device model."
                        )
                    )
                }
                return .success(FoundationModelAdapter())
            case .unavailable(let reason):
                let message = switch reason {
                case .deviceNotEligible: "this Mac is not eligible"
                case .appleIntelligenceNotEnabled: "Apple Intelligence is disabled"
                case .modelNotReady: "the on-device model is not ready"
                @unknown default: "the on-device model reported an unknown availability state"
                }
                return .failure(
                    .appleIntelligenceUnavailable(reason: message)
                )
            }
        case .local(let variant):
            return .success(
                FoundationModelAdapter(
                    model: MLXLanguageModel(variant: variant),
                    tokenMeasurer: MLXTokenMeasurer(variant: variant)
                )
            )
        }
    }
}

struct MLXTokenMeasurer: PromptTokenMeasuring {
    let variant: LocalLanguageModelVariant
    let runtime: LocalLanguageModelRuntime

    init(
        variant: LocalLanguageModelVariant,
        runtime: LocalLanguageModelRuntime = .shared
    ) {
        self.variant = variant
        self.runtime = runtime
    }

    var contextSize: Int { get async { LocalLanguageModelRuntime.contextSize } }

    func tokenCount(_ text: String) async throws -> Int {
        try await runtime.tokenCount(text, using: variant)
    }
}
