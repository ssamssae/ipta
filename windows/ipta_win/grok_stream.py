"""Return only a completed Grok result; reap the owned CLI separately."""
from __future__ import annotations
import json
import subprocess
import threading
import queue
from collections.abc import Callable
from .winhide import hidden_kwargs

LIMIT = 1_000_000


def run(argv: list[str], timeout: float, *, environment=None, cwd=None, cleanup: Callable[[], None] | None = None) -> str:
    from .oauth import CliFailure, _kill_process_tree
    try:
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=environment, cwd=cwd, **hidden_kwargs())
    except OSError:
        if cleanup: cleanup()
        raise CliFailure('launch')
    result: queue.Queue = queue.Queue(maxsize=1)

    def publish(value):
        try: result.put_nowait(value)
        except queue.Full: pass

    def read_output():
        try:
            while line := proc.stdout.readline(LIMIT + 1):
                if len(line) > LIMIT:
                    publish(CliFailure('invalid_output')); return
                try: obj = json.loads(line)
                except (ValueError, UnicodeError): continue
                if not isinstance(obj, dict) or obj.get('type') != 'result': continue
                text = obj.get('result')
                if (obj.get('subtype') == 'success' and obj.get('is_error') is False
                        and obj.get('stop_reason') == 'end_turn' and isinstance(text, str) and text.strip()):
                    publish(text.strip()); return
                publish(CliFailure('invalid_output')); return
            publish(CliFailure('invalid_output'))
        except (OSError, ValueError): publish(CliFailure('execution'))
        finally:
            # Drain trailing output so an otherwise normal child can exit.
            try:
                while proc.stdout.read(65536): pass
            except (OSError, ValueError): pass

    def drain_errors():
        try:
            while proc.stderr.read(65536): pass
        except (OSError, ValueError): pass

    def reap():
        try:
            try: proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                _kill_process_tree(proc)
                proc.wait(timeout=3)
        except (OSError, subprocess.TimeoutExpired): pass
        finally:
            reader.join(timeout=1); errors.join(timeout=1)
            for stream in (proc.stdout, proc.stderr):
                try: stream.close()
                except OSError: pass
            if cleanup: cleanup()

    reader = threading.Thread(target=read_output, daemon=True)
    errors = threading.Thread(target=drain_errors, daemon=True)
    reader.start(); errors.start()
    try:
        try: value = result.get(timeout=timeout)
        except queue.Empty: raise CliFailure('timeout')
        if isinstance(value, Exception): raise value
        return json.dumps({'text': value}, ensure_ascii=False)
    finally:
        threading.Thread(target=reap, daemon=True).start()
