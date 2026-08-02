import Foundation

struct LocalRecordingFileStore: RecordingFileStore {
    private let root: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = support.appending(path: "Burrito/Recordings", directoryHint: .isDirectory)
    }

    init(root: URL) {
        self.root = root
    }

    func createSession(id: UUID, mode: RecordingMode) -> Result<RecordingFiles, BurritoError> {
        let directory = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return .success(
                RecordingFiles(
                    sessionID: id,
                    systemAudioURL: directory.appending(path: "system.m4a"),
                    microphoneAudioURL: mode == .meeting
                        ? directory.appending(path: "microphone.m4a")
                        : nil
                )
            )
        } catch {
            return .failure(.storageFailed(details: error.localizedDescription))
        }
    }

    func relativePath(for url: URL) -> String {
        let rootPath = root.standardizedFileURL.path()
        let filePath = url.standardizedFileURL.path()
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func url(forRelativePath path: String) -> URL {
        root.appending(path: path)
    }

    func removeAudio(for files: RecordingFiles) -> Result<Void, BurritoError> {
        do {
            for url in [files.systemAudioURL, files.microphoneAudioURL].compactMap({ $0 })
            where FileManager.default.fileExists(atPath: url.path()) {
                try FileManager.default.removeItem(at: url)
            }
            return .success(())
        } catch {
            return .failure(.storageFailed(details: error.localizedDescription))
        }
    }
}
