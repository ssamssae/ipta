import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import IOKit

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
    /// 녹음 장치가 바뀌면 새로 만든다. 옛 장치 포맷이 그래프에 남아 첫 녹음이 비는 일을 막는다.
    private var engine = AVAudioEngine()
    /// 지금 엔진 입력 유닛에 묶인 CoreAudio 장치. 0 = 맥 기본 입력 그대로.
    private var boundDeviceID: AudioDeviceID = 0
    private var file: AVAudioFile?
    /// 말하는 동안 미리 받아적기용 구간 파일. 본 파일과 같은 포맷으로 같이 쓴다.
    private var segmentFile: AVAudioFile?
    private var segmentURL: URL?
    private var segmentSettings: [String: Any] = [:]
    private var converter: AVAudioConverter?
    private var wavURL: URL?
    private var startedAt: Date?
    private var tapInstalled = false
    private let lock = NSLock()
    /// 마지막 녹음에서 마이크를 왜 그렇게 골랐는지. nil 이면 알릴 것이 없다.
    private(set) var lastPickNote: String?
    /// 맥 기본 입력이나 장치 목록이 바뀌면 메인 큐에서 부른다.
    var onInputDevicesChange: (() -> Void)?
    private var watching = false

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

    /// 소리를 받을 수 있는 장치만. 종류(내장·USB·블루투스·가상)와 맥 기본 입력 여부를 같이 준다.
    func listDevices() -> [AudioInputDevice] {
        let defaultID = defaultInputDeviceID()
        return listAudioDevices().compactMap { dev in
            guard inputChannelCount(dev.id) > 0 else { return nil }
            return AudioInputDevice(
                id: dev.uid,
                name: deviceName(dev.id) ?? dev.uid,
                kind: AudioInputKind(transportType: transportType(dev.id)),
                isSystemDefault: dev.id == defaultID
            )
        }
    }

    func start(deviceId: String, onTick: @escaping (Double, Double) -> Void) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.noPermission
        }
        // Do not hold the write lock across prepare/start/removeTap: the tap callback
        // also takes `lock`. NSLock is not recursive.
        tearDownEngine()

        // 맥 전체 기본 입력은 바꾸지 않는다. 고른 장치(또는 정책이 고른 실제 마이크)를 엔진 입력 유닛에만 묶는다.
        let devices = listDevices()
        let lidClosed = Self.isLidClosed()
        let pick = MicPolicy.pick(selected: deviceId, devices: devices, lidClosed: lidClosed)
        lastPickNote = pick.reason.note
        let targetID = pick.uid.flatMap { uid in listAudioDevices().first { $0.uid == uid }?.id } ?? 0
        if targetID != boundDeviceID {
            engine = AVAudioEngine()
            boundDeviceID = 0
            tapInstalled = false
        }
        malgyeolLog("mic pick uid=\(pick.uid ?? "-") reason=\(pick.reason) lidClosed=\(lidClosed) devices=\(devices.map { "\($0.name)[\($0.kind.rawValue)\($0.isSystemDefault ? ",default" : "")]" })")

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
        if targetID != 0 {
            // 묶기에 실패하면 맥 기본 입력으로 진행한다(예전 동작과 같다).
            boundDeviceID = bindInput(deviceID: targetID) ? targetID : 0
        }
        // 장치를 묶은 뒤 「하드웨어」 포맷(inputFormat)을 읽어 그 포맷으로 탭을 건다.
        // outputFormat 은 맥 기본 장치 포맷으로 굳어 있어서, 묶은 장치의 샘플레이트가 다르면
        // 탭을 nil 포맷으로 걸었을 때 start 가 -10868(FormatNotSupported)로 실패한다(볼칸 10/17 실측).
        let inFormat = input.inputFormat(forBus: 0)
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
        segmentSettings = settings
        if let seg = Self.openSegment(settings) {
            segmentFile = seg.file
            segmentURL = seg.url
        }
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, outFormat: outFormat, onTick: onTick)
        }
        tapInstalled = true
        malgyeolLog("record graph inSR=\(inFormat.sampleRate) ch=\(inFormat.channelCount) processingSR=\(outFormat.sampleRate) common=\(outFormat.commonFormat.rawValue) interleaved=\(outFormat.isInterleaved) bound=\(boundDeviceID)")
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
        if let segmentFile {
            do { try segmentFile.write(from: out) } catch { malgyeolLog("segment write \(error)") }
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
        let leftoverSegment = segmentURL
        segmentFile = nil
        segmentURL = nil
        lock.unlock()
        // finishSegment() 로 가져가지 않은 구간 파일은 버린다(본 파일에 같은 소리가 있다).
        if let leftoverSegment { try? FileManager.default.removeItem(at: leftoverSegment) }
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
        let seg = segmentURL
        segmentFile = nil
        segmentURL = nil
        lock.unlock()
        if let url { try? FileManager.default.removeItem(at: url) }
        if let seg { try? FileManager.default.removeItem(at: seg) }
    }

    /// 지금까지의 구간 파일을 닫아 돌려주고 새 구간을 연다. 녹음 중이 아니면 nil.
    func cutSegment() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard startedAt != nil, let url = segmentURL else { return nil }
        segmentFile = nil
        segmentURL = nil
        if let next = Self.openSegment(segmentSettings) {
            segmentFile = next.file
            segmentURL = next.url
        }
        return url
    }

    /// 마지막 구간 파일을 닫아 돌려준다. stop() 전에 부른다.
    func finishSegment() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        let url = segmentURL
        segmentFile = nil
        segmentURL = nil
        return url
    }

    private static func openSegment(_ settings: [String: Any]) -> (file: AVAudioFile, url: URL)? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("malgyeol-seg-\(UUID().uuidString).wav")
        guard let file = try? AVAudioFile(forWriting: url, settings: settings) else { return nil }
        return (file, url)
    }

    /// Stop I/O and remove the tap without holding `lock` (tap callback uses `lock`).
    private func tearDownEngine() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
    }

    /// 엔진 입력 유닛(AUHAL)에 장치를 묶는다. 맥 기본 입력 설정은 건드리지 않는다.
    private func bindInput(deviceID: AudioDeviceID) -> Bool {
        guard let unit = engine.inputNode.audioUnit else {
            malgyeolLog("bindInput: 입력 유닛 없음 — 맥 기본 입력으로 진행")
            return false
        }
        var id = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            malgyeolLog("bindInput device=\(deviceID) status=\(status) — 맥 기본 입력으로 진행")
            return false
        }
        return true
    }

    /// 맥 기본 입력·장치 목록이 바뀌면 `onInputDevicesChange` 를 메인 큐에서 부른다. 여러 번 불러도 한 번만 건다.
    func watchInputDevices() {
        guard !watching else { return }
        watching = true
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDevices,
        ]
        for selector in selectors {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main
            ) { [weak self] _, _ in
                self?.onInputDevicesChange?()
            }
            if status != noErr { malgyeolLog("watchInputDevices selector=\(selector) status=\(status)") }
        }
    }

    /// `--mic-probe`: 장치 목록·선택 결과를 찍고 2초 녹음해 파일 크기와 최대 레벨을 보고한다.
    /// 실기기에서 마이크 선택 설계를 확인하는 용도. 권한이 없으면 한 번 묻고 30초 기다린다.
    static func runProbe() -> Int32 {
        func say(_ line: String) {
            malgyeolLog(line)
            fputs(line + "\n", stdout)
        }
        let recorder = Recorder()
        let devices = recorder.listDevices()
        for d in devices { say("probe device \(d.title) default=\(d.isSystemDefault) uid=\(d.id)") }
        let selected = UserDefaults.standard.string(forKey: "malgyeol.selectedDeviceId") ?? ""
        let lidClosed = isLidClosed()
        let pick = MicPolicy.pick(selected: selected, devices: devices, lidClosed: lidClosed)
        say("probe pick selected=\(selected.isEmpty ? "(맥 기본)" : selected) uid=\(pick.uid ?? "-") reason=\(pick.reason) lidClosed=\(lidClosed)")
        if !recorder.hasPermission() {
            let gate = DispatchSemaphore(value: 0)
            recorder.requestPermission { _ in gate.signal() }
            _ = gate.wait(timeout: .now() + 30)
        }
        var peak = 0.0
        var ticks = 0
        do {
            try recorder.start(deviceId: selected) { level, _ in
                peak = max(peak, level)
                ticks += 1
            }
            Thread.sleep(forTimeInterval: 2)
            let url = try recorder.stop()
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
            try? FileManager.default.removeItem(at: url)
            say("probe recorded bytes=\(bytes) ticks=\(ticks) peak=\(String(format: "%.3f", peak)) note=\(recorder.lastPickNote ?? "-")")
            return bytes > 44 ? 0 : 2
        } catch {
            say("probe error \(error.localizedDescription)")
            return 1
        }
    }

    /// 노트북 덮개가 닫혀 있는지. 못 읽으면 열린 것으로 본다.
    static func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return false }
        return (value as? Bool) ?? false
    }

    /// 지금 맥 기본 마이크 이름(설정 화면 「맥 기본 마이크 따르기」 옆에 보여 준다).
    func defaultInputName() -> String? {
        let id = defaultInputDeviceID()
        guard id != 0 else { return nil }
        return deviceName(id)
    }

    private func defaultInputDeviceID() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
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

    private func deviceName(_ id: AudioDeviceID) -> String? {
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private func transportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    /// 입력 스트림의 채널 수 합. 0 이면 스피커처럼 소리를 받지 못하는 장치다.
    private func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
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
