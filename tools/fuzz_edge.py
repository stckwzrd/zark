import random, subprocess, sys, os, tempfile

INTS = ["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64"]
BITS = {"i8": 8, "i16": 16, "i32": 32, "i64": 64, "u8": 8, "u16": 16, "u32": 32, "u64": 64}
FLOATS = ["f32", "f64"]


def pool(t):
    b = BITS[t]
    if t[0] == "i":
        vals = [0, 1, -1, 2, -2, 7, 100, (1 << (b - 1)) - 1, -(1 << (b - 1)), -(1 << (b - 1)) + 1, 1 << (b - 2)]
    else:
        vals = [0, 1, 2, 3, 7, 100, (1 << b) - 1, (1 << b) - 2, 1 << (b - 1), (1 << (b - 1)) - 1]
    return vals


def lit(t, v):
    if t[0] == "i" and v < 0:
        return f"(0 - {-v}) as {t}" if v != -(1 << (BITS[t] - 1)) else f"((0 - {(1 << (BITS[t] - 1)) - 1}) - 1) as {t}"
    return f"{v} as {t}"


def fpool():
    return ["0.0", "1.0", "-1.0", "0.5", "-0.5", "255.9", "256.0", "-129.5", "1e10", "-1e10", "1e19", "-1e19", "3e38", "1e300", "nanv()", "infv()", "ninfv()"]


def expr(r, vars, depth):
    ivars = [v for v in vars if v[1] in INTS]
    if depth == 0 or r.random() < 0.2:
        return r.choice(ivars)
    a, ta = expr(r, vars, depth - 1)
    k = r.random()
    if k < 0.25:
        b, tb = expr(r, vars, depth - 1)
        b = f"({b} as {ta})"
        return f"({a} {r.choice(['+%', '-%', '*%', '&', '|', '^'])} {b})", ta
    if k < 0.45:
        b, tb = expr(r, vars, depth - 1)
        b = f"({b} as {ta})"
        return f"({a} {r.choice(['<<', '>>'])} {b})", ta
    if k < 0.6:
        b, tb = expr(r, vars, depth - 1)
        b = f"nz_{ta}({b} as {ta})"
        return f"({a} {r.choice(['/', '%'])} {b})", ta
    if k < 0.75:
        t = r.choice(INTS)
        return f"({a} as {t})", t
    if k < 0.85:
        f = r.choice(FLOATS)
        t = r.choice(INTS)
        return f"(({a} as {f}) as {t})", t
    if k < 0.93:
        return f"(~{a})", ta
    return f"(pick_{ta}({a}, {r.choice(vars)[0] if False else a}))", ta


def program(seed):
    r = random.Random(seed)
    lines = []
    vars = []
    for i in range(5):
        t = r.choice(INTS)
        lines.append(f"    {t} v{i} = {lit(t, r.choice(pool(t)))};")
        vars.append((f"v{i}", t))
    fvars = []
    for i in range(2):
        f = r.choice(FLOATS)
        lines.append(f"    {f} g{i} = {r.choice(fpool())} as {f};")
        fvars.append((f"g{i}", f))
    for i in range(r.randint(6, 14)):
        e, t = expr(r, vars, 3)
        tgt = r.choice(vars)
        lines.append(f"    {tgt[0]} = {e} as {tgt[1]};")
        if r.random() < 0.3:
            g = r.choice(fvars)
            tgt2 = r.choice(vars)
            lines.append(f"    {tgt2[0]} = {g[0]} as {tgt2[1]};")
        if r.random() < 0.2:
            g = r.choice(fvars)
            src = r.choice(vars)
            lines.append(f"    {g[0]} = {src[0]} as {g[1]};")
    body = "\n".join(lines)
    prints = "\n".join(f"    println({v[0]});" for v in vars + fvars)
    helpers = "\n".join(
        f"{t} nz_{t}({t} d) {{ if (d == 0 as {t}) {{ return 1 as {t}; }} return d; }}\n{t} pick_{t}({t} a, {t} b) {{ if (a < b) {{ return a; }} return b; }}"
        for t in INTS)
    helpers += "\nf64 zero() { return 0.0; }\nf64 nanv() { return zero() / zero(); }\nf64 infv() { return 1.0 / zero(); }\nf64 ninfv() { return -1.0 / zero(); }\n"
    return helpers + "\nvoid main() {\n" + body + "\n" + prints + "\n}\n"


def run(zark, path, flags):
    p = subprocess.run([zark, "run", path] + flags, capture_output=True, text=True, timeout=120)
    return p.returncode, p.stdout + p.stderr


def main():
    zark = os.environ.get("ZARK", "build/zark")
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    bad = 0
    for seed in range(start, start + n):
        src = program(seed)
        d = tempfile.mkdtemp()
        path = os.path.join(d, "f.zk")
        open(path, "w").write(src)
        res = {}
        for name, flags in (("native", []), ("llvm", ["--llvm"]), ("O2", ["-O"]), ("rel", ["--release"])):
            try:
                res[name] = run(zark, path, flags)
            except subprocess.TimeoutExpired:
                res[name] = (-1, "timeout")
        safe = {k: v for k, v in res.items() if k != "rel"}
        ok = len(set(safe.values())) == 1
        rel_ok = res["rel"][0] != 0 or res["rel"] == res["native"] or res["native"][0] != 0
        if safe["native"][0] != 0 and "panic" not in safe["native"][1] and ok:
            print(f"seed {seed}: compile problem")
            print(safe["native"][1][:300])
            bad += 1
        elif not ok or (res["native"][0] == 0 and res["rel"] != res["native"]):
            bad += 1
            keep = f"/tmp/claude-1000/fuzz_edge_{seed}.zk"
            open(keep, "w").write(src)
            print(f"seed {seed}: MISMATCH saved {keep}")
            for k, v in res.items():
                print("   ", k, v[0], v[1][:150].replace("\n", " | "))
    print(f"done: {n} programs, {bad} problems")
    sys.exit(1 if bad else 0)


main()
