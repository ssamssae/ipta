import Foundation

/// 입력 장치 종류. CoreAudio transport type(네 글자 코드)을 사람이 읽는 범주로 줄인 것.
/// CoreAudio 를 모르는 테스트에서도 쓸 수 있게 UInt32 코드만 받는다.
enum AudioInputKind: String, Sendable {
    case builtIn, usb, thunderbolt, pci, fireWire, hdmi, displayPort
    case bluetooth, bluetoothLE, continuity, airPlay, aggregate, virtual, unknown

    init(transportType: UInt32) {
        switch transportType {
        case 0x626c_746e: self = .builtIn      // 'bltn'
        case 0x7573_6220: self = .usb          // 'usb '
        case 0x7468_756e: self = .thunderbolt  // 'thun'
        case 0x7063_6920: self = .pci          // 'pci '
        case 0x3133_3934: self = .fireWire     // '1394'
        case 0x6864_6d69: self = .hdmi         // 'hdmi'
        case 0x6470_7274: self = .displayPort  // 'dprt'
        case 0x626c_7565: self = .bluetooth    // 'blue'
        case 0x626c_6561: self = .bluetoothLE  // 'blea'
        case 0x6363_7764, 0x6363_776c: self = .continuity  // 'ccwd' 'ccwl' (아이폰 연속성 캡처)
        case 0x6169_7270: self = .airPlay      // 'airp'
        case 0x6772_7570, 0x6667_7270: self = .aggregate   // 'grup' 'fgrp'
        case 0x7669_7274: self = .virtual      // 'virt' (실시간 말하기·BlackHole 류)
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .builtIn: return "내장"
        case .usb: return "USB"
        case .thunderbolt: return "썬더볼트"
        case .pci: return "PCI"
        case .fireWire: return "FireWire"
        case .hdmi: return "HDMI"
        case .displayPort: return "DisplayPort"
        case .bluetooth, .bluetoothLE: return "블루투스"
        case .continuity: return "아이폰 연속성"
        case .airPlay: return "AirPlay"
        case .aggregate: return "집계 장치"
        case .virtual: return "가상 장치"
        case .unknown: return "기타"
        }
    }

    /// 실제 소리를 받는 마이크인지. 가상·집계·AirPlay 는 다른 앱의 출력(실시간 말하기, BlackHole)일 때가 많다.
    var isRealMicrophone: Bool {
        switch self {
        case .virtual, .aggregate, .airPlay: return false
        default: return true
        }
    }

    /// 자동 선택 우선순위. 작을수록 먼저. 블루투스는 통화 프로파일로 음질이 떨어져 뒤로 민다.
    var autoRank: Int {
        switch self {
        case .builtIn: return 0
        case .usb, .thunderbolt, .pci, .fireWire, .hdmi, .displayPort: return 1
        case .continuity: return 2
        case .bluetooth, .bluetoothLE: return 3
        case .unknown: return 4
        case .airPlay, .aggregate, .virtual: return 9
        }
    }
}

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    /// CoreAudio 장치 UID. AVCaptureDevice.uniqueID 와 같은 값이라 저장된 선택값과 바로 비교된다.
    let id: String
    let name: String
    let kind: AudioInputKind
    let isSystemDefault: Bool

    var title: String { "\(name) · \(kind.label)" }
}

/// 녹음에 쓸 마이크를 고른다. 맥 전체 기본 입력은 절대 바꾸지 않는다.
enum MicPolicy {
    enum Reason: Equatable, Sendable {
        /// 사용자가 고른 장치가 있어 그대로 쓴다(가상 장치라도 사용자 뜻).
        case chosen
        /// 맥 기본 입력이 실제 마이크라 그대로 따른다.
        case systemDefault
        /// 맥 기본 입력이 가상·집계 장치(또는 덮개 닫힌 내장 마이크)라 실제 마이크로 바꿨다.
        case defaultReplaced(defaultName: String)
        /// 맥 기본 입력을 못 읽어 실제 마이크 중 하나를 골랐다.
        case defaultMissing
        /// 쓸 수 있는 마이크가 하나도 없다.
        case noMicrophone

        /// 설정 화면·로그에 보여 줄 한 줄. nil 이면 특별히 알릴 것이 없다.
        var note: String? {
            switch self {
            case .chosen, .systemDefault: return nil
            case .defaultReplaced(let name): return "맥 기본 입력 「\(name)」은 실제 마이크가 아니라 다른 마이크로 녹음합니다"
            case .defaultMissing: return "맥 기본 입력을 읽지 못해 실제 마이크를 골랐습니다"
            case .noMicrophone: return "쓸 수 있는 마이크가 없습니다"
            }
        }
    }

    struct Pick: Equatable, Sendable {
        let uid: String?
        let reason: Reason
    }

    /// - selected: 사용자가 고른 UID. 빈 문자열 = 맥 기본 마이크 따르기.
    /// - lidClosed: 노트북 덮개가 닫혀 있으면 내장 마이크를 자동 선택에서 건너뛴다.
    static func pick(selected: String, devices: [AudioInputDevice], lidClosed: Bool) -> Pick {
        if !selected.isEmpty, devices.contains(where: { $0.id == selected }) {
            return Pick(uid: selected, reason: .chosen)
        }
        if let def = devices.first(where: { $0.isSystemDefault }) {
            if usable(def, lidClosed: lidClosed) {
                return Pick(uid: def.id, reason: .systemDefault)
            }
            if let best = bestMicrophone(devices, lidClosed: lidClosed) {
                return Pick(uid: best.id, reason: .defaultReplaced(defaultName: def.name))
            }
            // 실제 마이크가 하나도 없으면 기본 입력이라도 쓴다(예: 덮개 닫힌 노트북 단독).
            return Pick(uid: def.id, reason: .systemDefault)
        }
        if let best = bestMicrophone(devices, lidClosed: lidClosed) {
            return Pick(uid: best.id, reason: .defaultMissing)
        }
        return Pick(uid: nil, reason: .noMicrophone)
    }

    static func bestMicrophone(_ devices: [AudioInputDevice], lidClosed: Bool) -> AudioInputDevice? {
        devices
            .filter { usable($0, lidClosed: lidClosed) }
            .min { ($0.kind.autoRank, $0.name) < ($1.kind.autoRank, $1.name) }
    }

    private static func usable(_ device: AudioInputDevice, lidClosed: Bool) -> Bool {
        device.kind.isRealMicrophone && !(lidClosed && device.kind == .builtIn)
    }
}
