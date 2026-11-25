#!/usr/bin/env python3
"""Differential whole-program fuzzer with a Python reference model.

Generated programs mix random expression trees, random struct shapes, unions,
enums and nested control flow with defers.  The generator also computes the
expected output (checksum and printed lines), so a frontend bug that all four
backends share is still caught.

Each program is built four ways (native, --llvm, -O, --release); every build
must exit 0 and print exactly the reference output.

usage: tools/fuzz_prog.py [--count N] [--seed N] [--quick] [--keep]
                          [--zark PATH]
"""

import argparse
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLAGS = [[], ["--llvm"], ["-O"], ["--release"]]
MASK = (1 << 64) - 1
SEED = 0xcbf29ce484222325


def mix(h, v):
    return ((h ^ (v & MASK)) * 1099511628211) & MASK


class Ty:
    def __init__(self, name, kind, bits=0, signed=False):
        self.name = name
        self.kind = kind
        self.bits = bits
        self.signed = signed


I8 = Ty("i8", "int", 8, True)
I16 = Ty("i16", "int", 16, True)
I32 = Ty("i32", "int", 32, True)
I64 = Ty("i64", "int", 64, True)
U8 = Ty("u8", "int", 8, False)
U16 = Ty("u16", "int", 16, False)
U32 = Ty("u32", "int", 32, False)
U64 = Ty("u64", "int", 64, False)
F32 = Ty("f32", "float", 32)
F64 = Ty("f64", "float", 64)
BOOL = Ty("bool", "bool")
INTS = [I8, I16, I32, I64, U8, U16, U32, U64]
FLOATS = [F32, F64]
SCALARS = INTS + FLOATS + [BOOL]


def wrap(v, ty):
    m = (1 << ty.bits) - 1
    v &= m
    if ty.signed and v >= (1 << (ty.bits - 1)):
        v -= 1 << ty.bits
    return v


def f32(v):
    return struct.unpack("<f", struct.pack("<f", v))[0]


def conv(v, src, dst):
    if dst.kind == "int":
        if src.kind == "int":
            return wrap(v, dst)
        if src.kind == "bool":
            return wrap(1 if v else 0, dst)
        if src.kind == "float":
            return wrap(int(v), dst)
    if dst.kind == "float":
        if src.kind == "bool":
            f = float(int(v))
        else:
            f = float(v)
        return f32(f) if dst.bits == 32 else f
    if dst.kind == "bool":
        if src.kind == "bool":
            return v
        if src.kind == "int":
            return v != 0
        if src.kind == "float":
            return v != 0.0
    raise ValueError(f"cannot convert {src.name} to {dst.name}")


def lit(v, ty):
    if ty.kind == "int":
        if v < 0:
            return f"((0 - {-v}) as {ty.name})"
        return f"({v} as {ty.name})"
    if ty.kind == "bool":
        return "true" if v else "false"
    return f"({v!r} as {ty.name})"


def as_int_code(code, ty):
    """code that mixes a value of `ty` as i64, plus its reference value."""
    if ty.kind in ("int", "bool"):
        return f"({code} as i64)"
    return f"((({code} as f64) * 1000.0) as i64)"


def as_int_value(v, ty):
    if ty.kind == "bool":
        return int(v)
    if ty.kind == "int":
        x = int(v)
        if ty.bits == 64 and not ty.signed and x >= (1 << 63):
            x -= 1 << 64
        return x
    return int(v * 1000.0)


class ExprGen:
    def __init__(self, rng, vars):
        self.rng = rng
        self.vars = vars  # list of (name, Ty, value)

    def atom(self, want):
        r = self.rng
        cand = [v for v in self.vars if want is None or v[1] is want]
        if cand and r.random() < 0.55:
            name, ty, val = r.choice(cand)
            return name, ty, val
        ty = want if want is not None else r.choice(SCALARS)
        if ty.kind == "int":
            v = r.choice([-9, -3, -1, 0, 1, 2, 3, 5, 7, 11, 13])
            return lit(v, ty), ty, wrap(v, ty)
        if ty.kind == "bool":
            v = r.random() < 0.5
            return lit(v, ty), ty, v
        v = r.choice([-3.25, -1.5, -0.5, 0.0, 0.25, 0.5, 1.5, 3.25, 7.5])
        return lit(v, ty), ty, (f32(v) if ty.bits == 32 else v)

    def gen(self, depth):
        return self.gen_of(self.rng.choice(SCALARS), depth)

    def gen_of(self, want, depth):
        r = self.rng
        if depth <= 0 or r.random() < 0.3:
            return self.atom(want)
        if want.kind == "bool":
            kind = r.random()
            if kind < 0.45:
                t = r.choice(INTS + FLOATS)
                a, _, av = self.gen_of(t, depth - 1)
                b, _, bv = self.gen_of(t, depth - 1)
                op = r.choice(["<", "<=", ">", ">=", "==", "!="])
                return f"(({a}) {op} ({b}))", BOOL, {
                    "<": av < bv, "<=": av <= bv, ">": av > bv,
                    ">=": av >= bv, "==": av == bv, "!=": av != bv}[op]
            if kind < 0.8:
                a, _, av = self.gen_of(BOOL, depth - 1)
                b, _, bv = self.gen_of(BOOL, depth - 1)
                if r.random() < 0.5:
                    return f"(({a}) && ({b}))", BOOL, bool(av and bv)
                return f"(({a}) || ({b}))", BOOL, bool(av or bv)
            a, _, av = self.gen_of(BOOL, depth - 1)
            return f"(!({a}))", BOOL, not av
        if want.kind == "float":
            kind = r.random()
            if kind < 0.3:
                # keep the magnitude inside i64 after the *1000 scaling used
                # when a float is mixed into the checksum
                src = r.choice([I8, I16, I32, U8, U16, U32, F32, F64])
                a, _, av = self.gen_of(src, depth - 1)
                return f"(({a}) as {want.name})", want, conv(av, src, want)
            a, _, av = self.gen_of(want, depth - 1)
            if kind < 0.85:
                b, _, bv = self.gen_of(want, depth - 1)
                op = r.choice(["+", "-", "*", "/"])
                if op == "/":
                    div = r.choice([2.0, 4.0, 0.5])
                    val = av / div
                    if not (-1e12 <= val <= 1e12):
                        return self.atom(want)
                    code = f"(({a}) / ({lit(div, want)}))"
                    return code, want, f32(val) if want.bits == 32 else val
                code = f"(({a}) {op} ({b}))"
                if op == "+":
                    val = av + bv
                elif op == "-":
                    val = av - bv
                else:
                    val = av * bv
                if not (-1e12 <= val <= 1e12):
                    return self.atom(want)
                return code, want, (f32(val) if want.bits == 32 else val)
            return f"(-({a}))", want, f32(-av) if want.bits == 32 else -av
        # int
        kind = r.random()
        if kind < 0.25:
            src = r.choice(INTS + [BOOL])
            a, _, av = self.gen_of(src, depth - 1)
            return f"(({a}) as {want.name})", want, conv(av, src, want)
        a, _, av = self.gen_of(want, depth - 1)
        b, _, bv = self.gen_of(want, depth - 1)
        if kind < 0.75:
            op = r.choice(["+%", "-%", "*%"])
            if op == "+%":
                val = av + bv
            elif op == "-%":
                val = av - bv
            else:
                val = av * bv
            return f"(({a}) {op} ({b}))", want, wrap(val, want)
        op = r.choice(["&", "|", "^"])
        val = {"&": av & bv, "|": av | bv, "^": av ^ bv}[op]
        return f"(({a}) {op} ({b}))", want, wrap(val, want)


class Unit:
    def __init__(self, decl="", body="", events=None):
        self.decl = decl
        self.body = body
        self.events = events or []


def u_expr(rng, k):
    vars = []
    body = []
    events = []
    for j in range(rng.randint(2, 4)):
        ty = rng.choice(SCALARS)
        code, _, val = ExprGen(rng, vars).gen_of(ty, rng.randint(1, 3))
        name = f"v{k}_{j}"
        body.append(f"    const auto {name} = {code};")
        body.append(f"    h = mix(h, {as_int_code(name, ty)});")
        events.append(("mix", as_int_value(val, ty)))
        vars.append((name, ty, val))
    return Unit(body="\n".join(body), events=events)


def struct_leaves(meta, code, value):
    out = []
    for fname, kind, info in meta.fields:
        c = f"{code}.{fname}"
        v = value[fname]
        if kind == "scalar":
            out.append((as_int_code(c, info), as_int_value(v, info)))
        elif kind == "array":
            ety, n = info
            for i in range(n):
                out.append((as_int_code(f"{c}[{i}]", ety), as_int_value(v[i], ety)))
        else:
            out.extend(struct_leaves(info, c, v))
    return out


def make_struct(rng, name, avail):
    nf = rng.randint(2, 5)
    fields = []
    used = set()
    for i in range(nf):
        fname = f"f{i}"
        kind = rng.random()
        if kind < 0.55 or not avail:
            fields.append((fname, "scalar", rng.choice(SCALARS)))
        elif kind < 0.8:
            fields.append((fname, "array", (rng.choice(SCALARS), rng.randint(1, 3))))
        else:
            fields.append((fname, "struct", rng.choice(avail)))
        used.add(fname)
    return StructMeta(name, fields)


class StructMeta:
    def __init__(self, name, fields):
        self.name = name
        self.fields = fields

    def decl(self):
        parts = []
        for fname, kind, info in self.fields:
            if kind == "scalar":
                parts.append(f"{info.name} {fname};")
            elif kind == "array":
                parts.append(f"{info[0].name}[{info[1]}] {fname};")
            else:
                parts.append(f"{info.name} {fname};")
        return f"struct {self.name} {{ {' '.join(parts)} }}\n"


def struct_init(meta, eg):
    parts = []
    value = {}
    for fname, kind, info in meta.fields:
        if kind == "scalar":
            code, _, v = eg.gen_of(info, 2)
        elif kind == "array":
            ety, n = info
            vs = [eg.gen_of(ety, 1) for _ in range(n)]
            code = "[" + ", ".join(x[0] for x in vs) + "]"
            v = [x[2] for x in vs]
        else:
            code, v = struct_init(info, eg)
        parts.append(f".{fname} = {code}")
        value[fname] = v
    return f"{meta.name}{{ {', '.join(parts)} }}", value


def u_struct(rng, k, avail):
    # a nested struct first, sometimes
    decls = []
    nested = None
    if rng.random() < 0.5:
        nested = make_struct(rng, f"N{k}", avail)
        decls.append(nested.decl())
    meta = make_struct(rng, f"S{k}", ([nested] if nested else []) + avail)
    decls.append(meta.decl())
    # value constructors for nested fields need their own handlers; keep it
    # simple: a nested struct field is initialized inline by struct_init.
    eg = ExprGen(rng, [])
    init, val = struct_init(meta, eg)

    # plus(by value) and bump(pointer) with a mirrored mutation
    mcode = None
    mut = None
    for fname, kind, info in meta.fields:
        if kind != "scalar":
            continue
        if info.kind == "int":
            d = rng.choice([1, 3, 7, -2])
            mcode = f"    s.{fname} = s.{fname} +% {lit(d, info)};"
            mut = ("int", fname, d, info)
        elif info.kind == "bool":
            mcode = f"    s.{fname} = !s.{fname};"
            mut = ("bool", fname, None, info)
        else:
            d = rng.choice([0.25, 0.5, -0.25])
            mcode = f"    s.{fname} = s.{fname} + {lit(d, info)};"
            mut = ("float", fname, d, info)
        break
    decls.append(f"{meta.name} id{k}({meta.name} s) {{ return s; }}\n")
    if mcode is None:
        decls.append(f"{meta.name} plus{k}({meta.name} s) {{ return s; }}\n")
        decls.append(f"void bump{k}({meta.name}* p) {{ }}\n")
    else:
        decls.append(f"{meta.name} plus{k}({meta.name} s) {{\n{mcode}\n    return s;\n}}\n")
        decls.append(f"void bump{k}({meta.name}* p) {{\n    auto s = p;\n    {mcode.strip()}\n}}\n")

    body = []
    events = []
    body.append(f"    auto s{k} = {init};")
    for code, v in struct_leaves(meta, f"s{k}", val):
        body.append(f"    h = mix(h, {code});")
        events.append(("mix", v))
    body.append(f"    const auto idr{k} = id{k}(s{k});")
    for code, v in struct_leaves(meta, f"idr{k}", val):
        body.append(f"    h = mix(h, {code});")
        events.append(("mix", v))
    # plus by value: apply the same mutation to the reference value
    val2 = {f: (list(x) if isinstance(x, list) else dict(x) if isinstance(x, dict) else x)
            for f, x in val.items()}
    if mut is not None:
        kind, fname, delta, ty = mut
        if kind == "int":
            val2[fname] = wrap(val2[fname] + delta, ty)
        elif kind == "bool":
            val2[fname] = not val2[fname]
        else:
            nv = val2[fname] + delta
            val2[fname] = f32(nv) if ty.bits == 32 else nv
    body.append(f"    const auto plusr{k} = plus{k}(s{k});")
    for code, v in struct_leaves(meta, f"plusr{k}", val2):
        body.append(f"    h = mix(h, {code});")
        events.append(("mix", v))
    # bump through a pointer: same mutation again on s
    val3 = {f: (list(x) if isinstance(x, list) else dict(x) if isinstance(x, dict) else x)
            for f, x in val.items()}
    if mut is not None:
        kind, fname, delta, ty = mut
        if kind == "int":
            val3[fname] = wrap(val3[fname] + delta, ty)
        elif kind == "bool":
            val3[fname] = not val3[fname]
        else:
            nv = val3[fname] + delta
            val3[fname] = f32(nv) if ty.bits == 32 else nv
    body.append(f"    bump{k}(&s{k});")
    for code, v in struct_leaves(meta, f"s{k}", val3):
        body.append(f"    h = mix(h, {code});")
        events.append(("mix", v))
    return Unit(decl="".join(decls), body="\n".join(body), events=events)


def u_union(rng, k):
    nv = rng.randint(2, 4)
    variants = [(f"V{i}", rng.choice(SCALARS)) for i in range(nv)]
    decl = "union U{k} {{ {parts} }}\n".format(
        k=k, parts=" ".join(f"{t.name} {n};" for n, t in variants))
    pick = rng.randrange(nv)
    pname, pty = variants[pick]
    code, _, val = ExprGen(rng, []).gen_of(pty, 2)
    body = []
    events = []
    body.append(f"    const U{k} u{k} = .{pname}({code});")
    first, fty = variants[0]
    body.append(f"    match u{k} {{")
    body.append(f"        .{first}(v) => {{ h = mix(h, {as_int_code('v', fty)}); }},")
    body.append("        _ => { h = mix(h, 99); },")
    body.append("    }")
    if pick == 0:
        events.append(("mix", as_int_value(val, fty)))
    else:
        events.append(("mix", 99))
    return Unit(decl=decl, body="\n".join(body), events=events)


def u_enum(rng, k):
    nv = rng.randint(3, 5)
    names = [f"V{i}" for i in range(nv)]
    decl = f"enum E{k} {{ {', '.join(names)} }}\n"
    pick = rng.randrange(nv)
    other = (pick + 1) % nv
    body = []
    events = []
    body.append(f"    const auto e{k} = E{k}::{names[pick]};")
    body.append(f"    if (e{k} is .{names[pick]}) {{ h = mix(h, 1); }} else {{ h = mix(h, 2); }}")
    events.append(("mix", 1))
    body.append(f"    match e{k} {{")
    for i, n in enumerate(names):
        body.append(f"        .{n} => {{ h = mix(h, {10 + i}); }},")
    body.append("    }")
    events.append(("mix", 10 + pick))
    body.append(f"    if (e{k} is .{names[other]}) {{ h = mix(h, 3); }} else {{ h = mix(h, 4); }}")
    events.append(("mix", 4))
    return Unit(decl=decl, body="\n".join(body), events=events)


def u_loop_defer(rng, k):
    a = rng.randint(0, 2)
    b = a + rng.randint(4, 7)
    c = a + rng.randint(1, 3)
    d = a + rng.randint(3, b - a - 1) if b - a > 3 else b - 1
    m = rng.choice([3, 5, 7])
    body = f"""    for (auto i : {a}..{b}) {{
        defer println("L{k} {{i}}");
        if (i < {c}) {{ continue; }}
        if (i == {d}) {{ break; }}
        h = mix(h, i *% {m});
    }}"""
    events = []
    for i in range(a, b):
        if i < c:
            events.append(("print", f"L{k} {i}"))
            continue
        if i == d:
            events.append(("print", f"L{k} {i}"))
            break
        events.append(("mix", wrap(i * m, I64)))
        events.append(("print", f"L{k} {i}"))
    return Unit(body=body, events=events)


def u_nested_defer(rng, k):
    a = rng.choice([1, 2, 3, 5, 7])
    b = rng.choice([11, 13, 17])
    body = f"""    {{
        defer println("A{k}");
        h = mix(h, {a});
        {{
            defer println("B{k}");
            h = mix(h, {b});
        }}
    }}"""
    events = [("mix", a), ("mix", b), ("print", f"B{k}"), ("print", f"A{k}")]
    return Unit(body=body, events=events)


def u_func_defer(rng, k):
    a = rng.randint(1, 9)
    decl = f"""!i64 fd{k}(i64 n) {{
    defer println("D{k}");
    errdefer println("E{k}");
    if (n < 0) {{ return error.Bad; }}
    return n *% 3;
}}
"""
    body = f"""    const auto fs{k} = fd{k}({a}) catch -1;
    h = mix(h, fs{k});
    const auto fe{k} = fd{k}(-1) catch -2;
    h = mix(h, fe{k});"""
    events = [
        ("print", f"D{k}"),
        ("mix", wrap(a * 3, I64)),
        ("print", f"E{k}"),
        ("print", f"D{k}"),
        ("mix", -2),
    ]
    return Unit(decl=decl, body=body, events=events)


def u_closure_loop(rng, k):
    a = rng.randint(1, 5)
    body = f"""    for (auto i : 0..3) {{
        const U{k} u = .V0((i as i64) +% {a});
        const auto c{k} = [u]() -> i64 {{
            match u {{
                .V0(x) => {{ return x *% 2; }},
                _ => {{ return 7; }},
            }}
            return 0;
        }};
        h = mix(h, c{k}());
    }}"""
    decl = f"union U{k} {{ i64 V0; bool V1; }}\n"
    events = [("mix", wrap((i + a) * 2, I64)) for i in range(3)]
    return Unit(decl=decl, body=body, events=events)


def generate(seed):
    rng = random.Random(seed)
    units = []
    k = 0
    for _ in range(rng.randint(2, 3)):
        units.append(u_expr(rng, k))
        k += 1
    structs = []
    for _ in range(rng.randint(1, 2)):
        units.append(u_struct(rng, k, structs))
        k += 1
    units.append(u_union(rng, k))
    k += 1
    units.append(u_enum(rng, k))
    k += 1
    choices = [u_loop_defer, u_nested_defer, u_func_defer, u_closure_loop]
    rng.shuffle(choices)
    for fn in choices[:rng.randint(2, 4)]:
        units.append(fn(rng, k))
        k += 1
    return units


HELPERS = """u64 mix(u64 h, i64 v) {
    h = (h ^ (v as u64)) *% 1099511628211;
    return h;
}

"""


def render(units):
    out = [HELPERS]
    for u in units:
        if u.decl:
            out.append(u.decl)
    out.append("!void main() {\n    u64 h = 0xcbf29ce484222325 as u64;\n")
    for u in units:
        out.append(u.body)
        out.append("\n")
    out.append('    println("checksum {h:x}");\n}\n')
    return "".join(out)


def expected(units):
    h = SEED
    lines = []
    for u in units:
        for kind, v in u.events:
            if kind == "mix":
                h = mix(h, v)
            else:
                lines.append(v)
    lines.append(f"checksum {h:x}")
    return "\n".join(lines) + "\n"


def run_program(zark, text, want, workdir):
    path = os.path.join(workdir, "main.zk")
    with open(path, "w") as f:
        f.write(text)
    env = os.environ.copy()
    env["ZARK_CRASH_HANDLER"] = "0"
    results = []
    for flags in FLAGS:
        cmd = [zark, "run", path] + flags
        try:
            p = subprocess.run(cmd, cwd=workdir, env=env, capture_output=True,
                               text=True, timeout=120)
        except subprocess.TimeoutExpired:
            return "diverge", [(flags, -1, "", "timeout")]
        results.append((flags, p.returncode, p.stdout, p.stderr))
    ran = sum(1 for _, rc, _, _ in results if rc == 0)
    if ran == 0:
        return "invalid", results
    if ran != len(results):
        return "diverge", results
    if any(out != want for _, _, out, _ in results):
        return "diverge", results
    return "ok", results


def diverges(zark, units):
    d = tempfile.mkdtemp(prefix="zarkfuzz-")
    try:
        status, _ = run_program(zark, render(units), expected(units), d)
        return status != "ok"
    finally:
        shutil.rmtree(d, ignore_errors=True)


def minimize(zark, units):
    keep = list(units)
    changed = True
    while changed and len(keep) > 1:
        changed = False
        for i in range(len(keep) - 1, -1, -1):
            cand = keep[:i] + keep[i + 1:]
            if not cand:
                continue
            if diverges(zark, cand):
                keep = cand
                changed = True
                break
    return keep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--zark", default=os.environ.get("ZARK", os.path.join(ROOT, "build", "zark")))
    args = ap.parse_args()

    zark = os.path.abspath(args.zark)
    if not os.path.exists(zark):
        print(f"fuzz_prog: no compiler at {zark}", file=sys.stderr)
        return 2
    count = args.count if args.count is not None else (20 if args.quick else 100)
    scratch = os.path.join(ROOT, "scratch", "fuzz_prog")
    failures = 0
    for i in range(count):
        seed = args.seed + i
        units = generate(seed)
        want = expected(units)
        d = tempfile.mkdtemp(prefix="zarkfuzz-")
        try:
            status, results = run_program(zark, render(units), want, d)
        finally:
            shutil.rmtree(d, ignore_errors=True)
        if status == "ok":
            if not args.quick:
                print(f"seed {seed}: ok")
            continue
        failures += 1
        if status == "invalid":
            print(f"seed {seed}: program did not compile in any mode (compiler bug or invalid generation)")
            if results:
                for line in results[0][3].splitlines()[:8]:
                    print(f"    {line}")
            if args.keep:
                os.makedirs(scratch, exist_ok=True)
                full = os.path.join(scratch, f"invalid{seed}.zk")
                with open(full, "w") as f:
                    f.write(render(units))
                print(f"  saved {full}")
            continue
        print(f"seed {seed}: DIVERGENCE")
        if results is None:
            print("  timeout")
            continue
        for flags, rc, out, err in results:
            label = " ".join(flags) if flags else "native"
            print(f"  [{label}] exit {rc}")
            olen = len(out.splitlines())
            wlen = len(want.splitlines())
            if out != want:
                if olen != wlen:
                    print(f"    expected {wlen} lines, got {olen}")
                for a, b in zip(want.splitlines(), out.splitlines()):
                    if a != b:
                        print(f"    want: {a}")
                        print(f"    got:  {b}")
                        break
            if err:
                for line in err.splitlines()[:6]:
                    print(f"    {line}")
        if args.keep:
            os.makedirs(scratch, exist_ok=True)
            full = os.path.join(scratch, f"seed{seed}.zk")
            with open(full, "w") as f:
                f.write(render(units))
            with open(os.path.join(scratch, f"seed{seed}.expected"), "w") as f:
                f.write(want)
            print(f"  saved {full}")
            small = minimize(zark, units)
            mpath = os.path.join(scratch, f"seed{seed}.min.zk")
            with open(mpath, "w") as f:
                f.write(render(small))
            with open(os.path.join(scratch, f"seed{seed}.min.expected"), "w") as f:
                f.write(expected(small))
            print(f"  minimal {mpath} ({len(small)} units)")
    if failures:
        print(f"fuzz_prog: {failures}/{count} programs failed")
        return 1
    print(f"fuzz_prog: {count} programs ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
