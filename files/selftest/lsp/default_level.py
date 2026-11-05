"""Self-test: what level does basedpyright check at when an EDITOR starts it, with no project config?

This is the bug class "installed and starts, but unusable": basedpyright's own default level ("recommended") is so
strict that ordinary working code shows a page of errors in Kate and Helix. The setup gives the editors a default of
"standard" through the language-server settings. This script speaks LSP to basedpyright-langserver the way Kate does,
in both of its ways:
  didchange     Kate 23.08 (Ubuntu 24.04): sends workspace/didChangeConfiguration {"settings": ...} after start
  configuration Kate 25.12 (Ubuntu 26.04): declares workspace/configuration and answers it from "settings"
and checks the diagnostics for a small, untyped, perfectly working file.

usage: default_level.py MODE SETTINGS_JSON      MODE = didchange | configuration
       SETTINGS_JSON "none" = send no settings (the control: this must be strict, or the test proves nothing)
exit: 0 = quiet (standard level), 1 = noisy, 2 = no answer / protocol problem, 3 = strict (the control, expected)
"""
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time

SAMPLE = '''import os


def add(a, b):
    return a + b


data = {}
print(add(1, 2), data)
'''


def main():
    mode, raw = sys.argv[1], sys.argv[2]
    settings = None if raw == "none" else json.loads(raw)
    root = tempfile.mkdtemp(prefix="lspdefault-")  # a project with NO pyrightconfig.json / pyproject.toml
    path = os.path.join(root, "sample.py")
    with open(path, "w") as fh:
        fh.write(SAMPLE)
    uri = "file://" + path
    proc = subprocess.Popen(["basedpyright-langserver", "--stdio"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, cwd=root)

    def send(msg):
        body = json.dumps(msg).encode()
        proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        proc.stdin.flush()

    def read():
        header = b""
        while not header.endswith(b"\r\n\r\n"):
            ch = proc.stdout.read(1)
            if not ch:
                return None
            header += ch
        length = int([h for h in header.decode().split("\r\n") if h.lower().startswith("content-length")][0].split(":")[1])
        return json.loads(proc.stdout.read(length))

    def section(name):  # what Kate 25.12 does for workspace/configuration: walk the dotted section in "settings"
        value = settings
        for part in name.split("."):
            value = value.get(part) if isinstance(value, dict) else None
        return value

    # A reader thread: the server's messages arrive whenever it likes, and "nothing more for a while" must be noticeable.
    inbox = queue.Queue()

    def pump():
        while True:
            msg = read()
            inbox.put(msg)
            if msg is None:
                return

    def get(timeout):
        try:
            return inbox.get(timeout=timeout)
        except queue.Empty:
            return "idle"

    caps = {"textDocument": {"publishDiagnostics": {}}}
    if mode == "configuration":
        caps["workspace"] = {"configuration": True}
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": {"processId": os.getpid(), "rootUri": "file://" + root, "capabilities": caps}})
    threading.Thread(target=pump, daemon=True).start()
    deadline = time.time() + 90
    while True:
        if time.time() > deadline:
            proc.kill()
            return 2
        msg = get(1)
        if msg is None:
            return 2
        if msg != "idle" and msg.get("id") == 1 and "result" in msg:
            break
    send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    if mode == "didchange" and settings is not None:
        send({"jsonrpc": "2.0", "method": "workspace/didChangeConfiguration", "params": {"settings": settings}})
    send({"jsonrpc": "2.0", "method": "textDocument/didOpen",
          "params": {"textDocument": {"uri": uri, "languageId": "python", "version": 1, "text": SAMPLE}}})

    diagnostics = None
    last = time.time()
    deadline = time.time() + 90
    while time.time() < deadline:
        msg = get(1)
        if msg is None:
            break
        if msg == "idle":
            if diagnostics is not None and time.time() - last > 8:   # it said something and has been quiet since: done
                break
            continue
        method = msg.get("method")
        if method == "workspace/configuration" and "id" in msg:      # a request from the server: answer it like Kate
            items = msg["params"]["items"]
            result = [section(i.get("section", "")) if settings is not None else None for i in items]
            send({"jsonrpc": "2.0", "id": msg["id"], "result": result})
        elif method in ("client/registerCapability", "window/workDoneProgress/create") and "id" in msg:
            send({"jsonrpc": "2.0", "id": msg["id"], "result": None})
        elif method == "textDocument/publishDiagnostics" and msg["params"]["uri"] == uri:
            diagnostics = msg["params"]["diagnostics"]
            last = time.time()
            if diagnostics:
                break
    send({"jsonrpc": "2.0", "id": 99, "method": "shutdown", "params": None})
    send({"jsonrpc": "2.0", "method": "exit"})
    proc.kill()
    if diagnostics is None:
        return 2
    # Errors and warnings are what the editor shows in red and yellow; hints (grayed-out unused code) are fine at any level.
    diagnostics = [d for d in diagnostics if d.get("severity", 1) in (1, 2)]
    rules = sorted({d.get("code") for d in diagnostics if d.get("code")})
    print(f"{mode} settings={raw}: {len(diagnostics)} diagnostic(s) for a small untyped but working file: {', '.join(rules) or 'none'}")
    if settings is None:
        return 3 if diagnostics else 0
    return 1 if diagnostics else 0


if __name__ == "__main__":
    sys.exit(main())
