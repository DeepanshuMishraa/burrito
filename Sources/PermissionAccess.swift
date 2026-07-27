import AVFoundation
import AppKit
import CoreGraphics
import Observation
import Speech

@MainActor
@Observable
final class PermissionAccess {
    enum Permission {
        case microphone
        case systemAudio
        case speechRecognition

        fileprivate var settingsURL: URL? {
            let anchor = switch self {
            case .microphone: "Privacy_Microphone"
            case .systemAudio: "Privacy_ScreenCapture"
            case .speechRecognition: "Privacy_SpeechRecognition"
            }
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
            )
        }
    }

    enum State: Equatable {
        case needsAccess
        case granted
        case denied
    }

    private(set) var systemAudio: State = .needsAccess
    private(set) var microphone: State = .needsAccess
    private(set) var speechRecognition: State = .needsAccess

    var allGranted: Bool {
        systemAudio == .granted
            && microphone == .granted
            && speechRecognition == .granted
    }

    init() {
        refresh()
    }

    func refresh() {
        systemAudio = CGPreflightScreenCaptureAccess() ? .granted : .needsAccess
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .needsAccess
        @unknown default: .denied
        }
        speechRecognition = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .needsAccess
        @unknown default: .denied
        }
    }

    func requestSystemAudio() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    func requestMicrophone() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        refresh()
    }

    func requestSpeechRecognition() async {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            let status = await Self.requestSystemSpeechAuthorization()
            speechRecognition = status == .authorized ? .granted : .denied
        } else {
            refresh()
        }
    }

    func openSettings(for permission: Permission) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private nonisolated static func requestSystemSpeechAuthorization()
        async -> SFSpeechRecognizerAuthorizationStatus
    {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
    }
}
