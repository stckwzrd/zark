import itertools, os, subprocess, sys, tempfile

INTS = ["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64"]
BITS = {"i8": 8, "i16": 16, "i32": 32, "i64": 64, "u8": 8, "u16": 16, "u32": 32, "u64": 64}


def rng(t):
    b = BITS[t]
    if t[0] == "i":
        return -(1 << (b - 1)), (1 << (b - 1)) - 1
    return 0, (1 << b) - 1


def pool(t):
    lo, hi = rng(t)
    b = BITS[t]
    vals = {0, 1, 2, 3, 7, 100, hi, hi - 1, hi // 2, hi // 2 + 1, 1 << (b // 2), (1 << (b // 2)) - 1, (1 << (b // 2)) + 1}
    if t[0] == "i":
        vals |= {-1, -2, -7, lo, lo + 1, lo // 2, -(1 << (b // 2)), -(1 << (b // 2)) - 1, -(1 << (b // 2)) + 1}
    return sorted(v for v in vals if lo <= v <= hi)


def lit(t, v):
    lo, _ = rng(t)
    if v < 0:
        if v == lo:
            return f"((0 - {-(lo + 1)}) - 1) as {t}"
        return f"(0 - {-v}) as {t}"
    return f"{v} as {t}"


def program(t, op, pairs):
    arms = []
    for k, (a, b) in enumerate(pairs):
        arms.append(f"    if (k == {k}) {{ println(id_{t}({lit(t, a)}) {op} id_{t}({lit(t, b)})); return; }}")
    return (
        f"{t} id_{t}({t} x) {{ return x; }}\n"
        "void pick(i64 k) {\n" + "\n".join(arms) + "\n}\n"
        "void main() {\n    pick(parse_int(arg(1)) catch 0);\n}\n"
    )


def expected(t, op, a, b):
    r = {"+": a + b, "-": a - b, "*": a * b}[op]
    lo, hi = rng(t)
    return str(r) if lo <= r <= hi else None


def build(vibe, src, exe, flags):
    p = subprocess.run([vibe, "build", src, "-o", exe] + flags, capture_output=True, text=True, timeout=300)
    return p.returncode, p.stdout + p.stderr


def main():
    vibe = os.environ.get("VIBE", "build/vibe")
    only = sys.argv[1:] or INTS
    bad = 0
    total = 0
    d = tempfile.mkdtemp()
    for t in only:
        pl = pool(t)
        pairs = list(itertools.product(pl, pl))
        for op in ("+", "-", "*"):
            src = os.path.join(d, f"o_{t}.vibe")
            open(src, "w").write(program(t, op, pairs))
            for name, flags in (("native", []), ("llvm", ["--llvm"]), ("O2", ["-O"])):
                exe = os.path.join(d, f"o_{t}_{name}")
                code, out = build(vibe, src, exe, flags)
                if code != 0:
                    print(f"{t} {op} {name}: build failed: {out[:300]}")
                    bad += 1
                    continue
                for k, (a, b) in enumerate(pairs):
                    want = expected(t, op, a, b)
                    p = subprocess.run([exe, str(k)], capture_output=True, text=True, timeout=30)
                    total += 1
                    if want is None:
                        ok = p.returncode != 0 and "integer overflow" in p.stderr + p.stdout
                    else:
                        ok = p.returncode == 0 and p.stdout.strip() == want
                    if not ok:
                        bad += 1
                        print(f"{t} {a} {op} {b} [{name}]: expected {want or 'overflow panic'}, got exit {p.returncode} {(p.stdout + p.stderr)[:120]!r}")
    print(f"done: {total} cases, {bad} problems")
    sys.exit(1 if bad else 0)


main()
