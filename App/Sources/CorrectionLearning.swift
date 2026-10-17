import Foundation

/// 입타가 넣은 단어와 사용자가 곧바로 고친 단어의 쌍. 개인 사전 후보로만 쌓이고, 등록은 사용자가 누른다.
struct CorrectionCandidate: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    /// 입타가 넣은 표현
    var heard: String
    /// 사용자가 고친 표기
    var spelling: String
    var appName: String
    var count = 1
}

/// 자동으로 넣은 글을 잠시 뒤 다시 읽어, 사용자가 고친 단어를 찾는다. 순수 함수라 검사하기 쉽다.
enum CorrectionLearning {
    /// 넣은 뒤 이만큼 기다렸다가 한 번만 읽는다.
    static let checkDelay: TimeInterval = 10
    static let maxCandidates = 50
    static let maxPairsPerPaste = 5

    struct Region: Equatable {
        let text: String
        /// 창이 값 끝 전에 잘렸으면 마지막 단어가 반쪽일 수 있다.
        let truncated: Bool
    }

    /// 입력칸 값 안에서 넣은 글이 있던 자리의 지금 글. 앞 글 꼬리(contextTail) 바로 뒤부터 넣은 글 길이의 1.5배를 본다.
    /// 앞 글이 없으면(빈 칸에 넣음) 값의 앞부분.
    static func editedRegion(in value: String, contextTail: String, insertedCount: Int) -> Region? {
        guard insertedCount > 0, !value.isEmpty else { return nil }
        let window = Int(Double(insertedCount) * 1.5) + 8
        let start: String.Index
        if !contextTail.isEmpty, let found = value.range(of: contextTail, options: .backwards) {
            start = found.upperBound
        } else if contextTail.isEmpty {
            start = value.startIndex
        } else {
            return nil
        }
        let end = value.index(start, offsetBy: window, limitedBy: value.endIndex) ?? value.endIndex
        return Region(text: String(value[start..<end]), truncated: end < value.endIndex)
    }

    /// 넣은 글과 고친 글의 단어를 맞춰 보고 바뀐 쌍만 돌려준다.
    /// 같은 단어가 절반도 안 남았으면(통째로 지우고 다른 글을 썼으면) 아무것도 돌려주지 않는다.
    static func pairs(inserted: String, edited: String, editedTruncated: Bool = false) -> [(heard: String, spelling: String)] {
        var a = tokens(inserted)
        var b = tokens(edited)
        if editedTruncated {
            // 창이 글 중간에서 끊겼으면 양쪽 마지막 단어는 반쪽일 수 있어 둘 다 뺀다.
            if !b.isEmpty { b.removeLast() }
            if a.count > 1 { a.removeLast() }
        }
        guard !a.isEmpty, !b.isEmpty, a != b else { return [] }
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        guard dp[0][0] * 2 >= min(a.count, b.count) else { return [] }
        var out: [(String, String)] = []
        var pendingA: [String] = []
        var pendingB: [String] = []
        func flush() {
            if pendingA.count == pendingB.count {
                for (x, y) in zip(pendingA, pendingB) where x != y { out.append((x, y)) }
            } else if !pendingA.isEmpty, !pendingB.isEmpty {
                out.append((pendingA.joined(separator: " "), pendingB.joined(separator: " ")))
            }
            pendingA = []
            pendingB = []
        }
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                flush()
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                pendingA.append(a[i])
                i += 1
            } else {
                pendingB.append(b[j])
                j += 1
            }
        }
        pendingA += a[i...]
        pendingB += b[j...]
        flush()
        return Array(out.filter { usable($0.0) && usable($0.1) }.prefix(maxPairsPerPaste)).map { (heard: $0.0, spelling: $0.1) }
    }

    /// 공백으로 나누고 양끝 문장부호는 뗀다.
    static func tokens(_ text: String) -> [String] {
        let trimSet = CharacterSet(charactersIn: ".,!?…\"'()[]{}<>:;")
        return text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { $0.trimmingCharacters(in: trimSet) }
            .filter { !$0.isEmpty }
    }

    /// 2~20자이고 글자나 숫자가 하나는 있어야 후보가 된다.
    static func usable(_ word: String) -> Bool {
        (2...20).contains(word.count) && word.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}
