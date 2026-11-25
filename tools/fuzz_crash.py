#!/usr/bin/env python3
"""Crash fuzzer for the compiler frontends.

Mutates real .zk files from examples/, tests/, std/ and selfhost/ and runs
`zark tokens`, `zark ir` and `zark fmt --check` on the mutant with a timeout
and an address-space limit.  A signal exit, a timeout, an allocation failure
or a compiler panic is a finding; a normal non-zero exit with an error
message is fine.

usage: tools/fuzz_crash.py [--count N] [--seed N] [--quick] [--keep]
                           [--zark PATH] [--timeout SEC] [--memory-mb N]
"""

import argparse
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS_DIRS = ("examples", "tests", "std", "selfhost")
KEYWORDS = [
    "auto", "const", "static", "template", "fn", "struct", "union", "enum",
    "match", "type", "import", "extern", "export", "defer", "errdefer",
    "catch", "orelse", "is", "as", "move", "borrows", "invalidates",
    "await", "async", "owned", "packed", "test", "while", "for", "if",
    "else", "return", "break", "continue", "true", "false", "null",
    "sizeof", "alignof",
]
BRACKETS = list("(){}[]")
TOKEN_RE = re.compile(
    r'"(?:\\.|[^"\\])*"'
    r"|'(?:\\.|[^'\\])*'"
    r"|[A-Za-z_][A-Za-z0-9_]*"
    r"|[0-9]+(?:\.[0-9]+)?"
    r"|[^\sA-Za-z0-9_]"
)
WORD_RE = re.compile(r"^[A-Za-z_0-9]")


def corpus():
    out = []
    for base in CORPUS_DIRS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, base)):
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            for f in filenames:
                if f.endswith(".zk"):
                    out.append(os.path.join(dirpath, f))
    return sorted(out)


def tokens(text):
    return [(m.start(), m.end(), m.group(0)) for m in TOKEN_RE.finditer(text)]


def mutate_text(text, rng):
    for _ in range(8):
        kind = rng.randrange(9)
        toks = tokens(text)
        lines = text.split("\n")
        if kind == 0 and toks:
            s, e, _ = rng.choice(toks)
            out = text[:s] + text[e:]
        elif kind == 1 and toks:
            s, e, t = rng.choice(toks)
            out = text[:e] + t + text[e:]
        elif kind == 2 and len(toks) > 1:
            i = rng.randrange(len(toks) - 1)
            s1, e1, t1 = toks[i]
            s2, e2, t2 = toks[i + 1]
            out = text[:s1] + t2 + text[e1:s2] + t1 + text[e2:]
        elif kind == 3:
            pos = rng.randrange(len(text) + 1)
            out = text[:pos] + rng.choice(BRACKETS) + text[pos:]
        elif kind == 4 and len(text) > 20:
            pos = rng.randrange(len(text) // 5, max(len(text) * 9 // 10, len(text) // 5 + 1))
            out = text[:pos]
        elif kind == 5:
            words = [t for t in toks if WORD_RE.match(t[2]) and not t[2][0].isdigit()]
            if not words:
                continue
            s, e, _ = rng.choice(words)
            out = text[:s] + rng.choice(KEYWORDS) + text[e:]
        elif kind == 6 and len(lines) > 2:
            i = rng.randrange(1, len(lines))
            out = "\n".join(lines[:i] + lines[i + 1:])
        elif kind == 7 and len(lines) > 1:
            i = rng.randrange(len(lines))
            out = "\n".join(lines[:i] + [lines[i]] + lines[i:])
        elif kind == 8 and len(lines) > 2:
            i = rng.randrange(len(lines) - 1)
            ls = list(lines)
            ls[i], ls[i + 1] = ls[i + 1], ls[i]
            out = "\n".join(ls)
        else:
            continue
        if out and out != text:
            return out, kind
    return text, -1


def limit_memory(mb):
    try:
        import resource
        n = mb * 1024 * 1024
        resource.setrlimit(resource.RLIMIT_AS, (n, n))
    except Exception:
        pass


BAD_RE = re.compile(r"(?m)^(?:panic:|fatal:|error: internal compiler error:)")


def run_cmd(zark, args, timeout, memory_mb):
    def pre():
        limit_memory(memory_mb)
    try:
        p = subprocess.run([zark] + args, cwd=ROOT, capture_output=True,
                           timeout=timeout, preexec_fn=pre)
    except subprocess.TimeoutExpired:
        return "timeout", -1, ""
    except OSError as e:
        return f"exec error: {e}", -1, ""
    out = (p.stdout + p.stderr).decode("utf-8", "replace")
    if p.returncode < 0:
        return f"signal {p.returncode}", p.returncode, out
    if BAD_RE.search(out):
        return "compiler panic", p.returncode, out
    return None, p.returncode, out


def one(zark, base, seed, rng, timeout, memory_mb, scratch):
    with open(base, "rb") as f:
        text = f.read().decode("latin-1")
    mutant, kind = mutate_text(text, rng)
    if kind < 0:
        return None
    d = os.path.dirname(base)
    fd, path = tempfile.mkstemp(prefix=".fuzz-", suffix=".zk", dir=d)
    try:
        os.write(fd, mutant.encode("latin-1", "ignore"))
        os.close(fd)
        cmds = [("tokens", ["tokens", path]),
                ("ir", ["ir", path]),
                ("fmt", ["fmt", "--check", path])]
        for name, args in cmds:
            why, rc, out = run_cmd(zark, args, timeout, memory_mb)
            if why is None:
                continue
            tag = f"{seed}_{kind}_{name}"
            os.makedirs(scratch, exist_ok=True)
            with open(os.path.join(scratch, tag + ".zk"), "wb") as f:
                f.write(mutant.encode("latin-1", "ignore"))
            with open(os.path.join(scratch, tag + ".txt"), "w") as f:
                f.write(f"base: {base}\nmutation: {kind}\ncommand: {' '.join(args[:2])}\n")
                f.write(f"result: {why} (exit {rc})\n")
                f.write(out[-4000:])
            return (tag, base, name, why, rc, out)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--zark", default=os.environ.get("ZARK", os.path.join(ROOT, "build", "zark")))
    ap.add_argument("--timeout", type=int, default=10)
    ap.add_argument("--memory-mb", type=int, default=2048)
    args = ap.parse_args()

    zark = os.path.abspath(args.zark)
    if not os.path.exists(zark):
        print(f"fuzz_crash: no compiler at {zark}", file=sys.stderr)
        return 2
    files = corpus()
    if not files:
        print("fuzz_crash: empty corpus", file=sys.stderr)
        return 2
    count = args.count if args.count is not None else (50 if args.quick else 200)
    rng = random.Random(args.seed)
    scratch = os.path.join(ROOT, "scratch", "fuzz_crash")
    findings = 0
    for i in range(count):
        seed = args.seed + i
        r = random.Random(seed)
        base = r.choice(files)
        res = one(zark, base, seed, r, args.timeout, args.memory_mb, scratch)
        if res is None:
            if not args.quick and (i + 1) % 50 == 0:
                print(f"{i + 1}/{count} mutations ok")
            continue
        findings += 1
        tag, base, name, why, rc, out = res
        print(f"seed {seed}: {why} in `zark {name}` on {os.path.relpath(base, ROOT)}")
        for line in out.splitlines()[:10]:
            print(f"    {line}")
        print(f"    saved scratch/fuzz_crash/{tag}.zk")
        if not args.keep:
            break
    if findings:
        print(f"fuzz_crash: {findings} finding(s) in {count} mutations")
        return 1
    print(f"fuzz_crash: {count} mutations ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
