import CryptoKit
import Foundation
import Security

enum SupermemoryConfiguration {
    static let enabledKey = "supermemory.cloudSearchEnabled"
    static let indexingEnabledKey = "supermemory.automaticIndexingEnabled"

    static var supportsSelectedModel: Bool {
        if case .local = LocalLanguageModelStore.currentSelection() {
            return true
        }
        return false
    }

    private static let installationIDKey = "supermemory.installationID"

    static func containerTag(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: installationIDKey),
           let identifier = UUID(uuidString: existing) {
            return formattedContainerTag(identifier)
        }
        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: installationIDKey)
        return formattedContainerTag(identifier)
    }

    static func customID(noteID: UUID, defaults: UserDefaults = .standard) -> String {
        "\(containerTag(defaults: defaults))_\(noteID.uuidString.lowercased())"
    }

    private static func formattedContainerTag(_ identifier: UUID) -> String {
        "burrito_" + identifier.uuidString
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
    }
}

enum SupermemoryClientError: Error, Equatable, Sendable {
    case apiKeyUnavailable
    case downloadedModelRequired
    case invalidAPIKey
    case paymentRequired
    case rateLimited
    case invalidResponse
    case serviceRejected(statusCode: Int)
    case transport(String)
    case keychain(operation: String, status: Int32)
    case cloudDeletionIncomplete(remainingCount: Int)

    var recoveryMessage: String {
        switch self {
        case .apiKeyUnavailable:
            "Add your Supermemory API key in General Settings, then try again. Your meetings remain local."
        case .downloadedModelRequired:
            "Apple Intelligence cannot call the tools Supermemory requires on macOS 26. Download and select a Burrito local model in Models, then connect Supermemory again."
        case .invalidAPIKey:
            "Supermemory rejected this API key. Copy a current key from the Supermemory console and reconnect. Your local meetings are unchanged."
        case .paymentRequired:
            "The Supermemory account has no available credits. Add credits in Supermemory or continue with Burrito’s local meeting search."
        case .rateLimited:
            "Supermemory is temporarily rate limiting requests. Burrito will continue using local meeting search."
        case .invalidResponse:
            "Supermemory returned an unreadable response. Burrito kept the local library intact and will use local meeting search."
        case .serviceRejected(let statusCode):
            "Supermemory rejected the request with status \(statusCode). Burrito kept the local library intact and will use local meeting search."
        case .transport(let details):
            "Burrito could not reach Supermemory: \(details). The local library is intact and local meeting search remains available."
        case .keychain(let operation, let status):
            "Burrito could not \(operation) the Supermemory key in macOS Keychain (status \(status)). No transcript data was changed."
        case .cloudDeletionIncomplete(let remainingCount):
            "Supermemory did not confirm deletion of \(remainingCount) Burrito meeting document(s). The API key remains connected so you can retry; local meetings are unchanged."
        }
    }
}

protocol SupermemoryAPIKeyStoring: Sendable {
    func load() -> Result<String?, SupermemoryClientError>
    func save(_ apiKey: String) -> Result<Void, SupermemoryClientError>
    func remove() -> Result<Void, SupermemoryClientError>
}

struct KeychainSupermemoryAPIKeyStore: SupermemoryAPIKeyStoring {
    private let service = "com.local.burrito.supermemory"
    private let account = "api-key"

    func load() -> Result<String?, SupermemoryClientError> {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return .success(nil)
        }
        guard status == errSecSuccess else {
            return .failure(.keychain(operation: "read", status: status))
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return .failure(.keychain(operation: "decode", status: errSecDecode))
        }
        return .success(value)
    }

    func save(_ apiKey: String) -> Result<Void, SupermemoryClientError> {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = value.data(using: .utf8), !value.isEmpty else {
            return .failure(.apiKeyUnavailable)
        }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                return .failure(.keychain(operation: "update", status: updateStatus))
            }
            return .success(())
        }
        guard status == errSecSuccess else {
            return .failure(.keychain(operation: "save", status: status))
        }
        return .success(())
    }

    func remove() -> Result<Void, SupermemoryClientError> {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return .failure(.keychain(operation: "remove", status: status))
        }
        return .success(())
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

struct SupermemorySearchHit: Equatable, Sendable {
    let text: String
    let documentID: String?
}

struct SupermemoryIndexedDocument: Equatable, Sendable {
    let id: String
    let status: String
}

enum SupermemoryIndexState: String, Codable, Equatable, Sendable {
    case uploading
    case queued
    case processing
    case live
    case failed

    init(apiStatus: String) {
        switch apiStatus.lowercased() {
        case "done", "completed", "complete", "ready", "live": self = .live
        case "processing": self = .processing
        case "failed": self = .failed
        default: self = .queued
        }
    }
}

struct SupermemoryIndexProgress: Equatable, Sendable {
    let noteID: UUID
    let title: String
    let state: SupermemoryIndexState
    let liveCount: Int
    let totalCount: Int
}

struct SupermemoryAPIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://api.supermemory.ai")
            ?? URL(fileURLWithPath: "/"),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func validate(apiKey: String, containerTag: String) async -> Result<Void, SupermemoryClientError> {
        let body = DocumentListRequest(containerTags: [containerTag], limit: 1)
        return await send(
            path: "v3/documents/list",
            method: "POST",
            apiKey: apiKey,
            body: body,
            responseType: EmptyResponse.self
        ).map { _ in () }
    }

    func add(
        document: MemoryDocument,
        apiKey: String,
        containerTag: String,
        customID: String
    ) async -> Result<SupermemoryIndexedDocument, SupermemoryClientError> {
        let body = AddDocumentRequest(
            content: SupermemoryDocumentRenderer.render(document),
            containerTag: containerTag,
            customId: customID,
            metadata: [
                "source": "burrito",
                "type": "meeting-transcript",
                "noteId": document.noteID.uuidString.lowercased(),
                "title": document.title,
                "updatedAt": ISO8601DateFormatter().string(from: document.updatedAt),
            ],
            taskType: "superrag"
        )
        return await send(
            path: "v3/documents",
            method: "POST",
            apiKey: apiKey,
            body: body,
            responseType: AddDocumentResponse.self
        ).map { SupermemoryIndexedDocument(id: $0.id, status: $0.status) }
    }

    func search(
        query: String,
        apiKey: String,
        containerTag: String,
        documentID: String?
    ) async -> Result<[SupermemorySearchHit], SupermemoryClientError> {
        let body = SearchRequest(
            q: query,
            containerTags: [containerTag],
            limit: 10,
            rerank: true,
            rewriteQuery: true,
            searchMode: "documents",
            docId: documentID
        )
        return await send(
            path: "v4/search",
            method: "POST",
            apiKey: apiKey,
            body: body,
            responseType: SearchResponse.self
        ).map { response in
            response.results.compactMap { result in
                guard let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else {
                    return nil
                }
                return SupermemorySearchHit(text: text, documentID: result.documentID)
            }
        }
    }

    func delete(documentID: String, apiKey: String) async -> Result<Void, SupermemoryClientError> {
        await sendWithoutBody(
            path: "v3/documents/\(documentID)",
            method: "DELETE",
            apiKey: apiKey
        )
    }

    func documentStatus(
        documentID: String,
        apiKey: String
    ) async -> Result<SupermemoryIndexState, SupermemoryClientError> {
        await sendWithoutBody(
            path: "v3/documents/\(documentID)",
            method: "GET",
            apiKey: apiKey,
            responseType: DocumentStatusResponse.self
        )
        .map { SupermemoryIndexState(apiStatus: $0.status) }
    }

    private func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        path: String,
        method: String,
        apiKey: String,
        body: Body,
        responseType: Response.Type
    ) async -> Result<Response, SupermemoryClientError> {
        var request = authorizedRequest(path: path, method: method, apiKey: apiKey)
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                return .failure(Self.error(for: httpResponse.statusCode))
            }
            if Response.self == EmptyResponse.self, data.isEmpty {
                guard let empty = EmptyResponse() as? Response else {
                    return .failure(.invalidResponse)
                }
                return .success(empty)
            }
            return .success(try JSONDecoder().decode(responseType, from: data))
        } catch let error as SupermemoryClientError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    private func sendWithoutBody<Response: Decodable & Sendable>(
        path: String,
        method: String,
        apiKey: String,
        responseType: Response.Type
    ) async -> Result<Response, SupermemoryClientError> {
        let request = authorizedRequest(path: path, method: method, apiKey: apiKey)
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                return .failure(Self.error(for: httpResponse.statusCode))
            }
            if Response.self == EmptyResponse.self, data.isEmpty {
                guard let empty = EmptyResponse() as? Response else {
                    return .failure(.invalidResponse)
                }
                return .success(empty)
            }
            return .success(try JSONDecoder().decode(responseType, from: data))
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    private func sendWithoutBody(
        path: String,
        method: String,
        apiKey: String
    ) async -> Result<Void, SupermemoryClientError> {
        let result = await sendWithoutBody(
            path: path,
            method: method,
            apiKey: apiKey,
            responseType: EmptyResponse.self
        )
        switch result {
        case .success:
            return .success(())
        case .failure(let error):
            if method == "DELETE",
               case .serviceRejected(statusCode: 404) = error {
                return .success(())
            } else {
                return .failure(error)
            }
        }
    }

    private func authorizedRequest(path: String, method: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func error(for statusCode: Int) -> SupermemoryClientError {
        switch statusCode {
        case 401, 403: .invalidAPIKey
        case 402: .paymentRequired
        case 429: .rateLimited
        default: .serviceRejected(statusCode: statusCode)
        }
    }
}

private struct EmptyResponse: Decodable, Sendable {
    init() {}

    init(from decoder: any Decoder) throws {
        _ = try? decoder.singleValueContainer()
    }
}

private struct DocumentListRequest: Encodable, Sendable {
    let containerTags: [String]
    let limit: Int
}

private struct AddDocumentRequest: Encodable, Sendable {
    let content: String
    let containerTag: String
    let customId: String
    let metadata: [String: String]
    let taskType: String
}

private struct AddDocumentResponse: Decodable, Sendable {
    let id: String
    let status: String
}

private struct DocumentStatusResponse: Decodable, Sendable {
    let status: String
}

private struct SearchRequest: Encodable, Sendable {
    let q: String
    let containerTags: [String]
    let limit: Int
    let rerank: Bool
    let rewriteQuery: Bool
    let searchMode: String
    let docId: String?
}

private struct SearchResponse: Decodable, Sendable {
    let results: [SearchResult]
}

private struct SearchResult: Decodable, Sendable {
    let text: String?
    let documentID: String?

    enum CodingKeys: String, CodingKey {
        case content
        case chunk
        case memory
        case docId
        case documentId
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        text = try values.decodeIfPresent(String.self, forKey: .content)
            ?? values.decodeIfPresent(String.self, forKey: .chunk)
            ?? values.decodeIfPresent(String.self, forKey: .memory)
        documentID = try values.decodeIfPresent(String.self, forKey: .docId)
            ?? values.decodeIfPresent(String.self, forKey: .documentId)
    }
}

enum SupermemoryDocumentRenderer {
    static func render(_ document: MemoryDocument) -> String {
        """
        # \(document.title)

        Burrito meeting ID: \(document.noteID.uuidString.lowercased())
        Updated: \(ISO8601DateFormatter().string(from: document.updatedAt))

        ## Transcript
        \(Transcript.rendered(document.segments))
        """
    }

    static func digest(_ document: MemoryDocument) -> String {
        let bytes = SHA256.hash(data: Data(render(document).utf8))
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

struct SupermemoryManifest: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let documentID: String
        let digest: String
    }

    var entries: [UUID: Entry] = [:]
}

struct SupermemorySyncReport: Equatable, Sendable {
    var queuedCount = 0
    var unchangedCount = 0
    var liveCount = 0
    var pendingCount = 0
    var failedCount = 0
}

private struct SupermemoryLiveStatusReport: Sendable {
    let report: SupermemorySyncReport
    let failedEntries: [UUID: String]
}

actor SupermemoryCloudMemory {
    static let shared = SupermemoryCloudMemory()

    private let client: SupermemoryAPIClient
    private let keyStore: any SupermemoryAPIKeyStoring
    private let defaults: UserDefaults
    private var disconnecting = false
    private var lifecycleGeneration = 0

    init(
        client: SupermemoryAPIClient = SupermemoryAPIClient(),
        keyStore: any SupermemoryAPIKeyStoring = KeychainSupermemoryAPIKeyStore(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.keyStore = keyStore
        self.defaults = defaults
    }

    func connect(apiKey: String) async -> Result<Void, SupermemoryClientError> {
        guard !disconnecting else { return .failure(.apiKeyUnavailable) }
        let generation = lifecycleGeneration
        guard SupermemoryConfiguration.supportsSelectedModel else {
            return .failure(.downloadedModelRequired)
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(.apiKeyUnavailable) }
        let validation = await client.validate(
            apiKey: key,
            containerTag: SupermemoryConfiguration.containerTag(defaults: defaults)
        )
        guard case .success = validation else { return validation }
        guard isActive(generation) else { return .failure(.apiKeyUnavailable) }
        switch keyStore.save(key) {
        case .success:
            defaults.set(true, forKey: SupermemoryConfiguration.enabledKey)
            defaults.set(false, forKey: SupermemoryConfiguration.indexingEnabledKey)
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    func hasAPIKey() -> Bool {
        guard case .success(let value) = keyStore.load() else { return false }
        return value?.isEmpty == false
    }

    func indexAll(
        _ documents: [MemoryDocument],
        onProgress: @escaping @Sendable (SupermemoryIndexProgress) async -> Void = { _ in }
    ) async -> SupermemorySyncReport {
        guard !disconnecting else { return SupermemorySyncReport() }
        let generation = lifecycleGeneration
        let report = await synchronize(
            documents,
            waitsForLiveStatus: true,
            onProgress: onProgress,
            lifecycleGeneration: generation
        )
        if isActive(generation) {
            defaults.set(true, forKey: SupermemoryConfiguration.indexingEnabledKey)
        }
        return report
    }

    private func synchronize(
        _ documents: [MemoryDocument],
        waitsForLiveStatus: Bool,
        onProgress: @escaping @Sendable (SupermemoryIndexProgress) async -> Void,
        lifecycleGeneration: Int
    ) async -> SupermemorySyncReport {
        guard isActive(lifecycleGeneration), let apiKey = configuredAPIKey() else {
            return SupermemorySyncReport()
        }
        let containerTag = SupermemoryConfiguration.containerTag(defaults: defaults)
        var manifest = loadManifest(apiKey: apiKey)
        var report = SupermemorySyncReport()
        let currentIDs = Set(documents.map(\.noteID))
        let totalCount = documents.count
        var pendingStatusChecks: [(document: MemoryDocument, documentID: String)] = []

        let removedIDs = Array(manifest.entries.keys).filter { !currentIDs.contains($0) }
        for removedID in removedIDs {
            guard isActive(lifecycleGeneration) else { return report }
            guard let entry = manifest.entries[removedID] else { continue }
            if case .success = await client.delete(documentID: entry.documentID, apiKey: apiKey) {
                manifest.entries.removeValue(forKey: removedID)
                saveManifest(manifest, apiKey: apiKey)
            }
        }

        for document in documents {
            guard isActive(lifecycleGeneration) else { return report }
            let digest = SupermemoryDocumentRenderer.digest(document)
            if let entry = manifest.entries[document.noteID], entry.digest == digest {
                report.unchangedCount += 1
                pendingStatusChecks.append((document, entry.documentID))
                continue
            }
            guard isActive(lifecycleGeneration) else { return report }
            await onProgress(SupermemoryIndexProgress(
                noteID: document.noteID,
                title: document.title,
                state: .uploading,
                liveCount: report.liveCount,
                totalCount: totalCount
            ))
            guard isActive(lifecycleGeneration) else { return report }
            let result = await client.add(
                document: document,
                apiKey: apiKey,
                containerTag: containerTag,
                customID: SupermemoryConfiguration.customID(
                    noteID: document.noteID,
                    defaults: defaults
                )
            )
            if !isActive(lifecycleGeneration) || Task.isCancelled {
                if case .success(let indexed) = result {
                    _ = await client.delete(documentID: indexed.id, apiKey: apiKey)
                }
                return report
            }
            guard case .success(let indexed) = result else {
                report.failedCount += 1
                await onProgress(SupermemoryIndexProgress(
                    noteID: document.noteID,
                    title: document.title,
                    state: .failed,
                    liveCount: report.liveCount,
                    totalCount: totalCount
                ))
                continue
            }
            manifest.entries[document.noteID] = SupermemoryManifest.Entry(
                documentID: indexed.id,
                digest: digest
            )
            report.queuedCount += 1
            pendingStatusChecks.append((document, indexed.id))
            guard isActive(lifecycleGeneration) else { return report }
            await onProgress(SupermemoryIndexProgress(
                noteID: document.noteID,
                title: document.title,
                state: SupermemoryIndexState(apiStatus: indexed.status),
                liveCount: report.liveCount,
                totalCount: totalCount
            ))
            guard isActive(lifecycleGeneration) else { return report }
            saveManifest(manifest, apiKey: apiKey)
        }
        if waitsForLiveStatus {
            let statusReport = await waitForLiveStatus(
                pendingStatusChecks,
                apiKey: apiKey,
                totalCount: totalCount,
                onProgress: onProgress,
                lifecycleGeneration: lifecycleGeneration
            )
            report.liveCount += statusReport.report.liveCount
            report.pendingCount += statusReport.report.pendingCount
            report.failedCount += statusReport.report.failedCount
            for (noteID, documentID) in statusReport.failedEntries {
                if manifest.entries[noteID]?.documentID == documentID {
                    manifest.entries.removeValue(forKey: noteID)
                }
            }
            if !statusReport.failedEntries.isEmpty, isActive(lifecycleGeneration) {
                saveManifest(manifest, apiKey: apiKey)
            }
        }
        return report
    }

    private func waitForLiveStatus(
        _ indexedDocuments: [(document: MemoryDocument, documentID: String)],
        apiKey: String,
        totalCount: Int,
        onProgress: @escaping @Sendable (SupermemoryIndexProgress) async -> Void,
        lifecycleGeneration: Int
    ) async -> SupermemoryLiveStatusReport {
        var report = SupermemorySyncReport()
        var pending = indexedDocuments
        var lastStates: [UUID: SupermemoryIndexState] = [:]
        var failedEntries: [UUID: String] = [:]

        for attempt in 0..<60 {
            guard !pending.isEmpty, isActive(lifecycleGeneration), !Task.isCancelled else { break }
            var stillPending: [(document: MemoryDocument, documentID: String)] = []
            for item in pending {
                guard isActive(lifecycleGeneration), !Task.isCancelled else { break }
                let result = await client.documentStatus(
                    documentID: item.documentID,
                    apiKey: apiKey
                )
                guard isActive(lifecycleGeneration), !Task.isCancelled else { break }
                switch result {
                case .success(let state):
                    if lastStates[item.document.noteID] != state || state == .live {
                        await onProgress(SupermemoryIndexProgress(
                            noteID: item.document.noteID,
                            title: item.document.title,
                            state: state,
                            liveCount: report.liveCount + (state == .live ? 1 : 0),
                            totalCount: totalCount
                        ))
                        lastStates[item.document.noteID] = state
                    }
                    switch state {
                    case .live:
                        report.liveCount += 1
                    case .failed:
                        report.failedCount += 1
                        failedEntries[item.document.noteID] = item.documentID
                    case .uploading, .queued, .processing:
                        stillPending.append(item)
                    }
                case .failure:
                    stillPending.append(item)
                }
            }
            pending = stillPending
            if !pending.isEmpty, attempt < 59 {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
            }
        }
        report.pendingCount = pending.count
        return SupermemoryLiveStatusReport(report: report, failedEntries: failedEntries)
    }

    func retrieve(
        query: String,
        documents: [MemoryDocument],
        scopedDocument: MemoryDocument?,
        limit: Int = 6
    ) async -> [MemoryEvidence]? {
        guard limit > 0, let apiKey = configuredAPIKey() else { return nil }
        let manifest = loadManifest(apiKey: apiKey)
        let scopedDocumentID = scopedDocument.flatMap {
            manifest.entries[$0.noteID]?.documentID
        }
        if scopedDocument != nil, scopedDocumentID == nil {
            return nil
        }
        let result = await client.search(
            query: query,
            apiKey: apiKey,
            containerTag: SupermemoryConfiguration.containerTag(defaults: defaults),
            documentID: scopedDocumentID
        )
        guard case .success(let hits) = result else { return nil }
        let evidence = SupermemoryEvidenceMapper.map(
            hits: hits,
            documents: scopedDocument.map { [$0] } ?? documents,
            manifest: manifest,
            limit: limit
        )
        return evidence.isEmpty ? nil : evidence
    }

    func disconnect(deleteRemoteData: Bool) async -> Result<Void, SupermemoryClientError> {
        guard !disconnecting else {
            return .failure(.apiKeyUnavailable)
        }
        lifecycleGeneration += 1
        disconnecting = true
        guard case .success(let storedKey) = keyStore.load() else {
            disconnecting = false
            return .failure(.apiKeyUnavailable)
        }
        if deleteRemoteData, let apiKey = storedKey {
            var manifest = loadManifest(apiKey: apiKey)
            for (noteID, entry) in Array(manifest.entries) {
                let result = await client.delete(documentID: entry.documentID, apiKey: apiKey)
                if case .success = result {
                    manifest.entries.removeValue(forKey: noteID)
                    saveManifest(manifest, apiKey: apiKey)
                }
            }
            guard manifest.entries.isEmpty else {
                disconnecting = false
                return .failure(.cloudDeletionIncomplete(remainingCount: manifest.entries.count))
            }
        }
        switch keyStore.remove() {
        case .success:
            defaults.set(false, forKey: SupermemoryConfiguration.enabledKey)
            defaults.set(false, forKey: SupermemoryConfiguration.indexingEnabledKey)
            disconnecting = false
            return .success(())
        case .failure(let error):
            disconnecting = false
            return .failure(error)
        }
    }

    private func configuredAPIKey() -> String? {
        guard defaults.bool(forKey: SupermemoryConfiguration.enabledKey),
              case .success(let apiKey) = keyStore.load() else {
            return nil
        }
        return apiKey
    }

    private func isActive(_ generation: Int) -> Bool {
        !disconnecting && lifecycleGeneration == generation
    }

    private func manifestKey(apiKey: String) -> String {
        let digest = SHA256.hash(data: Data(apiKey.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        return "supermemory.manifest.\(digest)"
    }

    private func loadManifest(apiKey: String) -> SupermemoryManifest {
        guard let data = defaults.data(forKey: manifestKey(apiKey: apiKey)),
              let manifest = try? JSONDecoder().decode(SupermemoryManifest.self, from: data) else {
            return SupermemoryManifest()
        }
        return manifest
    }

    private func saveManifest(_ manifest: SupermemoryManifest, apiKey: String) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        defaults.set(data, forKey: manifestKey(apiKey: apiKey))
    }
}

enum SupermemoryEvidenceMapper {
    static func map(
        hits: [SupermemorySearchHit],
        documents: [MemoryDocument],
        manifest: SupermemoryManifest,
        limit: Int
    ) -> [MemoryEvidence] {
        guard limit > 0 else { return [] }
        let documentsByID = Dictionary(uniqueKeysWithValues: documents.map { ($0.noteID, $0) })
        let documentIDsByRemoteID = Dictionary(
            uniqueKeysWithValues: manifest.entries.map { ($0.value.documentID, $0.key) }
        )
        let segmentsByID = Dictionary(
            uniqueKeysWithValues: documents.flatMap { document in
                document.segments.map { ($0.id, (document, $0)) }
            }
        )
        var evidence: [MemoryEvidence] = []
        var includedIDs = Set<String>()

        for hit in hits {
            let markerIDs = sourceIDs(in: hit.text)
            for markerID in markerIDs {
                guard let (document, segment) = segmentsByID[markerID] else { continue }
                append(
                    document: document,
                    segment: segment,
                    evidence: &evidence,
                    includedIDs: &includedIDs
                )
                if evidence.count == limit { return evidence }
            }
            if !markerIDs.isEmpty { continue }
            guard let remoteID = hit.documentID,
                  let noteID = documentIDsByRemoteID[remoteID],
                  let document = documentsByID[noteID],
                  let segment = bestContainedSegment(in: hit.text, document: document) else {
                continue
            }
            append(
                document: document,
                segment: segment,
                evidence: &evidence,
                includedIDs: &includedIDs
            )
            if evidence.count == limit { return evidence }
        }
        return evidence
    }

    private static func sourceIDs(in text: String) -> [UUID] {
        guard let expression = try? NSRegularExpression(
            pattern: #"\[source:([0-9A-Fa-f-]{36})\]"#
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: text) else { return nil }
            return UUID(uuidString: String(text[capture]))
        }
    }

    private static func bestContainedSegment(
        in text: String,
        document: MemoryDocument
    ) -> TranscriptSegment? {
        let normalized = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        return document.segments
            .filter { segment in
                let candidate = segment.text.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                return candidate.count >= 12 && normalized.contains(candidate)
            }
            .max { $0.text.count < $1.text.count }
    }

    private static func append(
        document: MemoryDocument,
        segment: TranscriptSegment,
        evidence: inout [MemoryEvidence],
        includedIDs: inout Set<String>
    ) {
        let item = MemoryEvidence(
            noteID: document.noteID,
            noteTitle: document.title,
            noteUpdatedAt: document.updatedAt,
            segment: segment
        )
        guard includedIDs.insert(item.id).inserted else { return }
        evidence.append(item)
    }
}

struct MeetingRetrievalResult: Equatable, Sendable {
    let evidence: [MemoryEvidence]
    let usedSupermemory: Bool
}

enum MeetingMemoryRetriever {
    static func retrieve(
        query: String,
        documents: [MemoryDocument],
        scopedDocument: MemoryDocument?,
        limit: Int = 6,
        useSupermemory: Bool = true
    ) async -> MeetingRetrievalResult {
        if useSupermemory,
           let evidence = await SupermemoryCloudMemory.shared.retrieve(
            query: query,
            documents: documents,
            scopedDocument: scopedDocument,
            limit: limit
        ) {
            return MeetingRetrievalResult(evidence: evidence, usedSupermemory: true)
        }
        let local = scopedDocument.map {
            LocalMemory.retrieve(question: query, scopedTo: $0, limit: limit)
        } ?? LocalMemory.retrieve(question: query, from: documents, limit: limit)
        return MeetingRetrievalResult(evidence: local, usedSupermemory: false)
    }
}
