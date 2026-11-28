import json
import os
import subprocess
import sys
import tempfile

code = '''!void main() {
    HashMap<str, i64> values = HashMap<str, i64>::init(c_allocator());
    for (auto [key, value] : values.iter(), auto n : 0..2) {
        println(key, value, n);
    }
    values.deinit();
}
'''

with tempfile.TemporaryDirectory() as directory:
    path = os.path.join(directory, "main.zk")
    with open(path, "w", encoding="utf-8") as f:
        f.write(code)
    proc = subprocess.Popen([os.path.abspath(sys.argv[1]), "lsp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    def send(msg):
        data = json.dumps(msg).encode()
        proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(data) + data)
        proc.stdin.flush()

    def receive():
        header = b""
        while not header.endswith(b"\r\n\r\n"):
            byte = proc.stdout.read(1)
            if not byte:
                raise RuntimeError("LSP exited")
            header += byte
        length = int(next(line for line in header.decode().split("\r\n") if line.lower().startswith("content-length:")).split(":")[1])
        return json.loads(proc.stdout.read(length))

    def response(request_id):
        while True:
            msg = receive()
            if msg.get("id") == request_id:
                return msg

    send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"rootUri": "file://" + directory, "capabilities": {}}})
    response(1)
    send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": "file://" + path, "languageId": "zark", "version": 1, "text": code}}})
    line = code.splitlines()[3]
    for request_id, (name, expected) in enumerate((("key", "str"), ("value", "i64"), ("n", "i64")), 2):
        character = line.index(name, line.index("(") + 1)
        send({"jsonrpc": "2.0", "id": request_id, "method": "textDocument/hover", "params": {"textDocument": {"uri": "file://" + path}, "position": {"line": 3, "character": character}}})
        result = response(request_id).get("result")
        assert result and f"const {expected} {name}" in result["contents"]["value"], (name, result)
    send({"jsonrpc": "2.0", "id": 5, "method": "shutdown", "params": {}})
    response(5)
    send({"jsonrpc": "2.0", "method": "exit", "params": {}})
    proc.wait(timeout=5)
print("ok   iterator LSP types")
