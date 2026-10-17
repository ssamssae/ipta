import Foundation

/// 긴 녹음을 말하는 동안 구간으로 잘라 미리 받아적는 규칙. 순수 함수라 검사하기 쉽다.
/// 짧은 녹음(최소 구간 길이 미만)은 예전과 똑같이 정지 뒤 한 번에 받아적는다.
enum SegmentPlanner {
    /// 이보다 짧은 녹음은 자르지 않는다.
    static let minSegmentSeconds: Double = 30
    /// 조용한 순간을 못 찾아도 이 길이가 되면 자른다(whisper 는 어차피 30초 창으로 본다).
    static let maxSegmentSeconds: Double = 60
    /// 이 레벨 아래가 「조용함」.
    static let quietLevel: Double = 0.04
    /// 조용함이 이만큼 이어져야 말 사이로 본다.
    static let quietHoldSeconds: Double = 0.4

    /// elapsed = 녹음 경과, lastCut = 마지막으로 자른 시각, quietSince = 조용해진 시각(nil = 지금 말하는 중).
    static func shouldCut(elapsed: Double, lastCut: Double, quietSince: Double?) -> Bool {
        let length = elapsed - lastCut
        guard length >= minSegmentSeconds else { return false }
        if length >= maxSegmentSeconds { return true }
        guard let quietSince else { return false }
        return elapsed - quietSince >= quietHoldSeconds
    }

    /// 레벨 틱마다 조용해진 시각을 갱신한다.
    static func nextQuietSince(current: Double?, level: Double, elapsed: Double) -> Double? {
        if level < quietLevel { return current ?? elapsed }
        return nil
    }

    /// 구간 결과를 순서대로 잇는다. 빈 구간은 건너뛴다. 하나라도 빠졌으면 nil(통째 인식으로 돌아간다).
    static func join(_ texts: [Int: String], count: Int) -> String? {
        guard count > 0 else { return nil }
        var parts: [String] = []
        for index in 0..<count {
            guard let text = texts[index] else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        return parts.joined(separator: " ")
    }
}
