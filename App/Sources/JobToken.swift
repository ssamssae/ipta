import Foundation

struct JobToken: Equatable {
    private(set) var value: UInt64 = 0

    @discardableResult
    mutating func bump() -> UInt64 {
        value += 1
        return value
    }

    func isCurrent(_ job: UInt64) -> Bool {
        job == value
    }
}
