import CoreAudio
import Foundation

/// 녹음하는 동안 맥 출력(스피커·헤드폰)을 잠시 음소거한다.
/// 원래 음소거 상태를 기억했다가 그대로 되돌린다. 원래 음소거였으면 건드리지 않는다.
final class OutputMute {
    private var mutedDevice: AudioDeviceID = 0

    /// 우리가 음소거를 걸어야 하는지. 이미 음소거면 걸지 않고, 나중에 되돌리지도 않는다.
    static func shouldMute(wasMuted: Bool) -> Bool { !wasMuted }

    func mute() {
        guard mutedDevice == 0 else { return }
        let id = Self.defaultOutputDeviceID()
        guard id != 0 else { return }
        guard let was = Self.isMuted(id) else {
            malgyeolLog("output mute skip: device=\(id) 음소거 속성 없음")
            return
        }
        guard Self.shouldMute(wasMuted: was) else { return }
        if Self.setMuted(id, true) {
            mutedDevice = id
            malgyeolLog("output mute on device=\(id)")
        } else {
            malgyeolLog("output mute skip: device=\(id) 설정 불가")
        }
    }

    func restore() {
        guard mutedDevice != 0 else { return }
        let ok = Self.setMuted(mutedDevice, false)
        malgyeolLog("output mute restore device=\(mutedDevice) ok=\(ok)")
        mutedDevice = 0
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func defaultOutputDeviceID() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else {
            return 0
        }
        return id
    }

    static func isMuted(_ id: AudioDeviceID) -> Bool? {
        var addr = muteAddress
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    static func setMuted(_ id: AudioDeviceID, _ on: Bool) -> Bool {
        var addr = muteAddress
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = on ? 1 : 0
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
