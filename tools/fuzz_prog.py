#!/usr/bin/env python3
"""Differential fuzzer for whole programs.

One generated program is built four ways (native, --llvm, -O, --release); the
stdout must be identical and every build must exit 0.  A program ends with a
checksum line, so a divergence shows up as one different line.

usage: tools/fuzz_prog.py [--count N] [--seed N] [--quick] [--keep]
                          [--zark PATH]
"""

import argparse
import os
import random
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLAGS = [[], ["--llvm"], ["-O"], ["--release"]]

HELPERS = """u64 mix(u64 h, i64 v) {
    h = (h ^ (v as u64)) *% 1099511628211;
    return h;
}

"""


class Unit:
    def __init__(self, decl, body):
        self.decl = decl
        self.body = body


def u_struct(r, k):
    a, b, c = r.randint(-20, 20), r.randint(-20, 20), r.randint(-20, 20)
    decl = f"""struct P{k} {{ i64 a; i64 b; }}
struct Q{k} {{ P{k} p; i64 c; i64[2] tail; }}
P{k} mkp{k}(i64 a, i64 b) {{ return P{k}{{ .a = a, .b = b }}; }}
i64 sump{k}(P{k}* p) {{ return p.a + p.b; }}
"""
    body = f"""    const auto p{k} = mkp{k}({a}, {b});
    const auto q{k} = Q{k}{{ .p = p{k}, .c = {c}, .tail = [{a}, {b}] }};
    h = mix(h, sump{k}(&q{k}.p) + q{k}.c + q{k}.tail[0] + q{k}.tail[1]);
    h = mix(h, q{k}.p.a *% q{k}.p.b);"""
    return Unit(decl, body)


def u_union(r, k):
    a = r.randint(0, 30)
    e = r.randint(0, 2)
    decl = f"""enum E{k} {{ A, B, C }}
union U{k} {{ i64 Num; bool Flag; }}
i64 useu{k}(U{k} u) {{
    match u {{
        .Num(v) => {{ return v + 1; }}
        .Flag(b) => {{ if (b) {{ return 2; }} return 3; }}
    }}
    return 0;
}}
"""
    body = f"""    const U{k} u{k} = .Num({a});
    h = mix(h, useu{k}(u{k}));
    const U{k} ub{k} = .Flag(true);
    h = mix(h, useu{k}(ub{k}));
    const auto e{k} = E{k}::B;
    if (e{k} is .B) {{ h = mix(h, 5); }} else if (e{k} is .A) {{ h = mix(h, 6); }} else {{ h = mix(h, 7); }}
    match e{k} {{
        .A => {{ h = mix(h, 1); }},
        .B => {{ h = mix(h, 2); }},
        .C => {{ h = mix(h, 3); }},
    }}
    h = mix(h, {e} + {a});"""
    return Unit(decl, body)


def u_list(r, k):
    a, b, c = r.randint(1, 50), r.randint(1, 50), r.randint(1, 50)
    body = f"""    auto l{k} = List<i64>::init(c_allocator());
    l{k}.push({a})?;
    l{k}.push({b})?;
    l{k}.push({c})?;
    h = mix(h, l{k}.get(1));
    h = mix(h, l{k}.len);
    const auto rm{k} = l{k}.remove_at(0)?;
    h = mix(h, rm{k});
    h = mix(h, l{k}.get(0));
    for (auto x{k} : l{k}) {{ h = mix(h, x{k}); }}
    l{k}.deinit();
    auto m{k} = Map<i64>::init(c_allocator());
    m{k}.put("a", {a})?;
    m{k}.put("b", {b})?;
    h = mix(h, m{k}.get("a") catch -1);
    h = mix(h, m{k}.remove("a") as i64);
    h = mix(h, m{k}.get("b") catch -1);
    h = mix(h, m{k}.get("missing") catch -2);
    m{k}.deinit();"""
    return Unit("", body)


def u_defer(r, k):
    a = r.randint(0, 20)
    decl = f"""!i64 may{k}(i64 n) {{
    defer println("d{k}a");
    errdefer println("d{k}b");
    if (n < 0) {{ return error.Neg; }}
    return n *% 2;
}}
"""
    body = f"""    const auto rs{k} = may{k}({a}) catch -99;
    h = mix(h, rs{k});
    const auto re{k} = may{k}(-1) catch -77;
    h = mix(h, re{k});"""
    return Unit(decl, body)


def u_option(r, k):
    a = r.randint(1, 30)
    decl = f"""?i64 opt{k}(i64 n) {{
    if (n > 0) {{ return n; }}
    return null;
}}
"""
    body = f"""    const auto o{k} = opt{k}({a}) orelse -1;
    h = mix(h, o{k});
    const auto n{k} = opt{k}(-{a}) orelse -2;
    h = mix(h, n{k});"""
    return Unit(decl, body)


def u_loop(r, k):
    body = f"""    var{k}: for (auto i{k} : 0..6) {{
        if (i{k} == 2) {{ continue; }}
        if (i{k} == 5) {{ break var{k}; }}
        h = mix(h, i{k});
    }}
    auto w{k} = 0;
    while (w{k} < 5) {{
        w{k} += 1;
        if (w{k} == 3) {{ continue; }}
        h = mix(h, w{k});
    }}"""
    return Unit("", body)


def u_closure(r, k):
    a = r.randint(1, 30)
    body = f"""    auto base{k} = {a};
    const auto cl{k} = [base{k}]() -> i64 {{ return base{k} *% 3; }};
    base{k} += 1;
    h = mix(h, cl{k}());"""
    return Unit("", body)


def u_generic(r, k):
    a, b, c = r.randint(-9, 9), r.randint(-9, 9), r.randint(-9, 9)
    decl = f"""template<T> T pick{k}(T a, T b) {{ return a; }}
struct Box{k}<T> {{ T v; }}
"""
    body = f"""    h = mix(h, pick{k}({a}, {b}));
    const auto bx{k} = Box{k}<i64>{{ .v = {c} }};
    h = mix(h, bx{k}.v);"""
    return Unit(decl, body)


def u_float(r, k):
    a = r.randint(1, 40)
    body = f"""    const auto fx{k} = ({a} as f64) / 7.0;
    println("{{fx{k}:.6}}");
    h = mix(h, (fx{k} * 1000000.0) as i64);
    const auto fy{k} = (fx{k} as f32) as f64;
    println("{{fy{k}:.6}}");
    h = mix(h, (fy{k} * 1000.0) as i64);"""
    return Unit("", body)


def u_scope(r, k):
    a = r.randint(1, 30)
    body = f"""    {{
        defer println("z{k}1");
        defer println("z{k}2");
        h = mix(h, {a});
    }}"""
    return Unit("", body)


def u_slice(r, k):
    a, b, c = r.randint(1, 9), r.randint(1, 9), r.randint(1, 9)
    body = f"""    auto arr{k} = [{a}, {b}, {c}, {a} + {b}];
    auto sl{k} = arr{k}[1..3];
    for (auto [i{k}, x{k}] : sl{k}) {{ h = mix(h, i{k} + x{k}); }}
    const auto ptrl{k} = &arr{k}[2];
    h = mix(h, *ptrl{k});
    sl{k}[0] = {c};
    h = mix(h, arr{k}[1]);"""
    return Unit("", body)


def u_ptr_struct(r, k):
    a, b, c = r.randint(1, 9), r.randint(1, 9), r.randint(1, 9)
    decl = f"""struct N{k} {{ i64[3] xs; i64 n; }}
i64 sumn{k}(N{k}* p) {{
    auto t = 0;
    for (auto i : 0..3) {{ t += p.xs[i]; }}
    return t + p.n;
}}
"""
    body = f"""    const auto nn{k} = N{k}{{ .xs = [{a}, {b}, {c}], .n = {a} }};
    h = mix(h, sumn{k}(&nn{k}));"""
    return Unit(decl, body)


UNITS = [u_struct, u_union, u_list, u_defer, u_option, u_loop,
         u_closure, u_generic, u_float, u_scope, u_slice, u_ptr_struct]


def generate(seed):
    r = random.Random(seed)
    n = r.randint(5, 9)
    kinds = r.choices(UNITS, k=n)
    units = [fn(r, i) for i, fn in enumerate(kinds)]
    return units


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


def run_program(zark, text, workdir):
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
            return None, [(flags, -1, "", "timeout")]
        results.append((flags, p.returncode, p.stdout, p.stderr))
    ran = sum(1 for _, rc, _, _ in results if rc == 0)
    out0 = results[0][2]
    same = all(out == out0 for _, _, out, _ in results)
    if ran == len(results) and same:
        return "ok", results
    if ran == 0:
        return "invalid", results
    return "diverge", results


def diverges(zark, units):
    d = tempfile.mkdtemp(prefix="zarkfuzz-")
    try:
        status, _ = run_program(zark, render(units), d)
        return status == "diverge"
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
        d = tempfile.mkdtemp(prefix="zarkfuzz-")
        try:
            status, results = run_program(zark, render(units), d)
        finally:
            shutil.rmtree(d, ignore_errors=True)
        if status == "ok":
            if not args.quick:
                print(f"seed {seed}: ok")
            continue
        failures += 1
        if status == "invalid":
            print(f"seed {seed}: GENERATOR produced a program that does not compile")
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
            if out:
                print("  stdout:")
                for line in out.splitlines():
                    print(f"    {line}")
            if err:
                print("  stderr:")
                for line in err.splitlines()[:10]:
                    print(f"    {line}")
        if args.keep:
            os.makedirs(scratch, exist_ok=True)
            full = os.path.join(scratch, f"seed{seed}.zk")
            with open(full, "w") as f:
                f.write(render(units))
            print(f"  saved {full}")
            small = minimize(zark, units)
            mpath = os.path.join(scratch, f"seed{seed}.min.zk")
            with open(mpath, "w") as f:
                f.write(render(small))
            print(f"  minimal {mpath} ({len(small)} units)")
    if failures:
        print(f"fuzz_prog: {failures}/{count} programs diverged")
        return 1
    print(f"fuzz_prog: {count} programs ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
