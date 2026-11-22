import random, subprocess, sys, os, tempfile

TYPES = ["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64"]
BITS = {"i8": 8, "i16": 16, "i32": 32, "i64": 64, "u8": 8, "u16": 16, "u32": 32, "u64": 64}
OPS = ["+%", "-%", "*%", "&", "|", "^"]


def expr(r, vars, depth):
    if depth == 0 or r.random() < 0.25:
        v = r.choice(vars)
        return v[0], v[1]
    kind = r.random()
    if kind < 0.55:
        a, ta = expr(r, vars, depth - 1)
        b, tb = expr(r, vars, depth - 1)
        b = f"({b} as {ta})" if tb != ta else b
        return f"({a} {r.choice(OPS)} {b})", ta
    if kind < 0.7:
        a, ta = expr(r, vars, depth - 1)
        b, tb = expr(r, vars, depth - 1)
        b = f"(({b} as {ta}) | 1)"
        return f"({a} {r.choice(['/', '%'])} {b})", ta
    if kind < 0.8:
        a, ta = expr(r, vars, depth - 1)
        return f"({a} {r.choice(['<<', '>>'])} {r.randint(0, BITS[ta] - 1)})", ta
    if kind < 0.95:
        a, ta = expr(r, vars, depth - 1)
        t = r.choice(TYPES)
        return f"({a} as {t})", t
    a, ta = expr(r, vars, depth - 1)
    b, tb = expr(r, vars, depth - 1)
    b = f"({b} as {ta})" if tb != ta else b
    return f"(pick_{ta}({a}, {b}))", ta


def program(seed):
    r = random.Random(seed)
    lines = []
    vars = []
    for i in range(6):
        t = r.choice(TYPES)
        lines.append(f"    {t} v{i} = {r.randint(0, 100)} as {t};")
        vars.append((f"v{i}", t))
    for i in range(r.randint(8, 20)):
        e, t = expr(r, vars, 4)
        tgt = r.choice(vars)
        lines.append(f"    {tgt[0]} = {e} as {tgt[1]};")
        if r.random() < 0.2:
            c, tc = expr(r, vars, 2)
            tgt2 = r.choice(vars)
            lines.append(f"    if ({tgt2[0]} > ({c} as {tgt2[1]})) {{ {tgt2[0]} = {tgt2[0]} -% 1 as {tgt2[1]}; }}")
        if r.random() < 0.15:
            lines.append(f"    for (auto k : 0..{r.randint(1, 5)}) {{ {tgt[0]} = ({tgt[0]} *% 3 +% k as {tgt[1]}) as {tgt[1]}; }}")
    body = "\n".join(lines)
    prints = "\n".join(f"    println({v[0]});" for v in vars)
    helpers = "\n".join(f"{t} pick_{t}({t} a, {t} b) {{ if (a < b) {{ return a; }} return b; }}" for t in TYPES)
    return helpers + "\nvoid main() {\n" + body + "\n" + prints + "\n}\n"


def program_b(seed):
    r = random.Random(seed)
    nargs = r.randint(1, 10)
    kinds = [r.choice(["i64", "i32", "u8", "f64", "f32", "bool"]) for _ in range(nargs)]
    params = ", ".join(f"{k} a{i}" for i, k in enumerate(kinds))
    terms = []
    for i, k in enumerate(kinds):
        if k == "bool":
            terms.append(f"(if (a{i}) {{ 3.0 }} else {{ 1.0 }})".replace("if (a%d) { 3.0 } else { 1.0 }" % i, "pickb(a%d)" % i))
        elif k in ("f64", "f32"):
            terms.append(f"(a{i} as f64)")
        else:
            terms.append(f"(a{i} as f64)")
    body = " + ".join(f"{terms[i]} * {r.randint(1, 9)}.0" for i in range(nargs))
    struct_fields = r.randint(1, 5)
    fields = "\n".join(f"    {r.choice(['i64','f64','i32','u8'])} f{i};" for i in range(struct_fields))
    ftypes = [l.split()[0] for l in fields.split("\n")]
    inits = ", ".join(f".f{i} = {r.randint(0, 50)} as {ftypes[i]}" for i in range(struct_fields))
    sums = " + ".join(f"(s.f{i} as f64)" for i in range(struct_fields))
    args = ", ".join(f"{'true' if k == 'bool' and r.random() < .5 else 'false' if k == 'bool' else str(r.randint(0, 20)) + ' as ' + k}" for k in kinds)
    arrn = r.randint(2, 12)
    return f"""
f64 pickb(bool b) {{ if (b) {{ return 3.0; }} return 1.0; }}
struct S {{
{fields}
}}
f64 many({params}) {{ return {body}; }}
S make(i64 k) {{
    S s = S{{ {inits} }};
    s.f0 = (s.f0 as i64 + k) as {ftypes[0]};
    return s;
}}
f64 total(S s) {{ return {sums}; }}
f64 arr_sum(f64[] xs) {{
    f64 t = 0.0;
    for (auto i : 0..xs.len) {{ t += xs[i] * (i + 1) as f64; }}
    return t;
}}
void main() {{
    const auto s = make({r.randint(0, 9)});
    println(many({args}), total(s));
    f64[{arrn}] xs;
    for (auto i : 0..{arrn}) {{ xs[i] = (i * {r.randint(1, 7)}) as f64 / 3.0; }}
    println(arr_sum(xs[..]));
    const auto f = [&xs](i64 i) -> f64 {{ return xs[i % {arrn}] * 2.0; }};
    println(f({r.randint(0, 30)}));
}}
"""


def run(zark, path, flags):
    p = subprocess.run([zark, "run", path] + flags, capture_output=True, text=True, timeout=120)
    return p.returncode, p.stdout + p.stderr


def main():
    zark = os.environ.get("ZARK", "build/zark")
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    bad = 0
    for seed in range(start, start + n):
        src = program_b(seed) if os.environ.get('MODE') == 'b' else program(seed)
        d = tempfile.mkdtemp()
        path = os.path.join(d, "f.zk")
        open(path, "w").write(src)
        res = {}
        for name, flags in (("native", []), ("llvm", ["--llvm"]), ("O2", ["-O"])):
            try:
                res[name] = run(zark, path, flags)
            except subprocess.TimeoutExpired:
                res[name] = (-1, "timeout")
        ok = len(set(v for v in res.values())) == 1
        if res["native"][0] != 0 and ok:
            print(f"seed {seed}: compile problem")
            print(res["native"][1][:300])
            bad += 1
        elif not ok:
            bad += 1
            keep = f"/tmp/claude-1000/fuzz_{seed}.zk"
            open(keep, "w").write(src)
            print(f"seed {seed}: MISMATCH saved {keep}")
            for k, v in res.items():
                print("  ", k, v[0], v[1].replace("\n", " ")[:120])
    print(f"done: {n} programs, {bad} problems")


main()
