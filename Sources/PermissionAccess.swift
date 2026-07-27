import AVFoundation
import CoreGraphics
import Observation
import Speech

@MainActor
@Observable
final class PermissionAccess {
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
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization {
                    continuation.resume(returning: $0)
                }
            }
            speechRecognition = status == .authorized ? .granted : .denied
        } else {
            refresh()
        }
    }
}
