import AVFoundation
import CoreAudio
import Foundation

enum RecorderError: LocalizedError {
    case noPermission
    case engine(String)
    var errorDescription: String? {
        switch self {
        case .noPermission: return "마이크 권한이 없습니다"
        case .engine(let s): return s
        }
    }
}

final class Recorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var wavURL: URL?
    private var startedAt: Date?
    private var tapInstalled = false
    private let lock = NSLock()

    func permissionLabel() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "허용"
        case .denied: return "거부"
        case .restricted: return "제한"
        case .notDetermined: return "아직 묻지 않음"
        @unknown default: return "알 수 없음"
        }
    }

    func hasPermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    func listDevices() -> [(id: String, name: String)] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { ($0.uniqueID, $0.localizedName) }
    }

    func start(deviceId: String, onTick: @escaping (Double, Double) -> Void) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.noPermission
        }
        // Do not hold the write lock across prepare/start/removeTap: the tap callback
        // also takes `lock`. NSLock is not recursive.
        tearDownEngine()
        try setDefaultInput(uniqueId: deviceId)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("malgyeol-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let newFile: AVAudioFile
        do {
            newFile = try AVAudioFile(forWriting: tmp, settings: settings)
        } catch {
            throw RecorderError.engine("녹음 파일을 만들지 못했습니다: \(error.localizedDescription)")
        }
        // Disk settings stay Int16 16kHz. AVAudioFile.processingFormat on this OS is
        // Float32 non-interleaved; write(from:) must match that or CoreAudio CAAssertRtn (SIGTRAP).
        let outFormat = newFile.processingFormat

        // Access inputNode before prepare(). prepare() on an empty graph throws
        // NSException "inputNode != nullptr || outputNode != nullptr" which Swift do/catch
        // does not catch (T-260912-021 probe-a).
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            try? FileManager.default.removeItem(at: tmp)
            throw RecorderError.engine("입력 장치를 열지 못했습니다 (sampleRate=0). 권한 또는 장치를 확인하세요.")
        }
        guard let conv = AVAudioConverter(from: inFormat, to: outFormat) else {
            try? FileManager.default.removeItem(at: tmp)
            throw RecorderError.engine("오디오 변환을 만들지 못했습니다")
        }

        lock.lock()
        file = newFile
        converter = conv
        wavURL = tmp
        startedAt = Date()
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, outFormat: outFormat, onTick: onTick)
        }
        tapInstalled = true
        malgyeolLog("record graph inSR=\(inFormat.sampleRate) ch=\(inFormat.channelCount) processingSR=\(outFormat.sampleRate) common=\(outFormat.commonFormat.rawValue) interleaved=\(outFormat.isInterleaved)")
        engine.prepare()
        do {
            try engine.start()
        } catch {
            tearDownEngine()
            try? FileManager.default.removeItem(at: tmp)
            throw RecorderError.engine("녹음을 시작하지 못했습니다: \(error.localizedDescription)")
        }
        malgyeolLog("engine start inSR=\(inFormat.sampleRate) ch=\(inFormat.channelCount)")
    }

    private func handle(buffer: AVAudioPCMBuffer, outFormat: AVAudioFormat, onTick: @escaping (Double, Double) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let converter, let file, let startedAt else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let frames = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded() + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: frames) else { return }
        var error: NSError?
        var supplied = false
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        converter.convert(to: out, error: &error, withInputFrom: inputBlock)
        if let error {
            malgyeolLog("convert \(error)")
            return
        }
        do {
            try file.write(from: out)
        } catch {
            malgyeolLog("write \(error)")
        }
        let rms = rmsLevel(buffer)
        let elapsed = Date().timeIntervalSince(startedAt)
        DispatchQueue.main.async { onTick(rms, elapsed) }
    }

    private func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let ch = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n {
            let v = ch[i]
            sum += v * v
        }
        return min(1, Double(sqrt(sum / Float(n))) * 4)
    }

    func stop() throws -> URL {
        tearDownEngine()
        lock.lock()
        let url = wavURL
        wavURL = nil
        file = nil
        converter = nil
        startedAt = nil
        lock.unlock()
        guard let url else { throw RecorderError.engine("녹음 파일이 없습니다") }
        return url
    }

    func cancel() {
        tearDownEngine()
        lock.lock()
        let url = wavURL
        wavURL = nil
        file = nil
        converter = nil
        startedAt = nil
        lock.unlock()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    /// Stop I/O and remove the tap without holding `lock` (tap callback uses `lock`).
    private func tearDownEngine() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
    }

    private func setDefaultInput(uniqueId: String) throws {
        guard !uniqueId.isEmpty else { return }
        let devices = listAudioDevices()
        guard let match = devices.first(where: { $0.uid == uniqueId }) else { return }
        var id = match.id
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        )
        if status != noErr {
            malgyeolLog("setDefaultInput status=\(status) — 기본 장치로 진행")
        }
    }

    private func listAudioDevices() -> [(id: AudioDeviceID, uid: String)] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        var out: [(AudioDeviceID, String)] = []
        for id in ids {
            var uidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(id, &uidAddr, 0, nil, &uidSize, &uid) == noErr,
               let uid {
                out.append((id, uid.takeUnretainedValue() as String))
            }
        }
        return out
    }
}
