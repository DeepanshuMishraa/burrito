import Foundation
import SwiftData

struct BurritoArchive: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let formatIdentifier = "app.burrito.archive"

    let format: String
    let version: Int
    let exportedAt: Date
    var notes: [NoteRecord]
    let folders: [FolderRecord]
    let templates: [TemplateRecord]

    struct FolderRecord: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let order: Int
    }

    struct TemplateRecord: Codable, Equatable, Sendable {
        let id: UUID
        let builtInID: String?
        let name: String
        let symbol: String
        let instructions: String
        let createdAt: Date
    }

    struct NoteRecord: Codable, Equatable, Sendable {
        let id: UUID
        let lifecycleRawValue: String
        let processingStageRawValue: String?
        let title: String
        let markdownBody: String
        let userNotes: String
        let transcriptSegments: [TranscriptSegment]
        let createdAt: Date
        let updatedAt: Date
        let recordingStartedAt: Date?
        let duration: TimeInterval
        let languageIdentifier: String
        let templateName: String
        let templateSymbol: String
        let templateInstructions: String
        let isFavorite: Bool
        let deletedAt: Date?
        let recordingModeRawValue: String?
        let retainsAudio: Bool
        let transcriptRevision: Int
        let generatedFromTranscriptRevision: Int
        let userEditedNotes: Bool
        let lastErrorMessage: String?
        let calendarEvent: CalendarEventSnapshot?
        let folderID: UUID?
        var systemAudioArchivePath: String?
        var microphoneAudioArchivePath: String?
    }

    static func capture(
        notes: [Note],
        folders: [Folder],
        templates: [NoteTemplate],
        exportedAt: Date = .now
    ) -> BurritoArchive {
        BurritoArchive(
            format: formatIdentifier,
            version: currentVersion,
            exportedAt: exportedAt,
            notes: notes.map { note in
                NoteRecord(
                    id: note.id,
                    lifecycleRawValue: note.lifecycleRawValue,
                    processingStageRawValue: note.processingStageRawValue,
                    title: note.title,
                    markdownBody: note.markdownBody,
                    userNotes: note.userNotes,
                    transcriptSegments: note.transcriptSegments,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt,
                    recordingStartedAt: note.recordingStartedAt,
                    duration: note.duration,
                    languageIdentifier: note.languageIdentifier,
                    templateName: note.templateName,
                    templateSymbol: note.templateSymbol,
                    templateInstructions: note.templateInstructions,
                    isFavorite: note.isFavorite,
                    deletedAt: note.deletedAt,
                    recordingModeRawValue: note.recordingModeRawValue,
                    retainsAudio: note.retainsAudio,
                    transcriptRevision: note.transcriptRevision,
                    generatedFromTranscriptRevision: note.generatedFromTranscriptRevision,
                    userEditedNotes: note.userEditedNotes,
                    lastErrorMessage: note.lastErrorMessage,
                    calendarEvent: note.calendarEvent,
                    folderID: note.folder?.id,
                    systemAudioArchivePath: nil,
                    microphoneAudioArchivePath: nil
                )
            },
            folders: folders.map {
                FolderRecord(id: $0.id, name: $0.name, order: $0.order)
            },
            templates: templates.map {
                TemplateRecord(
                    id: $0.id,
                    builtInID: $0.builtInID,
                    name: $0.name,
                    symbol: $0.symbol,
                    instructions: $0.instructions,
                    createdAt: $0.createdAt
                )
            }
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> BurritoArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive: BurritoArchive
        do {
            archive = try decoder.decode(BurritoArchive.self, from: data)
        } catch {
            throw BurritoArchiveError.invalidArchive(details: error.localizedDescription)
        }
        guard archive.format == formatIdentifier else {
            throw BurritoArchiveError.invalidArchive(
                details: "The selected file is not a Burrito archive."
            )
        }
        guard archive.version == currentVersion else {
            throw BurritoArchiveError.unsupportedVersion(
                found: archive.version,
                supported: currentVersion
            )
        }
        return archive
    }
}

struct ArchiveRestoreReport: Equatable, Sendable {
    let notesInserted: Int
    let foldersInserted: Int
    let templatesInserted: Int
    let duplicatesSkipped: Int
}

struct ArchiveExportReport: Equatable, Sendable {
    let destination: URL
    let notesExported: Int
    let audioFilesExported: Int
    let markdownFiles: [URL]
}

struct ArchivePackageRestoreReport: Equatable, Sendable {
    let notesInserted: Int
    let foldersInserted: Int
    let templatesInserted: Int
    let duplicatesSkipped: Int
    let audioFilesRestored: Int
}

struct ArchiveExportInput: Sendable {
    struct NoteFile: Sendable {
        let id: UUID
        let title: String
        let markdown: String
        let systemAudioSource: URL?
        let microphoneAudioSource: URL?
    }

    var archive: BurritoArchive
    let noteFiles: [NoteFile]
}

struct RestoredAudioPaths: Sendable {
    let system: String?
    let microphone: String?
}

private struct ValidatedArchiveAudio: Sendable {
    let system: URL?
    let microphone: URL?
}

private struct LoadedArchivePackage: Sendable {
    let directory: URL
    let archive: BurritoArchive
}

private struct RestoredArchiveFiles: Sendable {
    let audioPaths: [UUID: RestoredAudioPaths]
    let createdFiles: [URL]
    let createdDirectories: [URL]
    let count: Int
}

enum BurritoArchivePackage {
    static let manifestFilename = "burrito.json"

    static func prepareExport(
        notes: [Note],
        folders: [Folder],
        templates: [NoteTemplate],
        recordingStore: LocalRecordingFileStore
    ) -> ArchiveExportInput {
        ArchiveExportInput(
            archive: BurritoArchive.capture(
                notes: notes,
                folders: folders,
                templates: templates
            ),
            noteFiles: notes.map { note in
                ArchiveExportInput.NoteFile(
                    id: note.id,
                    title: note.title,
                    markdown: markdown(for: note),
                    systemAudioSource: note.systemAudioRelativePath.map(
                        recordingStore.url(forRelativePath:)
                    ),
                    microphoneAudioSource: note.microphoneAudioRelativePath.map(
                        recordingStore.url(forRelativePath:)
                    )
                )
            }
        )
    }

    static func export(
        notes: [Note],
        folders: [Folder],
        templates: [NoteTemplate],
        recordingStore: LocalRecordingFileStore,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws -> ArchiveExportReport {
        try export(
            prepareExport(
                notes: notes,
                folders: folders,
                templates: templates,
                recordingStore: recordingStore
            ),
            to: destination,
            fileManager: fileManager
        )
    }

    static func export(
        _ input: ArchiveExportInput,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws -> ArchiveExportReport {
        guard !fileManager.fileExists(atPath: destination.path()) else {
            throw BurritoArchiveError.fileOperationFailed(
                operation: "create the backup",
                details: "A file or folder already exists at \(destination.path()). Choose another location."
            )
        }

        var createdDestination = false
        do {
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            createdDestination = true
            let notesDirectory = destination.appending(path: "Notes", directoryHint: .isDirectory)
            let audioDirectory = destination.appending(path: "Audio", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)

            var archive = input.archive
            var markdownFiles: [URL] = []
            var audioFilesExported = 0

            for (index, note) in input.noteFiles.enumerated() {
                let markdownURL = notesDirectory.appending(
                    path: "\(safeFilename(note.title))--\(note.id.uuidString).md"
                )
                try note.markdown.write(
                    to: markdownURL,
                    atomically: true,
                    encoding: .utf8
                )
                markdownFiles.append(markdownURL)

                let noteAudioDirectory = audioDirectory.appending(
                    path: note.id.uuidString,
                    directoryHint: .isDirectory
                )
                let systemArchivePath = try copyAudio(
                    source: note.systemAudioSource,
                    filename: "system.m4a",
                    noteAudioDirectory: noteAudioDirectory,
                    fileManager: fileManager
                )
                let microphoneArchivePath = try copyAudio(
                    source: note.microphoneAudioSource,
                    filename: "microphone.m4a",
                    noteAudioDirectory: noteAudioDirectory,
                    fileManager: fileManager
                )
                archive.notes[index].systemAudioArchivePath = systemArchivePath
                archive.notes[index].microphoneAudioArchivePath = microphoneArchivePath
                audioFilesExported += [systemArchivePath, microphoneArchivePath]
                    .compactMap { $0 }
                    .count
            }

            try archive.encoded().write(
                to: destination.appending(path: manifestFilename),
                options: .atomic
            )
            try readme(for: archive).write(
                to: destination.appending(path: "README.md"),
                atomically: true,
                encoding: .utf8
            )

            return ArchiveExportReport(
                destination: destination,
                notesExported: input.noteFiles.count,
                audioFilesExported: audioFilesExported,
                markdownFiles: markdownFiles
            )
        } catch {
            if createdDestination {
                try? fileManager.removeItem(at: destination)
            }
            if let archiveError = error as? BurritoArchiveError {
                throw archiveError
            }
            throw BurritoArchiveError.fileOperationFailed(
                operation: "create the backup",
                details: error.localizedDescription
            )
        }
    }

    static func export(
        _ input: ArchiveExportInput,
        to destination: URL
    ) async throws -> ArchiveExportReport {
        try await Task.detached(priority: .userInitiated) {
            try export(input, to: destination, fileManager: .default)
        }
        .value
    }

    @MainActor
    static func restore(
        from selectedURL: URL,
        into context: ModelContext,
        recordingStore: LocalRecordingFileStore,
        fileManager: FileManager = .default
    ) throws -> ArchivePackageRestoreReport {
        let package = try loadPackage(from: selectedURL, fileManager: fileManager)
        let existingNoteIDs = Set(
            try context.fetch(FetchDescriptor<Note>()).map(\.id)
        )
        let restoredFiles = try restoreFiles(
            for: package,
            excluding: existingNoteIDs,
            recordingStore: recordingStore,
            fileManager: fileManager
        )
        do {
            let report = try package.archive.restore(
                into: context,
                audioPaths: restoredFiles.audioPaths
            )
            return packageReport(from: report, restoredFiles: restoredFiles)
        } catch {
            cleanup(restoredFiles, fileManager: fileManager)
            throw restoreError(error)
        }
    }

    @MainActor
    static func restore(
        from selectedURL: URL,
        into context: ModelContext,
        recordingStore: LocalRecordingFileStore
    ) async throws -> ArchivePackageRestoreReport {
        let package = try await Task.detached(priority: .userInitiated) {
            try loadPackage(from: selectedURL, fileManager: .default)
        }
        .value
        let existingNoteIDs = Set(
            try context.fetch(FetchDescriptor<Note>()).map(\.id)
        )
        let restoredFiles = try await Task.detached(priority: .userInitiated) {
            try restoreFiles(
                for: package,
                excluding: existingNoteIDs,
                recordingStore: recordingStore,
                fileManager: .default
            )
        }
        .value

        do {
            let report = try package.archive.restore(
                into: context,
                audioPaths: restoredFiles.audioPaths
            )
            return packageReport(from: report, restoredFiles: restoredFiles)
        } catch {
            await Task.detached(priority: .utility) {
                cleanup(restoredFiles, fileManager: .default)
            }
            .value
            throw restoreError(error)
        }
    }

    private static func loadPackage(
        from selectedURL: URL,
        fileManager: FileManager
    ) throws -> LoadedArchivePackage {
        let packageDirectory: URL
        let manifestURL: URL
        if selectedURL.lastPathComponent == manifestFilename {
            manifestURL = selectedURL
            packageDirectory = selectedURL.deletingLastPathComponent()
        } else {
            packageDirectory = selectedURL
            manifestURL = selectedURL.appending(path: manifestFilename)
        }

        do {
            return LoadedArchivePackage(
                directory: packageDirectory,
                archive: try BurritoArchive.decode(Data(contentsOf: manifestURL))
            )
        } catch let error as BurritoArchiveError {
            throw error
        } catch {
            throw BurritoArchiveError.fileOperationFailed(
                operation: "read the backup",
                details: "\(error.localizedDescription) Existing notes were not changed."
            )
        }
    }

    private static func restoreFiles(
        for package: LoadedArchivePackage,
        excluding existingNoteIDs: Set<UUID>,
        recordingStore: LocalRecordingFileStore,
        fileManager: FileManager
    ) throws -> RestoredArchiveFiles {
        let missingRecords = package.archive.notes.filter { !existingNoteIDs.contains($0.id) }
        var validatedAudio: [UUID: ValidatedArchiveAudio] = [:]
        var restoredPaths: [UUID: RestoredAudioPaths] = [:]
        var createdAudioFiles: [URL] = []
        var createdDirectories: [URL] = []
        var audioFilesRestored = 0

        do {
            for record in missingRecords {
                let mode = record.recordingModeRawValue
                    .flatMap(RecordingMode.init(rawValue:)) ?? .listenAlong
                if record.microphoneAudioArchivePath != nil, mode != .meeting {
                    throw BurritoArchiveError.invalidArchive(
                        details: "A microphone recording is attached to a non-meeting note. Existing notes were not changed."
                    )
                }
                validatedAudio[record.id] = ValidatedArchiveAudio(
                    system: try validatedAudioURL(
                        archivePath: record.systemAudioArchivePath,
                        packageDirectory: package.directory,
                        fileManager: fileManager
                    ),
                    microphone: try validatedAudioURL(
                        archivePath: record.microphoneAudioArchivePath,
                        packageDirectory: package.directory,
                        fileManager: fileManager
                    )
                )
            }

            for record in missingRecords {
                guard record.systemAudioArchivePath != nil
                        || record.microphoneAudioArchivePath != nil else {
                    continue
                }
                let mode = record.recordingModeRawValue
                    .flatMap(RecordingMode.init(rawValue:)) ?? .listenAlong
                let sessionDirectory = recordingStore.url(
                    forRelativePath: record.id.uuidString
                )
                let sessionDirectoryExisted = fileManager.fileExists(
                    atPath: sessionDirectory.path()
                )
                let files = try recordingStore.createSession(id: record.id, mode: mode).get()
                if !sessionDirectoryExisted {
                    createdDirectories.append(sessionDirectory)
                }
                let systemPath = try restoreAudio(
                    source: validatedAudio[record.id]?.system,
                    destination: files.systemAudioURL,
                    recordingStore: recordingStore,
                    fileManager: fileManager
                )
                if systemPath != nil, let systemURL = files.systemAudioURL {
                    createdAudioFiles.append(systemURL)
                }
                let microphonePath = try restoreAudio(
                    source: validatedAudio[record.id]?.microphone,
                    destination: files.microphoneAudioURL,
                    recordingStore: recordingStore,
                    fileManager: fileManager
                )
                if microphonePath != nil, let microphoneURL = files.microphoneAudioURL {
                    createdAudioFiles.append(microphoneURL)
                }
                restoredPaths[record.id] = RestoredAudioPaths(
                    system: systemPath,
                    microphone: microphonePath
                )
                audioFilesRestored += [systemPath, microphonePath].compactMap { $0 }.count
            }

            return RestoredArchiveFiles(
                audioPaths: restoredPaths,
                createdFiles: createdAudioFiles,
                createdDirectories: createdDirectories,
                count: audioFilesRestored
            )
        } catch {
            cleanup(
                RestoredArchiveFiles(
                    audioPaths: restoredPaths,
                    createdFiles: createdAudioFiles,
                    createdDirectories: createdDirectories,
                    count: audioFilesRestored
                ),
                fileManager: fileManager
            )
            throw restoreError(error)
        }
    }

    private static func cleanup(
        _ restoredFiles: RestoredArchiveFiles,
        fileManager: FileManager
    ) {
        for url in restoredFiles.createdFiles {
            try? fileManager.removeItem(at: url)
        }
        for directory in restoredFiles.createdDirectories.reversed() {
            let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            if contents?.isEmpty == true {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    private static func packageReport(
        from report: ArchiveRestoreReport,
        restoredFiles: RestoredArchiveFiles
    ) -> ArchivePackageRestoreReport {
        ArchivePackageRestoreReport(
            notesInserted: report.notesInserted,
            foldersInserted: report.foldersInserted,
            templatesInserted: report.templatesInserted,
            duplicatesSkipped: report.duplicatesSkipped,
            audioFilesRestored: restoredFiles.count
        )
    }

    private static func restoreError(_ error: Error) -> BurritoArchiveError {
        if let archiveError = error as? BurritoArchiveError {
            return archiveError
        }
        return BurritoArchiveError.fileOperationFailed(
            operation: "restore the backup",
            details: "\(error.localizedDescription) Existing notes were not changed."
        )
    }

    private static func copyAudio(
        source: URL?,
        filename: String,
        noteAudioDirectory: URL,
        fileManager: FileManager
    ) throws -> String? {
        guard let source else { return nil }
        guard fileManager.fileExists(atPath: source.path()) else {
            throw BurritoArchiveError.fileOperationFailed(
                operation: "create the backup",
                details: "The retained recording \(source.lastPathComponent) is missing. Your existing library was not changed."
            )
        }
        try fileManager.createDirectory(at: noteAudioDirectory, withIntermediateDirectories: true)
        let target = noteAudioDirectory.appending(path: filename)
        try fileManager.copyItem(at: source, to: target)
        return "Audio/\(noteAudioDirectory.lastPathComponent)/\(filename)"
    }

    private static func validatedAudioURL(
        archivePath: String?,
        packageDirectory: URL,
        fileManager: FileManager
    ) throws -> URL? {
        guard let archivePath else { return nil }
        var packagePath = packageDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path()
        while packagePath.count > 1, packagePath.hasSuffix("/") {
            packagePath.removeLast()
        }
        let source = packageDirectory
            .appending(path: archivePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard source.path().hasPrefix(packagePath + "/") else {
            throw BurritoArchiveError.invalidArchive(
                details: "An audio path points outside the backup folder. Existing notes were not changed."
            )
        }
        guard fileManager.fileExists(atPath: source.path()) else {
            throw BurritoArchiveError.invalidArchive(
                details: "The backup references missing audio at \(archivePath). Existing notes were not changed."
            )
        }
        return source
    }

    private static func restoreAudio(
        source: URL?,
        destination: URL?,
        recordingStore: LocalRecordingFileStore,
        fileManager: FileManager
    ) throws -> String? {
        guard let source else { return nil }
        guard let destination else {
            throw BurritoArchiveError.invalidArchive(
                details: "The backup contains audio for a track this note cannot restore. Existing notes were not changed."
            )
        }
        try fileManager.copyItem(at: source, to: destination)
        return recordingStore.relativePath(for: destination)
    }

    private static func safeFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.controlCharacters)
        let components = title.components(separatedBy: invalid)
        let cleaned = components
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(100))
    }

    private static func markdown(for note: Note) -> String {
        var sections = [
            "# \(note.title)",
            note.exportedMarkdown,
        ]
        if !note.transcriptSegments.isEmpty {
            let transcript = note.transcriptSegments.map { segment in
                let speaker = segment.speakerName
                    ?? (segment.source == .microphone ? "Microphone" : "System audio")
                return "\(speaker): \(segment.text)"
            }
            .joined(separator: "\n\n")
            sections.append("## Transcript\n\n\(transcript)")
        }
        return sections
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
            + "\n"
    }

    private static func readme(for archive: BurritoArchive) -> String {
        """
        # Burrito backup

        This folder is an open, portable export of a Burrito library.

        - `burrito.json` is the complete machine-readable archive.
        - `Notes/` contains human-readable Markdown.
        - `Audio/` contains retained recordings referenced by the archive.

        Archive format: `\(archive.format)` version \(archive.version).
        Exported notes: \(archive.notes.count).
        """
    }
}

extension BurritoArchive {
    @MainActor
    func restore(
        into context: ModelContext,
        audioPaths: [UUID: RestoredAudioPaths] = [:]
    ) throws -> ArchiveRestoreReport {
        let existingFolders = try context.fetch(FetchDescriptor<Folder>())
        let existingTemplates = try context.fetch(FetchDescriptor<NoteTemplate>())
        let existingNotes = try context.fetch(FetchDescriptor<Note>())
        var foldersByID = Dictionary(uniqueKeysWithValues: existingFolders.map { ($0.id, $0) })
        var existingTemplateIDs = Set(existingTemplates.map(\.id))
        var existingBuiltInIDs = Set(existingTemplates.compactMap(\.builtInID))
        var existingNoteIDs = Set(existingNotes.map(\.id))
        var foldersInserted = 0
        var templatesInserted = 0
        var notesInserted = 0
        var duplicatesSkipped = 0

        for record in folders {
            guard foldersByID[record.id] == nil else {
                duplicatesSkipped += 1
                continue
            }
            let folder = Folder(id: record.id, name: record.name, order: record.order)
            context.insert(folder)
            foldersByID[record.id] = folder
            foldersInserted += 1
        }

        for record in templates {
            let duplicatesBuiltIn = record.builtInID.map(existingBuiltInIDs.contains) ?? false
            guard !existingTemplateIDs.contains(record.id), !duplicatesBuiltIn else {
                duplicatesSkipped += 1
                continue
            }
            context.insert(
                NoteTemplate(
                    id: record.id,
                    builtInID: record.builtInID,
                    name: record.name,
                    symbol: record.symbol,
                    instructions: record.instructions,
                    createdAt: record.createdAt
                )
            )
            existingTemplateIDs.insert(record.id)
            if let builtInID = record.builtInID {
                existingBuiltInIDs.insert(builtInID)
            }
            templatesInserted += 1
        }

        for record in notes {
            guard !existingNoteIDs.contains(record.id) else {
                duplicatesSkipped += 1
                continue
            }
            let archivedLifecycle = NoteLifecycle(rawValue: record.lifecycleRawValue) ?? .recoverable
            let restoredLifecycle: NoteLifecycle =
                archivedLifecycle == .recording || archivedLifecycle == .processing
                ? .recoverable
                : archivedLifecycle
            let mode = record.recordingModeRawValue
                .flatMap(RecordingMode.init(rawValue:)) ?? .listenAlong
            let note = Note(
                id: record.id,
                lifecycle: restoredLifecycle,
                title: record.title,
                markdownBody: record.markdownBody,
                userNotes: record.userNotes,
                transcriptSegments: record.transcriptSegments,
                createdAt: record.createdAt,
                languageIdentifier: record.languageIdentifier,
                template: TemplateSnapshot(
                    name: record.templateName,
                    symbol: record.templateSymbol,
                    instructions: record.templateInstructions
                ),
                recordingMode: mode,
                retainsAudio: record.retainsAudio,
                calendarEvent: record.calendarEvent
            )
            note.processingStageRawValue = nil
            note.updatedAt = record.updatedAt
            note.recordingStartedAt = record.recordingStartedAt
            note.duration = record.duration
            note.isFavorite = record.isFavorite
            note.deletedAt = record.deletedAt
            note.transcriptRevision = record.transcriptRevision
            note.generatedFromTranscriptRevision = record.generatedFromTranscriptRevision
            note.userEditedNotes = record.userEditedNotes
            note.lastErrorMessage = archivedLifecycle == restoredLifecycle
                ? record.lastErrorMessage
                : "This recording was active when the backup was created. Its note and transcript were restored, but no incomplete audio session was resumed."
            note.systemAudioRelativePath = audioPaths[record.id]?.system
            note.microphoneAudioRelativePath = audioPaths[record.id]?.microphone
            note.folder = record.folderID.flatMap { foldersByID[$0] }
            context.insert(note)
            existingNoteIDs.insert(record.id)
            notesInserted += 1
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw BurritoArchiveError.fileOperationFailed(
                operation: "restore the backup",
                details: error.localizedDescription
            )
        }

        return ArchiveRestoreReport(
            notesInserted: notesInserted,
            foldersInserted: foldersInserted,
            templatesInserted: templatesInserted,
            duplicatesSkipped: duplicatesSkipped
        )
    }
}

enum BurritoArchiveError: Error, Equatable, Sendable {
    case invalidArchive(details: String)
    case unsupportedVersion(found: Int, supported: Int)
    case fileOperationFailed(operation: String, details: String)

    var recoveryMessage: String {
        switch self {
        case .invalidArchive(let details):
            "Burrito could not read this backup: \(details) Existing notes were not changed."
        case .unsupportedVersion(let found, let supported):
            "This backup uses format version \(found), but this Burrito build supports version \(supported). Update Burrito, then try again. Existing notes were not changed."
        case .fileOperationFailed(let operation, let details):
            "Burrito could not \(operation): \(details) Existing notes were not changed."
        }
    }
}
