import AVFoundation
import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class PermissionAccess {
    enum Permission {
        case microphone
        case systemAudio

        fileprivate var settingsURL: URL? {
            let anchor = switch self {
            case .microphone: "Privacy_Microphone"
            case .systemAudio: "Privacy_ScreenCapture"
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

    var allGranted: Bool {
        systemAudio == .granted
            && microphone == .granted
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

    func openSettings(for permission: Permission) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
