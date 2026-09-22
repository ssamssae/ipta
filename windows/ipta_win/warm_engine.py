"""Private persistent whisper worker, with bounded lifetime and CLI fallback."""
from __future__ import annotations
import atexit
import json
import queue
import subprocess
import threading
from pathlib import Path
from .winhide import hidden_kwargs


class WarmEngine:
    def __init__(self, worker: Path, model: Path, timeout=60.0, idle_timeout=90.0, command=None):
        self.worker, self.model = worker, model
        self.command = command or [str(worker), str(model)]
        self.timeout, self.idle_timeout = timeout, idle_timeout
        self._lock = threading.Lock()
        self._proc = None
        self._responses = None
        self._idle = None
        self._idle_generation = 0
        atexit.register(self.cancel)

    def _stop(self):
        self._idle_generation += 1
        if self._idle:
            self._idle.cancel(); self._idle = None
        proc, self._proc = self._proc, None
        if proc:
            try:
                if proc.poll() is None: proc.kill()
                proc.wait(timeout=3)
            except (OSError, subprocess.TimeoutExpired): pass
            for stream in (proc.stdin, proc.stdout):
                if stream:
                    try: stream.close()
                    except OSError: pass

    def cancel(self):
        # Kill first to unblock a thread currently waiting for inference/ready.
        proc = self._proc
        if proc and proc.poll() is None:
            try: proc.kill()
            except OSError: pass
        with self._lock: self._stop()

    def _arm_idle(self):
        if self._idle: self._idle.cancel()
        # The timer never kills active inference; it acquires the request lock.
        self._idle_generation += 1
        self._idle = threading.Timer(self.idle_timeout, self._expire, args=(self._idle_generation,))
        self._idle.daemon = True
        self._idle.start()

    def _expire(self, generation):
        with self._lock:
            if generation == self._idle_generation: self._stop()

    def _read(self, proc, responses):
        try:
            while line := proc.stdout.readline(1_000_001):
                if len(line) > 1_000_000: break
                responses.put(json.loads(line))
        except (OSError, ValueError): pass
        finally: responses.put({'error': 'worker_closed'})

    def _receive(self):
        try: value = self._responses.get(timeout=self.timeout)
        except queue.Empty: raise RuntimeError('음성 인식 엔진 응답 시간 초과')
        if not isinstance(value, dict) or value.get('error'): raise RuntimeError('음성 인식 엔진 응답 실패')
        return value

    def _ready(self):
        if self._proc and self._proc.poll() is None: return
        self._stop()
        self._proc = subprocess.Popen(self.command, stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                      cwd=str(self.worker.parent), **hidden_kwargs())
        self._responses = queue.Queue()
        threading.Thread(target=self._read, args=(self._proc, self._responses), daemon=True).start()
        if self._receive().get('ready') is not True: raise RuntimeError('음성 인식 엔진 준비 실패')

    def prepare(self):
        with self._lock:
            try: self._ready(); self._arm_idle()
            except (OSError, RuntimeError): self._stop()

    def transcribe(self, wav: Path) -> str:
        with self._lock:
            if self._idle: self._idle.cancel()
            self._idle_generation += 1
            try:
                self._ready()
                self._proc.stdin.write((json.dumps({'wav': str(wav)})+'\n').encode('utf-8'))
                self._proc.stdin.flush()
                value = self._receive().get('text')
                if not isinstance(value, str): raise RuntimeError('음성 인식 결과 형식 오류')
                self._arm_idle()
                return value.strip()
            except (OSError, RuntimeError):
                self._stop(); raise
