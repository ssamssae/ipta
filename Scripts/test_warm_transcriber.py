#!/usr/bin/env python3
"""Exercise the real Swift process lifecycle with private fake child processes."""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HARNESS = r'''
import Foundation
struct MalgyeolInfo { static let modelURLOnDisk = URL(fileURLWithPath: "/missing") }
@main struct Tests {
    static func main() {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let model = root.appendingPathComponent("model")
        let cli = root.appendingPathComponent("cli")
        func make(_ name: String, timeout: Double = 3, idleTimeout: Double = 90) -> Transcriber {
            Transcriber(cliURL: cli, workerURL: root.appendingPathComponent(name), modelURL: model, timeout: timeout, idleTimeout: idleTimeout)
        }
        func run(_ t: Transcriber) -> String {
            let done = DispatchSemaphore(value: 0)
            var value = ""
            t.transcribe(wav: root.appendingPathComponent("audio.wav")) { result in
                switch result { case .success(let text): value = text; case .failure: value = "ERROR" }
                done.signal()
            }
            precondition(done.wait(timeout: .now() + 8) == .success, "hung transcription")
            return value
        }
        let reusable = make("worker")
        reusable.prepare()
        let first = run(reusable)
        precondition(first.hasPrefix("worker:"))
        precondition(run(reusable) == first, "worker was not reused")
        reusable.cancel()
        precondition(run(reusable) != first, "cancel did not replace worker")
        reusable.cancel()
        for name in ["missing", "broken", "crash", "hang"] {
            let t = make(name, timeout: 0.4)
            precondition(run(t) == "fallback", "fallback failed: \(name)")
            t.cancel()
        }
        let idle = make("worker", idleTimeout: 0.1)
        let beforeIdle = run(idle)
        Thread.sleep(forTimeInterval: 0.25)
        precondition(run(idle) != beforeIdle, "idle worker was not released")
        idle.cancel()
        let loading = make("hang", timeout: 5)
        loading.prepare()
        Thread.sleep(forTimeInterval: 0.1)
        loading.cancel()
        let start = Date()
        loading.prepare()
        loading.cancel()
        Thread.sleep(forTimeInterval: 0.2)
        precondition(Date().timeIntervalSince(start) < 1)
        let active = make("slow", timeout: 5)
        let callback = DispatchSemaphore(value: 0)
        active.transcribe(wav: root.appendingPathComponent("audio.wav")) { _ in callback.signal() }
        Thread.sleep(forTimeInterval: 0.15)
        active.cancel()
        precondition(callback.wait(timeout: .now() + 0.5) == .timedOut, "cancelled job called back")
        print("PASS reuse, idle release, cancel/restart, unavailable/malformed/crashed/timed-out worker fallback, cancel during loading and inference")
    }
}
'''
def main():
    with tempfile.TemporaryDirectory(prefix="ipta-warm-test-") as tmp:
        root = pathlib.Path(tmp)
        (root / "model").touch()
        scripts = {
            "worker": 'import os,sys,json\nprint(\'{"ready":true}\',flush=True)\nfor line in sys.stdin:\n print(json.dumps({"text":"worker:"+str(os.getpid())}),flush=True)\n',
            "broken": 'print("invalid",flush=True)\n',
            "crash": 'import sys\nprint(\'{"ready":true}\',flush=True)\nsys.stdin.readline()\nsys.exit(1)\n',
            "hang": 'import time\ntime.sleep(20)\n',
            "slow": 'import sys,time\nprint(\'{"ready":true}\',flush=True)\nsys.stdin.readline()\ntime.sleep(20)\n',
            "cli": 'print("fallback")\n',
        }
        for name, body in scripts.items():
            p = root / name
            p.write_text(f"#!{sys.executable}\n" + body)
            p.chmod(0o755)
        (root / "Harness.swift").write_text(HARNESS)
        subprocess.run(["swiftc", "-swift-version", "5", str(ROOT / "App/Sources/Transcriber.swift"), str(root / "Harness.swift"), "-o", str(root / "test")], check=True)
        subprocess.run([str(root / "test"), str(root)], check=True, timeout=25)


if __name__ == "__main__":
    main()
