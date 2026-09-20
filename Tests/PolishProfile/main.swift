import Foundation

enum PolishProvider: String {
    case apple, claude, grok, openai, cursor, local
    var supportsOAuth: Bool { self != .apple && self != .local }
    var title: String { rawValue }
    var missingProgramNote: String { "missing" }
}
func malgyeolLog(_ message: String) {}

func configuration(model: String = "grok-4.6", effort: String = "high", fast: String = "true") -> Data {
    try! JSONSerialization.data(withJSONObject: ["selectedModel": ["modelId": model, "parameters": [["id": "effort", "value": effort], ["id": "fast", "value": fast]]]])
}
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("FAIL: \(name)") }
    print("PASS: \(name)")
}
check(OAuthCLI.cursorPolishModel(configuration: configuration()) == "cursor-grok-4.6-low-fast", "same Grok 4.6 and Fast tier")
check(OAuthCLI.cursorPolishModel(configuration: configuration(model: "claude-opus-4-8")) == nil, "unmeasured model unchanged")
check(OAuthCLI.cursorPolishModel(configuration: configuration(fast: "false")) == nil, "never enable paid Fast tier")
check(OAuthCLI.cursorPolishModel(configuration: configuration(effort: "low")) == nil, "already low unchanged")
check(OAuthCLI.cursorPolishModel(configuration: Data("{}".utf8)) == nil, "missing selection unchanged")
check(OAuthCLI.cursorPolishModel(configuration: Data("invalid".utf8)) == nil, "invalid config unchanged")
check(OAuthCLI.cursorConfigurationDirectory(environment: ["CURSOR_CONFIG_DIR": "/tmp/selected", "XDG_CONFIG_HOME": "/tmp/ignored"]).path == "/tmp/selected", "existing config override respected")
check(OAuthCLI.cursorConfigurationDirectory(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"]).path == "/tmp/xdg/cursor", "XDG config respected")
let args = OAuthCLI.arguments(provider: .cursor, prompt: "text & $(example)")
check(args.contains("ask") && !args.contains("--force") && !args.contains("--yolo"), "read-only ask retained")
check(args.last == "text & $(example)", "dictated text stays one argument")
check(OAuthCLI.arguments(provider: .openai, prompt: "text") == ["exec", "--ephemeral", "--skip-git-repo-check", "-s", "read-only", "text"], "Codex path unchanged after inconclusive timing")
