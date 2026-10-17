import Foundation

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("FAIL: \(name)") }
    print("PASS: \(name)")
}

// 자르기 판정
check(!SegmentPlanner.shouldCut(elapsed: 20, lastCut: 0, quietSince: 19), "short recordings are never cut")
check(!SegmentPlanner.shouldCut(elapsed: 35, lastCut: 0, quietSince: nil), "no cut while speaking")
check(!SegmentPlanner.shouldCut(elapsed: 35, lastCut: 0, quietSince: 34.8), "quiet must hold for a moment")
check(SegmentPlanner.shouldCut(elapsed: 35, lastCut: 0, quietSince: 34.5), "cut at a quiet moment after 30s")
check(SegmentPlanner.shouldCut(elapsed: 61, lastCut: 0, quietSince: nil), "forced cut at 60s even while speaking")
check(!SegmentPlanner.shouldCut(elapsed: 50, lastCut: 35, quietSince: 49), "segment length counts from the last cut")
check(SegmentPlanner.shouldCut(elapsed: 66, lastCut: 35, quietSince: 65), "second segment cuts too")

// 조용함 추적
check(SegmentPlanner.nextQuietSince(current: nil, level: 0.01, elapsed: 10) == 10, "quiet starts now")
check(SegmentPlanner.nextQuietSince(current: 10, level: 0.01, elapsed: 11) == 10, "quiet start is kept")
check(SegmentPlanner.nextQuietSince(current: 10, level: 0.3, elapsed: 11) == nil, "speech resets quiet")

// 잇기
check(SegmentPlanner.join([0: "안녕하세요 ", 1: "오늘 회의는", 2: " 세 시입니다"], count: 3) == "안녕하세요 오늘 회의는 세 시입니다", "segments join in order")
check(SegmentPlanner.join([0: "안녕", 1: "   ", 2: "끝"], count: 3) == "안녕 끝", "empty segments are skipped")
check(SegmentPlanner.join([0: "안녕", 2: "끝"], count: 3) == nil, "missing segment falls back")
check(SegmentPlanner.join([:], count: 0) == nil, "no segments means no join")
print("all Segment checks passed")
