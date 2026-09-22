import Foundation
import Darwin

enum PolishProvider: String {
    case apple, claude, grok, openai, cursor, local
    var supportsOAuth: Bool { self != .apple && self != .local }
    var title: String { rawValue }
    var missingProgramNote: String { "missing" }
}
func malgyeolLog(_ message: String) {}
func check(_ yes: Bool, _ name: String) {
    guard yes else { fatalError("FAIL: \(name)") }
    print("PASS: \(name)")
}
let fixture = CommandLine.arguments[1]
let directory = CommandLine.arguments[2]
func run(_ mode: String, timeout: Double = 3) -> (OAuthCLI.RunResult, Double, Int32) {
    let pidPath = directory + "/" + mode + ".pid"
    let start = Date()
    let result = OAuthCLI.runGrok(URL(fileURLWithPath: "/usr/bin/python3"), [fixture, mode, pidPath], timeout: timeout)
    let elapsed = Date().timeIntervalSince(start)
    let pid = Int32((try? String(contentsOfFile: pidPath, encoding: .utf8)) ?? "") ?? 0
    return (result, elapsed, pid)
}
let (early, elapsed, earlyPID) = run("success")
check(early.code == 0 && early.out == "완성 결과", "complete terminal text only, fragmented NDJSON and stderr flood")
check(elapsed < 1.5 && kill(earlyPID, 0) == 0, "return before 2-second process teardown")
for mode in ["partial", "error", "truncated", "malformed", "empty", "limit", "oversized"] {
    let (result, _, _) = run(mode)
    check(result.code != 0 && result.out.isEmpty, "reject \(mode)")
}
let (timeout, _, hangingPID) = run("hang", timeout: 0.4)
check(timeout.code == 124, "timeout retains fallback")
Thread.sleep(forTimeInterval: 1)
check(hangingPID > 0 && kill(hangingPID, 0) != 0, "SIGTERM-resistant timed-out child reaped")
let (successHang, _, successPID) = run("success-hang", timeout: 0.4)
check(successHang.code == 0, "terminal success returned while child finishes")
Thread.sleep(forTimeInterval: 1.1)
check(successPID > 0 && kill(successPID, 0) != 0, "successful hung child bounded and reaped")
check(kill(earlyPID, 0) != 0, "normal successful child exited and reaped")
