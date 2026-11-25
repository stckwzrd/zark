#!/usr/bin/env python3
"""Mutation fuzzer for `zark lsp`.

Sends initialize/didOpen/didChange and hover/completion/definition requests
with mutated source text over JSON-RPC and checks that the server answers and
does not exit or panic.

usage: tools/fuzz_lsp.py [--count N] [--seed N] [--quick] [--keep]
                         [--zark PATH] [--timeout SEC]
"""

import argparse
import json
import os
import random
import select
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fuzz_crash  # noqa: E402


class Timeout(Exception):
    pass


class Eof(Exception):
    pass


def send(p, obj):
    body = json.dumps(obj, separators=(",", ":")).encode()
    p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    p.stdin.flush()


def read_line(p, deadline):
    buf = b""
    while True:
        rem = deadline - time.monotonic()
        if rem <= 0:
            raise Timeout()
        r, _, _ = select.select([p.stdout], [], [], rem)
        if not r:
            raise Timeout()
        b = p.stdout.read(1)
        if not b:
            raise Eof()
        buf += b
        if b == b"\n":
            return buf


def read_exact(p, n, deadline):
    buf = b""
    while len(buf) < n:
        rem = deadline - time.monotonic()
        if rem <= 0:
            raise Timeout()
        r, _, _ = select.select([p.stdout], [], [], rem)
        if not r:
            raise Timeout()
        chunk = p.stdout.read(n - len(buf))
        if not chunk:
            raise Eof()
        buf += chunk
    return buf


def read_message(p, deadline):
    headers = {}
    while True:
        line = read_line(p, deadline)
        if line in (b"\r\n", b"\n"):
            break
        k, _, v = line.decode("utf-8", "replace").partition(":")
        headers[k.strip().lower()] = v.strip()
    n = int(headers.get("content-length", "0"))
    body = read_exact(p, n, deadline)
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        raise ValueError("bad json")


def wait_id(p, want, deadline):
    while True:
        msg = read_message(p, deadline)
        if msg.get("id") == want:
            return msg


def session(zark, base, text, rng, timeout):
    uri = "file://" + base
    lines = text.split("\n")
    def pos():
        ln = rng.randrange(len(lines))
        ch = rng.randrange(len(lines[ln]) + 1)
        return {"line": ln, "character": ch}

    p = subprocess.Popen([zark, "lsp"], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         bufsize=0)
    why = None
    try:
        dl = time.monotonic() + timeout
        send(p, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                 "params": {"processId": None, "rootUri": None, "capabilities": {}}})
        wait_id(p, 1, dl)
        send(p, {"jsonrpc": "2.0", "method": "initialized", "params": {}})
        send(p, {"jsonrpc": "2.0", "method": "textDocument/didOpen",
                 "params": {"textDocument": {"uri": uri, "languageId": "zark",
                                             "version": 1, "text": text}}})
        req = 2
        for method in ("textDocument/hover", "textDocument/completion",
                       "textDocument/definition"):
            send(p, {"jsonrpc": "2.0", "id": req, "method": method,
                     "params": {"textDocument": {"uri": uri}, "position": pos()}})
            wait_id(p, req, dl)
            req += 1
        text2, _ = fuzz_crash.mutate_text(text, rng)
        send(p, {"jsonrpc": "2.0", "method": "textDocument/didChange",
                 "params": {"textDocument": {"uri": uri, "version": 2},
                            "contentChanges": [{"text": text2}]}})
        send(p, {"jsonrpc": "2.0", "id": req, "method": "textDocument/hover",
                 "params": {"textDocument": {"uri": uri}, "position": pos()}})
        wait_id(p, req, dl)
        req += 1
        send(p, {"jsonrpc": "2.0", "id": req, "method": "shutdown", "params": None})
        wait_id(p, req, dl)
        send(p, {"jsonrpc": "2.0", "method": "exit"})
        try:
            p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            why = "did not exit"
    except Timeout:
        why = "timeout"
    except Eof:
        why = "server closed stdout"
    except ValueError as e:
        why = str(e)
    finally:
        if p.poll() is None:
            p.kill()
    try:
        err = p.stderr.read().decode("utf-8", "replace")
    except Exception:
        err = ""
    if why is None and p.returncode not in (0, -9, -15):
        why = f"exit {p.returncode}"
    if why is None and fuzz_crash.BAD_RE.search(err):
        why = "compiler panic"
    return why, err


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--zark", default=os.environ.get("ZARK", os.path.join(ROOT, "build", "zark")))
    ap.add_argument("--timeout", type=int, default=10)
    args = ap.parse_args()

    zark = os.path.abspath(args.zark)
    if not os.path.exists(zark):
        print(f"fuzz_lsp: no compiler at {zark}", file=sys.stderr)
        return 2
    files = fuzz_crash.corpus()
    if not files:
        print("fuzz_lsp: empty corpus", file=sys.stderr)
        return 2
    count = args.count if args.count is not None else (20 if args.quick else 100)
    scratch = os.path.join(ROOT, "scratch", "fuzz_lsp")
    findings = 0
    for i in range(count):
        seed = args.seed + i
        r = random.Random(seed)
        base = r.choice(files)
        try:
            with open(base, "rb") as f:
                raw = f.read().decode("latin-1")
        except OSError:
            continue
        text, kind = fuzz_crash.mutate_text(raw, r)
        why, err = session(zark, base, text, r, args.timeout)
        if why is None:
            if not args.quick and (i + 1) % 20 == 0:
                print(f"{i + 1}/{count} sessions ok")
            continue
        findings += 1
        os.makedirs(scratch, exist_ok=True)
        tag = f"{seed}_{kind}"
        with open(os.path.join(scratch, tag + ".zk"), "wb") as f:
            f.write(text.encode("latin-1", "ignore"))
        with open(os.path.join(scratch, tag + ".txt"), "w") as f:
            f.write(f"base: {base}\nmutation: {kind}\nresult: {why}\n")
            f.write(err[-4000:])
        print(f"seed {seed}: {why} on {os.path.relpath(base, ROOT)} (saved scratch/fuzz_lsp/{tag}.zk)")
        for line in err.splitlines()[:8]:
            print(f"    {line}")
        if not args.keep:
            break
    if findings:
        print(f"fuzz_lsp: {findings} finding(s) in {count} sessions")
        return 1
    print(f"fuzz_lsp: {count} sessions ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
