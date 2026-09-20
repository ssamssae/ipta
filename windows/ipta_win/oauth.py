from __future__ import annotations

import json
import base64
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import webbrowser
from dataclasses import dataclass
from pathlib import Path

from . import polish
from .winhide import CREATE_NO_WINDOW, hidden_kwargs

BINARY_NAMES = {
    "claude": ("claude.cmd", "claude.exe", "claude"),
    "openai": ("codex.cmd", "codex.exe", "codex"),
    "grok": ("grok.exe", "grok.cmd", "grok"),
    "cursor": ("agent.cmd", "agent.exe", "cursor-agent.cmd", "cursor-agent.exe", "agent", "cursor-agent"),
}

WSL_COMMANDS = {
    "claude": "claude",
    "openai": "codex",
    "grok": "grok",
    "cursor": "agent",
}

LOGIN_ARGS = {
    "grok": ["login", "--oauth"],
    "cursor": ["login"],
    "claude": ["auth", "login"],
    "openai": ["login"],
}

CREATE_NEW_CONSOLE = 0x00000010
CREATE_NEW_PROCESS_GROUP = 0x00000200
CLI_TIMEOUT = 25
GROK_TIMEOUT = 15


class CliFailure(RuntimeError):
    def __init__(self, reason: str):
        self.reason = reason
        super().__init__(reason)


def search_directories(home: Path | None = None) -> list[Path]:
    home = home or Path.home()
    local_app = Path(os.environ.get("LOCALAPPDATA") or (home / "AppData" / "Local"))
    roaming = Path(os.environ.get("APPDATA") or (home / "AppData" / "Roaming"))
    return [
        home / ".local" / "bin",
        roaming / "npm",
        local_app / "Programs" / "cursor" / "resources" / "app" / "bin",
        local_app / "Programs" / "Claude",
        Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "cursor" / "resources" / "app" / "bin",
        Path("/usr/local/bin"),
        Path("/opt/homebrew/bin"),
    ]


def _usable_binary(path: Path) -> bool:
    if not path.is_file():
        return False
    if sys.platform != "win32":
        return True
    suffix = path.suffix.lower()
    if suffix in {".cmd", ".bat", ".exe", ".com"}:
        return True
    try:
        head = path.read_bytes()[:2]
    except OSError:
        return False
    return head == b"MZ"


def binary(provider: str, home: Path | None = None, path_env: str | None = None) -> Path | None:
    # Windows UI uses the user's WSL CLI/account when that provider is installed there.
    if sys.platform == "win32" and wsl_command_exists(WSL_COMMANDS.get(provider, "")):
        return None
    # Prefer the packaged executable over cmd.exe so dictated shell characters stay data.
    if provider == "openai" and sys.platform == "win32":
        root = Path(os.environ.get("APPDATA") or ((home or Path.home()) / "AppData" / "Roaming")) / "npm/node_modules/@openai/codex/node_modules/@openai"
        for candidate in sorted(root.glob("codex-win32-*/vendor/*/bin/codex.exe")):
            if candidate.is_file():
                return candidate
    names = BINARY_NAMES.get(provider, ())
    for directory in search_directories(home):
        for name in names:
            candidate = directory / name
            if _usable_binary(candidate):
                return candidate
    path = path_env if path_env is not None else os.environ.get("PATH", "")
    for name in names:
        found = shutil.which(name, path=path)
        if found and _usable_binary(Path(found)):
            return Path(found)
    return None


def wsl_exe() -> str | None:
    root = os.environ.get("SystemRoot") or os.environ.get("WINDIR") or r"C:\Windows"
    candidate = Path(root) / "System32" / "wsl.exe"
    if candidate.is_file():
        return str(candidate)
    return shutil.which("wsl.exe") or shutil.which("wsl")


def wsl_command_exists(name: str) -> bool:
    exe = wsl_exe()
    if not exe or not name:
        return False
    try:
        proc = subprocess.run(
            [exe, "-e", "bash", "-lc", f"command -v {shlex.quote(name)}"],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
            **hidden_kwargs(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return proc.returncode == 0 and bool((proc.stdout or "").strip())


def wsl_run(name: str, args: list[str], timeout: float = 8) -> str:
    exe = wsl_exe()
    if not exe or not name:
        return ""
    cmd = " ".join([name, *[shlex.quote(a) for a in args]])
    try:
        proc = subprocess.run(
            [exe, "-e", "bash", "-lc", cmd],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            **hidden_kwargs(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return (proc.stdout or "") + "\n" + (proc.stderr or "")


def wsl_home_file_exists(rel: str) -> bool:
    exe = wsl_exe()
    if not exe:
        return False
    try:
        proc = subprocess.run(
            [exe, "-e", "bash", "-lc", f'test -f "$HOME/{shlex.quote(rel)}"'],
            capture_output=True,
            timeout=8,
            check=False,
            **hidden_kwargs(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return proc.returncode == 0


@dataclass
class Probe:
    ready: bool
    blocked: bool
    note: str


def parse_cursor_status(raw: str) -> Probe:
    lower = raw.lower()
    if "keychain is locked" in lower or "unlock-keychain" in lower:
        return Probe(False, True, "이 컴퓨터 열쇠묶음이 잠겨 커서 로그인을 못 봅니다.")
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError:
        obj = None
    if isinstance(obj, dict) and isinstance(obj.get("isAuthenticated"), bool):
        if obj["isAuthenticated"]:
            return Probe(True, False, "이 컴퓨터 커서에 이미 붙어 있습니다")
        return Probe(False, False, "아직 커서에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
    if "not logged in" in lower or "logged out" in lower:
        return Probe(False, False, "아직 커서에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
    if "logged in" in lower:
        return Probe(True, False, "이 컴퓨터 커서에 이미 붙어 있습니다")
    return Probe(False, False, "커서 로그인을 확인하지 못했습니다")


def _run(bin_path: Path, args: list[str], timeout: float = 6) -> str:
    try:
        proc = subprocess.run(
            [str(bin_path), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            **hidden_kwargs(),
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return (proc.stdout or "") + "\n" + (proc.stderr or "")


def _popen_visible(argv: list[str]) -> None:
    kwargs: dict[str, object] = {}
    if sys.platform == "win32":
        kwargs["creationflags"] = CREATE_NEW_CONSOLE
    else:
        kwargs["stdin"] = subprocess.DEVNULL
        kwargs["stdout"] = subprocess.DEVNULL
        kwargs["stderr"] = subprocess.DEVNULL
    subprocess.Popen(argv, **kwargs)


def _popen_wsl_login(exe: str, cmd: str) -> None:
    wrapped = 'BROWSER="/mnt/c/Windows/System32/cmd.exe /c start" ' + cmd
    kwargs: dict[str, object] = {
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
    }
    if sys.platform == "win32":
        kwargs["creationflags"] = CREATE_NO_WINDOW
    subprocess.Popen([exe, "-e", "bash", "-lc", wrapped], **kwargs)


def _open_install_page(provider: str) -> str:
    url = polish.INSTALL_URLS.get(provider) or ""
    if url:
        webbrowser.open(url)
        return (
            polish.missing_program_note(provider)
            + "\n받는 곳을 브라우저에 열었습니다."
        )
    return polish.missing_program_note(provider)


def probe(provider: str, home: Path | None = None) -> Probe:
    if not polish.supports_oauth(provider):
        return Probe(False, True, "이 모델은 이 컴퓨터 로그인을 쓰지 않습니다")
    bin_path = binary(provider, home=home)
    wsl_name = WSL_COMMANDS.get(provider, "")
    wsl_ok = wsl_command_exists(wsl_name)
    if bin_path is None and not wsl_ok:
        return Probe(False, True, polish.missing_program_note(provider))
    home = home or Path.home()
    if provider == "claude":
        if bin_path is not None:
            out = _run(bin_path, ["auth", "status", "--json"], timeout=5)
        elif wsl_ok:
            out = wsl_run("claude", ["auth", "status", "--json"], timeout=8)
        else:
            out = ""
        compact = out.replace(" ", "")
        if '"loggedIn":true' in compact:
            return Probe(True, False, "이 컴퓨터 클로드에 이미 붙어 있습니다")
        return Probe(False, False, "아직 클로드에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
    if provider == "openai":
        out = (_run(bin_path, ["login", "status"], timeout=5) if bin_path else wsl_run("codex", ["login", "status"], timeout=8) if wsl_ok else "").lower()
        if "logged in" in out and "not logged in" not in out and "logged out" not in out:
            return Probe(True, False, "이 컴퓨터 코덱스에 이미 붙어 있습니다")
        return Probe(False, False, "아직 코덱스에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
    if provider == "grok":
        auth = home / ".grok" / "auth.json"
        if auth.is_file() or wsl_home_file_exists(".grok/auth.json"):
            return Probe(True, False, "이 컴퓨터 그록에 이미 붙어 있습니다")
        return Probe(False, False, "아직 그록에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
    if provider == "cursor":
        if bin_path is not None:
            return parse_cursor_status(_run(bin_path, ["status", "--format", "json"], timeout=6))
        if wsl_ok:
            return parse_cursor_status(wsl_run("agent", ["status", "--format", "json"], timeout=8))
        return Probe(False, False, "아직 커서에 안 붙어 있습니다. 로그인 버튼을 누르면 브라우저가 열립니다")
    return Probe(False, True, "")


def start_login(provider: str, home: Path | None = None) -> str:
    if not polish.supports_oauth(provider):
        return "이 모델은 로그인 창이 없습니다"
    already = probe(provider, home=home)
    if already.ready:
        return already.note
    args = LOGIN_ARGS.get(provider) or []
    if not args:
        return "로그인 명령을 모릅니다"
    bin_path = binary(provider, home=home)
    if bin_path is not None:
        try:
            _popen_visible([str(bin_path), *args])
        except OSError:
            return f"{polish.title(provider)} 로그인 창을 열지 못했습니다"
        return f"{polish.title(provider)} 로그인 창을 열었습니다"
    wsl_name = WSL_COMMANDS.get(provider, "")
    exe = wsl_exe()
    if exe and wsl_command_exists(wsl_name):
        cmd = " ".join([wsl_name, *[shlex.quote(a) for a in args]])
        try:
            _popen_wsl_login(exe, cmd)
        except OSError:
            return f"{polish.title(provider)} 로그인 창을 열지 못했습니다"
        return f"{polish.title(provider)} 로그인 창을 열었습니다"
    return _open_install_page(provider)


def decode_cli_output(raw: bytes | None) -> str:
    return (raw or b"").decode("utf-8", errors="replace")


def _kill_process_tree(proc: subprocess.Popen[bytes]) -> None:
    if sys.platform == "win32":
        subprocess.run(
            ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
            capture_output=True,
            check=False,
            **hidden_kwargs(),
        )
        return
    proc.kill()


def run_cli(argv: list[str], timeout: float = CLI_TIMEOUT, *, raise_errors: bool = False, environment: dict[str, str] | None = None, cwd: str | None = None) -> str | None:
    extra: dict[str, object] = {
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
    }
    if environment is not None:
        extra["env"] = environment
    if cwd is not None:
        extra["cwd"] = cwd
    if sys.platform == "win32":
        extra["creationflags"] = CREATE_NEW_PROCESS_GROUP
    kwargs = hidden_kwargs(extra)
    try:
        proc = subprocess.Popen(argv, **kwargs)
    except OSError:
        if raise_errors:
            raise CliFailure("launch")
        return None
    try:
        out, _err = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        _kill_process_tree(proc)
        try:
            proc.communicate(timeout=3)
        except Exception:
            pass
        if raise_errors:
            raise CliFailure("timeout")
        return None
    except Exception:
        _kill_process_tree(proc)
        if raise_errors:
            raise CliFailure("execution")
        return None
    if proc.returncode != 0:
        if raise_errors:
            error = decode_cli_output(_err).lower()
            reason = "timeout" if proc.returncode == 124 else "auth" if any(x in error for x in ("unauthorized", "not logged in", "token expired", "authentication failed")) else "execution"
            raise CliFailure(reason)
        return None
    return decode_cli_output(out).strip() or None


def strip_fences(text: str) -> str:
    if not text.startswith("```"):
        return text
    lines = text.splitlines()
    if lines and lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].startswith("```"):
        lines = lines[:-1]
    return "\n".join(lines).strip()


def grok_environment() -> dict[str, str]:
    values = {"GROK_MEMORY": "0", "GROK_WORKFLOWS": "0"}
    for vendor in ("CLAUDE", "CURSOR"):
        for kind in ("AGENTS", "RULES", "SKILLS", "MCPS", "HOOKS"):
            values[f"GROK_{vendor}_{kind}_ENABLED"] = "0"
    return values


def polish_grok(instructions: str, user: str, bin_path: Path | None) -> str | None:
    with tempfile.TemporaryDirectory(prefix="ipta-polish-") as directory:
        profile = Path(directory) / "agent.md"
        profile.write_text("---\nname: ipta-polish\ndescription: Korean dictation cleanup\ntools: []\n---\n" + instructions, encoding="utf-8")
        flags = ["-p", user, "--tools", "", "--disable-web-search", "--no-subagents", "--max-turns", "1", "--reasoning-effort", "low", "--output-format", "json"]
        env = os.environ.copy()
        env.update(grok_environment())
        if bin_path is not None:
            raw = run_cli([str(bin_path), "--agent", str(profile), *flags], timeout=GROK_TIMEOUT, raise_errors=True, environment=env, cwd=directory)
        else:
            exe = wsl_exe()
            if not exe:
                raise CliFailure("launch")
            encoded = base64.b64encode(profile.read_bytes()).decode("ascii")
            prefix = ["env", *[f"{k}={v}" for k,v in grok_environment().items()], "timeout", "--kill-after=2s", f"{GROK_TIMEOUT}s", "grok"]
            command = (
                "ipta_profile_dir=$(mktemp -d /tmp/ipta-polish.XXXXXX) || exit 1; "
                "trap 'rm -f \"$ipta_profile_dir/agent.md\"; rmdir \"$ipta_profile_dir\"' EXIT; "
                "printf %s " + shlex.quote(encoded) + " | base64 -d > \"$ipta_profile_dir/agent.md\" || exit 1; "
                "cd \"$ipta_profile_dir\" && " + " ".join(shlex.quote(a) for a in prefix)
                + " --agent \"$ipta_profile_dir/agent.md\" " + " ".join(shlex.quote(a) for a in flags)
            )
            raw = run_cli([exe, "-e", "bash", "-lc", command], timeout=GROK_TIMEOUT + 2, raise_errors=True)
        try:
            obj = json.loads(raw or "")
        except (ValueError, TypeError):
            raise CliFailure("invalid_output")
        text = obj.get("text") if isinstance(obj, dict) else None
        if not isinstance(text, str):
            raise CliFailure("invalid_output")
        return strip_fences(text) or None


def polish_cursor(args: list[str], bin_path: Path | None) -> str | None:
    if bin_path is not None:
        with tempfile.TemporaryDirectory(prefix="ipta-cursor-") as directory:
            raw = run_cli([str(bin_path), *args[1:], "--workspace", directory, "--trust"], timeout=CLI_TIMEOUT, raise_errors=True, cwd=directory)
    else:
        exe = wsl_exe()
        if not exe:
            raise CliFailure("launch")
        # The trust override is confined to a newly created empty directory, never /tmp or HOME.
        command = (
            "ipta_cursor_dir=$(mktemp -d /tmp/ipta-cursor.XXXXXX) || exit 1; "
            "trap 'rm -rf -- \"$ipta_cursor_dir\"' EXIT; "
            "cd \"$ipta_cursor_dir\" && timeout --kill-after=2s " + str(CLI_TIMEOUT) + "s "
            + " ".join(shlex.quote(a) for a in args)
            + " --workspace \"$ipta_cursor_dir\" --trust"
        )
        raw = run_cli([exe, "-e", "bash", "-lc", command], timeout=CLI_TIMEOUT + 2, raise_errors=True)
    return strip_fences(raw) if raw else None


def polish_via_cli(provider: str, instructions: str, user: str, key: str = "", home: Path | None = None) -> str | None:
    prompt = f"{instructions}\n\n글:\n{user}"
    if provider == "claude":
        args = ["claude", "-p", prompt, "--output-format", "text", "--permission-mode", "dontAsk"]
    elif provider == "openai":
        args = ["codex", "exec", "--ephemeral", "--skip-git-repo-check", "-s", "read-only", prompt]
    elif provider == "grok":
        args = ["grok", "-p", user, "--disable-web-search", "--tools", "",
                "--no-subagents", "--max-turns", "1", "--reasoning-effort", "low",
                "--system-prompt-override", instructions, "--output-format", "json"]
    elif provider == "cursor":
        args = ["agent", "-p", "--mode", "ask", "--output-format", "text", prompt]
        if key.strip():
            args = ["agent", "--api-key", key.strip(), "-p", "--mode", "ask", "--output-format", "text", prompt]
    else:
        return None
    already = probe(provider, home=home)
    if not already.ready:
        raise CliFailure("auth_unavailable")
    timeout = CLI_TIMEOUT
    bin_path = binary(provider, home=home)
    if provider == "grok":
        return polish_grok(instructions, user, bin_path)
    if provider == "cursor":
        return polish_cursor(args, bin_path)
    try:
        if bin_path is not None:
            with tempfile.TemporaryDirectory(prefix="ipta-cli-") as directory:
                raw = run_cli([str(bin_path), *args[1:]], timeout=timeout, raise_errors=True, cwd=directory)
        else:
            exe = wsl_exe()
            if not exe or not wsl_command_exists(args[0]):
                return None
            command = (
                "ipta_cli_dir=$(mktemp -d /tmp/ipta-cli.XXXXXX) || exit 1; "
                "trap 'rm -rf -- \"$ipta_cli_dir\"' EXIT; "
                "cd \"$ipta_cli_dir\" && timeout --kill-after=2s " + str(timeout) + "s "
                + " ".join(shlex.quote(a) for a in args)
            )
            raw = run_cli([exe, "-e", "bash", "-lc", command], timeout=timeout + 2, raise_errors=True)
    except CliFailure:
        raise
    except Exception:
        raise CliFailure("execution")
    if not raw:
        return None
    if provider == "grok":
        try:
            obj = json.loads(raw)
        except (ValueError, TypeError):
            raise CliFailure("invalid_output")
        raw = obj.get("text") if isinstance(obj, dict) else None
        if not isinstance(raw, str):
            raise CliFailure("invalid_output")
    return strip_fences(raw) or None
