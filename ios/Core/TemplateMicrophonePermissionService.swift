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
    static func map(_ permission: AVAudioApplication.recordPermission) -> TemplateMicrophonePermission {
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
    func currentPermission() -> TemplateMicrophonePermission {
        TemplateAVAudioSessionPermissionMapper.map(AVAudioApplication.shared.recordPermission)
    }

    func requestPermission() async -> TemplateMicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    let resolvedPermission: TemplateMicrophonePermission = granted
                        ? .granted
                        : TemplateAVAudioSessionPermissionMapper.map(AVAudioApplication.shared.recordPermission)
                    continuation.resume(returning: resolvedPermission)
                }
            }
        @unknown default:
            return .unavailable
        }
    }
}
