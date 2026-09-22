"""Read a supported Windows UI Automation text selection without Ctrl+C."""
from __future__ import annotations
import base64
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from .winhide import hidden_kwargs

SCRIPT = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$e=[System.Windows.Automation.AutomationElement]::FocusedElement
if (!$e -or $e.Current.IsPassword) { exit }
$p=$e.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
$s=$p.GetSelection()
if ($s.Count -ne 1) { exit }
$t=$s[0].GetText(20001)
if (!$t -or $t.Length -gt 20000) { exit }
$r=$p.DocumentRange.Clone()
$r.MoveEndpointByRange([System.Windows.Automation.TextPatternRangeEndpoint]::End,$s[0],[System.Windows.Automation.TextPatternRangeEndpoint]::Start)
$prefix=$r.GetText(100001)
if ($prefix.Length -gt 100000) { exit }
$sha=[System.Security.Cryptography.SHA256]::Create()
$hash=[Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($prefix)))
@{text=$t; runtime=($e.GetRuntimeId() -join ','); pid=$e.Current.ProcessId; prefix=$hash} | ConvertTo-Json -Compress
'''


@dataclass(frozen=True)
class Selection:
    hwnd: int
    text: str
    runtime: str
    pid: int
    prefix: str


def capture(hwnd: int) -> Selection | None:
    if sys.platform != 'win32' or not hwnd: return None
    from . import paste
    if paste.foreground_hwnd()!=hwnd: return None
    import os
    powershell=Path(os.environ.get('SystemRoot',r'C:\Windows'))/'System32/WindowsPowerShell/v1.0/powershell.exe'
    try:
        proc=subprocess.run([str(powershell),'-NoProfile','-NonInteractive','-STA','-EncodedCommand',base64.b64encode(SCRIPT.encode('utf-16-le')).decode('ascii')],capture_output=True,timeout=3,**hidden_kwargs())
        if proc.returncode or len(proc.stdout)>150000 or paste.foreground_hwnd()!=hwnd: return None
        data=json.loads(proc.stdout.decode('utf-8-sig'))
        if not isinstance(data.get('text'),str) or not data['text'] or len(data['text'])>20000: return None
        return Selection(hwnd,data['text'],str(data['runtime']),int(data['pid']),str(data['prefix']))
    except (OSError,ValueError,KeyError,subprocess.TimeoutExpired): return None


def replace_if_unchanged(snapshot: Selection, text: str) -> bool:
    from . import paste
    if capture(snapshot.hwnd)!=snapshot: return False
    paste.copy_text(text)
    if paste.foreground_hwnd()!=snapshot.hwnd: return False
    import ctypes
    user=ctypes.windll.user32
    user.keybd_event(0x11,0,0,0); user.keybd_event(0x56,0,0,0)
    user.keybd_event(0x56,0,2,0); user.keybd_event(0x11,0,2,0)
    return True
