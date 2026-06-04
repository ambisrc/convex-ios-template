import AVFoundation
import Foundation

protocol TemplateMicrophonePermissionProviding {
    func currentPermission() -> TemplateMicrophonePermission
    func requestPermission() async -> TemplateMicrophonePermission
}

struct TemplateGrantedMicrophonePermissionService: TemplateMicrophonePermissionProviding {
    func currentPermission() -> TemplateMicrophonePermission { .granted }

    func requestPermission() async -> TemplateMicrophonePermission { .granted }
}

enum TemplateAVAudioSessionPermissionMapper {
    static func map(_ permission: AVAudioSession.RecordPermission) -> TemplateMicrophonePermission {
        switch permission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}

struct TemplateAVAudioSessionPermissionService: TemplateMicrophonePermissionProviding {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func currentPermission() -> TemplateMicrophonePermission {
        TemplateAVAudioSessionPermissionMapper.map(session.recordPermission)
    }

    func requestPermission() async -> TemplateMicrophonePermission {
        switch session.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted ? .granted : .denied)
                }
            }
        @unknown default:
            return .unavailable
        }
    }
}
