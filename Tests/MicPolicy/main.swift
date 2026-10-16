import Foundation

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("FAIL: \(name)") }
    print("PASS: \(name)")
}

func dev(_ id: String, _ kind: AudioInputKind, isDefault: Bool = false, name: String? = nil) -> AudioInputDevice {
    AudioInputDevice(id: id, name: name ?? id, kind: kind, isSystemDefault: isDefault)
}

let builtIn = dev("BuiltInMicrophoneDevice", .builtIn, name: "MacBook Pro 마이크")
let usb = dev("ABKO-N550", .usb, name: "ABKO N550")
let bt = dev("AirPods-UID", .bluetooth, name: "AirPods")
let live = dev("LiveSpeech-UID", .virtual, isDefault: true, name: "실시간 말하기")
let blackhole = dev("BlackHole2ch_UID", .virtual, name: "BlackHole 2ch")

// transport 코드 → 종류
check(AudioInputKind(transportType: 0x626c_746e) == .builtIn, "bltn is built-in")
check(AudioInputKind(transportType: 0x7669_7274) == .virtual, "virt is virtual")
check(AudioInputKind(transportType: 0x626c_7565) == .bluetooth, "blue is bluetooth")
check(AudioInputKind(transportType: 0x6772_7570) == .aggregate, "grup is aggregate")
check(AudioInputKind(transportType: 0) == .unknown, "0 is unknown")
check(!AudioInputKind.virtual.isRealMicrophone && AudioInputKind.usb.isRealMicrophone, "virtual is not a microphone")

// 사용자가 고른 장치는 가상이라도 그대로
check(MicPolicy.pick(selected: "BlackHole2ch_UID", devices: [builtIn, blackhole], lidClosed: false) == .init(uid: "BlackHole2ch_UID", reason: .chosen), "explicit choice wins even if virtual")
// 고른 장치가 사라지면 기본 따르기로
check(MicPolicy.pick(selected: "Gone", devices: [dev("BuiltInMicrophoneDevice", .builtIn, isDefault: true)], lidClosed: false).reason == .systemDefault, "missing choice follows default")
// 기본이 실제 마이크면 그대로 따른다
check(MicPolicy.pick(selected: "", devices: [dev("BuiltInMicrophoneDevice", .builtIn, isDefault: true), usb], lidClosed: false).uid == "BuiltInMicrophoneDevice", "real default is followed")
// ★ 기본이 실시간 말하기(가상)면 내장 마이크로 바꾼다 — 10/16 「입타 바 안 움직임」
let swapped = MicPolicy.pick(selected: "", devices: [live, builtIn, usb], lidClosed: false)
check(swapped.uid == "BuiltInMicrophoneDevice", "virtual default is replaced by built-in")
check(swapped.reason == .defaultReplaced(defaultName: "실시간 말하기"), "replacement reason names the virtual device")
check(swapped.reason.note?.contains("실시간 말하기") == true, "note mentions the virtual device")
// 내장이 없으면 USB > 블루투스
check(MicPolicy.pick(selected: "", devices: [live, bt, usb], lidClosed: false).uid == "ABKO-N550", "usb beats bluetooth")
check(MicPolicy.pick(selected: "", devices: [live, bt], lidClosed: false).uid == "AirPods-UID", "bluetooth beats nothing")
// 덮개가 닫히면 내장을 건너뛴다
check(MicPolicy.pick(selected: "", devices: [dev("BuiltInMicrophoneDevice", .builtIn, isDefault: true), usb], lidClosed: true).uid == "ABKO-N550", "closed lid skips built-in")
// 덮개가 닫혔는데 내장뿐이면 그래도 내장
check(MicPolicy.pick(selected: "", devices: [dev("BuiltInMicrophoneDevice", .builtIn, isDefault: true)], lidClosed: true).uid == "BuiltInMicrophoneDevice", "closed lid with only built-in still records")
// 기본 장치를 못 읽으면 실제 마이크 중 최선
check(MicPolicy.pick(selected: "", devices: [blackhole, usb], lidClosed: false) == .init(uid: "ABKO-N550", reason: .defaultMissing), "no default picks best real mic")
// 가상 장치만 있으면 없음
check(MicPolicy.pick(selected: "", devices: [blackhole], lidClosed: false) == .init(uid: nil, reason: .noMicrophone), "only virtual means no microphone")
check(MicPolicy.pick(selected: "", devices: [], lidClosed: false).reason == .noMicrophone, "empty list means no microphone")
// 표시 제목
check(usb.title == "ABKO N550 · USB" && live.title == "실시간 말하기 · 가상 장치", "titles carry the kind label")
print("all MicPolicy checks passed")
