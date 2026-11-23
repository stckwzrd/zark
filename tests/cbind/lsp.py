import json
import subprocess
import sys

zark, path, cwd = sys.argv[1:4]
p = subprocess.Popen([zark, "lsp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, cwd=cwd)


def send(m):
    b = json.dumps(m).encode()
    p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b)
    p.stdin.flush()


def recv():
    h = b""
    while not h.endswith(b"\r\n\r\n"):
        c = p.stdout.read(1)
        if not c:
            return None
        h += c
    n = int([l for l in h.decode().split("\r\n") if l.lower().startswith("content-length")][0].split(":")[1])
    return json.loads(p.stdout.read(n))


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"rootUri": "file://" + cwd, "capabilities": {}}})
recv()
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
text = open(path).read()
send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": "file://" + path, "languageId": "zark", "version": 1, "text": text}}})
while True:
    m = recv()
    if m is None:
        sys.exit(1)
    if m.get("method") == "textDocument/publishDiagnostics":
        for d in m["params"]["diagnostics"]:
            print(d["message"])
        break
send({"jsonrpc": "2.0", "id": 2, "method": "shutdown"})
send({"jsonrpc": "2.0", "method": "exit"})
p.wait(timeout=10)
