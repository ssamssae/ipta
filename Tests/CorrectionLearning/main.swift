import Foundation

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("FAIL: \(name)") }
    print("PASS: \(name)")
}

// 단어쌍 추출
let one = CorrectionLearning.pairs(inserted: "오늘 아태나에서 회의 했어요", edited: "오늘 아테나에서 회의 했어요")
check(one.count == 1 && one[0].heard == "아태나에서" && one[0].spelling == "아테나에서", "single changed word")
let two = CorrectionLearning.pairs(inserted: "입 타 로 적고 말결 로 다듬어요", edited: "입타 로 적고 말결 로 다듬어요")
check(two.count == 1 && two[0].heard == "입 타" && two[0].spelling == "입타", "merged tokens become one pair")
check(CorrectionLearning.pairs(inserted: "오늘 회의 했어요", edited: "오늘 회의 했어요").isEmpty, "unchanged text gives nothing")
check(CorrectionLearning.pairs(inserted: "오늘 회의 했어요", edited: "전혀 다른 내용의 글").isEmpty, "rewritten field gives nothing")
check(CorrectionLearning.pairs(inserted: "a b c", edited: "a x c").isEmpty, "one-letter words are not candidates")
let many = CorrectionLearning.pairs(inserted: "하나 둘째 셋째 넷째 다섯 여섯 일곱 여덟", edited: "하나 두울째 셋째 네엣째 다섯 여섯 일고옵 여덟")
check(many.count == 3, "multiple pairs")
check(CorrectionLearning.pairs(inserted: "하나 둘 셋", edited: "하나 두 셋").isEmpty, "one-syllable words are not candidates")
let truncated = CorrectionLearning.pairs(inserted: "오늘 아태나에서 회의", edited: "오늘 아테나에서 회", editedTruncated: true)
check(truncated.count == 1 && truncated[0].spelling == "아테나에서", "truncated last word is dropped")
check(CorrectionLearning.pairs(inserted: "오늘, 아태나에서 회의!", edited: "오늘, 아테나에서 회의!").first?.heard == "아태나에서", "punctuation is trimmed")

// 고친 자리 찾기
let value = "회의록 초안입니다. 오늘 아테나에서 회의 했어요. 이어서 다른 글"
let region = CorrectionLearning.editedRegion(in: value, contextTail: "초안입니다. ", insertedCount: 8)
check(region?.text.hasPrefix("오늘 아테나에서 회의") == true && region?.truncated == true, "region after context tail")
check(CorrectionLearning.editedRegion(in: "오늘 아테나에서 회의", contextTail: "", insertedCount: 12)?.truncated == false, "empty context reads from the start")
check(CorrectionLearning.editedRegion(in: value, contextTail: "없는 꼬리", insertedCount: 10) == nil, "missing tail gives nil")

// 후보 저장·정렬·상한
var p = Personalization()
p.correctionLearningEnabled = true
p.rememberCorrections([(heard: "아태나", spelling: "아테나")], appName: "메모")
p.rememberCorrections([(heard: "아태나", spelling: "아테나"), (heard: "입 타", spelling: "입타")], appName: "메일")
check(p.corrections.count == 2 && p.corrections[0].count == 2 && p.corrections[0].heard == "아태나", "same pair counts up and sorts first")
for i in 0..<60 { p.rememberCorrections([(heard: "x\(i)", spelling: "y\(i)")], appName: "a") }
check(p.corrections.count == CorrectionLearning.maxCandidates, "candidate list is capped")
var off = Personalization()
off.rememberCorrections([(heard: "아태나", spelling: "아테나")], appName: "메모")
check(off.corrections.isEmpty, "disabled learning stores nothing")

// 파일 호환
let legacy = Data(#"{"vocabulary":[],"tones":[],"historyEnabled":false,"history":[]}"#.utf8)
check((try? JSONDecoder().decode(Personalization.self, from: legacy)) != nil, "0.1.28 file loads")
check((try? JSONDecoder().decode(Personalization.self, from: Data(#"{"vocabulary":[]}"#.utf8))) != nil, "oldest file loads")
let encoded = try! JSONEncoder().encode(p)
let back = try! JSONDecoder().decode(Personalization.self, from: encoded)
check(back.corrections.count == p.corrections.count && back.correctionLearningEnabled, "round trip keeps candidates")
print("all CorrectionLearning checks passed")
