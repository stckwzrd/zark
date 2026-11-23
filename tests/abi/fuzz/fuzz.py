import argparse
import os
import random
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ZARK = os.environ.get("ZARK", os.path.join(ROOT, "build", "zark"))
OUT = os.path.join(ROOT, "build", "abi_fuzz")

SCALARS = {
    "i8": ("int8_t", "i8", "i"),
    "u8": ("uint8_t", "u8", "i"),
    "i16": ("int16_t", "i16", "i"),
    "u16": ("uint16_t", "u16", "i"),
    "i32": ("int32_t", "i32", "i"),
    "u32": ("uint32_t", "u32", "i"),
    "i64": ("int64_t", "i64", "i"),
    "u64": ("uint64_t", "u64", "i"),
    "f32": ("float", "f32", "f"),
    "f64": ("double", "f64", "f"),
    "bool": ("bool", "bool", "b"),
}

STRUCTS = {
    "P": [("x", "i32"), ("y", "i32")],
    "M": [("a", "i64"), ("b", "f64")],
    "D2": [("x", "f64"), ("y", "f64")],
    "Big": [("a", "i64"), ("b", "i64"), ("c", "i64")],
    "Mix": [("a", "f32"), ("b", "i32")],
    "Nest": [("p", "P"), ("z", "i64")],
}

ORDER = ["P", "M", "D2", "Big", "Mix", "Nest"]

KNOWN_BROKEN = {
    ("indirect_p", "native"),
    ("indirect_p", "llvm"),
    ("indirect_p", "O"),
    ("indirect_16", "native"),
    ("export_struct", "native"),
    ("export_struct", "llvm"),
    ("export_struct", "O"),
    ("export_p", "native"),
    ("export_p", "llvm"),
    ("export_p", "O"),
    ("export_mixed", "native"),
    ("callback_p", "native"),
    ("callback_p", "llvm"),
    ("callback_p", "O"),
    ("callback_big", "native"),
    ("callback_big", "llvm"),
    ("callback_big", "O"),
}


def is_struct(t):
    return t in STRUCTS


def ctype(t):
    return SCALARS[t][0] if t in SCALARS else t


def zktype(t):
    return SCALARS[t][1] if t in SCALARS else t


def make_value(t, ctr):
    if t in SCALARS:
        kind = SCALARS[t][2]
        i = ctr[0]
        ctr[0] += 1
        if kind == "f":
            return float((i % 5) + 1)
        if kind == "b":
            return True
        return (i % 9) + 1
    return {f: make_value(ft, ctr) for f, ft in STRUCTS[t]}


def leaf_sum(v):
    if isinstance(v, dict):
        return sum(leaf_sum(x) for x in v.values())
    if isinstance(v, bool):
        return 1 if v else 0
    return int(v)


def zlit(t, v):
    if t in SCALARS:
        kind = SCALARS[t][2]
        if kind == "f":
            return f"{v:.1f}"
        if kind == "b":
            return "true" if v else "false"
        return str(v)
    fields = []
    for f, ft in STRUCTS[t]:
        fields.append(f".{f} = {zlit(ft, v[f])}")
    return t + "{ " + ", ".join(fields) + " }"


def clit(t, v):
    if t in SCALARS:
        kind = SCALARS[t][2]
        if kind == "f":
            return f"{v:.1f}"
        if kind == "b":
            return "true" if v else "false"
        return str(v)
    fields = []
    for f, ft in STRUCTS[t]:
        fields.append(f".{f} = {clit(ft, v[f])}")
    return "(" + t + "){ " + ", ".join(fields) + " }"


def csum(t, var):
    if t in SCALARS:
        return f"((int64_t){var})"
    parts = [csum(ft, f"{var}.{f}") for f, ft in STRUCTS[t]]
    return "(" + " + ".join(parts) + ")"


def zsum(t, var):
    if t in SCALARS:
        return f"({var} as i64)"
    parts = [zsum(ft, f"{var}.{f}") for f, ft in STRUCTS[t]]
    return "(" + " + ".join(parts) + ")"


def c_structs():
    out = []
    for name in ORDER:
        fields = " ".join(f"{ctype(ft)} {f};" for f, ft in STRUCTS[name])
        out.append(f"typedef struct {{ {fields} }} {name};")
    return out


def z_structs():
    out = []
    for name in ORDER:
        fields = " ".join(f"{zktype(ft)} {f};" for f, ft in STRUCTS[name])
        out.append(f"struct {name} {{ {fields} }}")
    return out


def sig_c(params):
    return ", ".join(f"{ctype(t)} {n}" for t, n in params)


def sig_zk(params):
    return ", ".join(f"{zktype(t)} {n}" for t, n in params)


def fn_ty(params):
    return "fn(" + ", ".join(zktype(t) for t, _ in params) + ") -> i64"


def sum_c(params):
    parts = [csum(t, n) for t, n in params]
    return " + ".join(parts) if parts else "0"


def sum_zk(params):
    parts = [zsum(t, n) for t, n in params]
    return " + ".join(parts) if parts else "0"


def args_c(params, vals):
    return ", ".join(clit(t, v) for (t, _), v in zip(params, vals))


def args_zk(params, vals):
    return ", ".join(zlit(t, v) for (t, _), v in zip(params, vals))


def build_case(name, mode, params, values=None, ret="i64", ret_value=None):
    ctr = [0]
    if values is None:
        vals = [make_value(t, ctr) for t, _ in params]
    else:
        vals = values
    if ret_value is None:
        expected = sum(leaf_sum(v) for v in vals)
    else:
        expected = int(ret_value)
    return {
        "name": name,
        "mode": mode,
        "params": params,
        "values": vals,
        "ret": ret,
        "ret_value": ret_value,
        "expected": expected,
    }


def render_zk(case):
    name = case["name"]
    mode = case["mode"]
    params = case["params"]
    vals = case["values"]
    ret = case["ret"]
    rv = case["ret_value"]
    lines = z_structs()
    lines.append("")
    sig = sig_zk(params)
    if mode in ("direct", "indirect"):
        lines.append(f"extern {zktype(ret)} f_{name}({sig});")
    else:
        prefix = "export " if mode == "export" else ""
        body = "0" if ret != "i64" else sum_zk(params)
        if rv is not None:
            body = zlit(ret, rv)
        lines.append(f"{prefix}{zktype(ret)} f_{name}({sig}) {{ return {body}; }}")
    lines.append("")
    if mode == "direct":
        lines.append(f"void main() {{ const auto r = f_{name}({args_zk(params, vals)}); println(\"RESULT {{(r as i64)}}\"); }}")
    elif mode == "indirect":
        lines.append(f"void main() {{ fn({', '.join(zktype(t) for t, _ in params)}) -> {zktype(ret)} fp = f_{name}; const auto r = fp({args_zk(params, vals)}); println(\"RESULT {{(r as i64)}}\"); }}")
    elif mode == "export":
        lines.append(f"extern i64 run_{name}();")
        lines.append(f"void main() {{ const auto r = run_{name}(); println(\"RESULT {{r}}\"); }}")
    else:
        fnty = f"fn({', '.join(zktype(t) for t, _ in params)}) -> {zktype(ret)}"
        lines.append(f"extern i64 run_{name}({fnty} cb);")
        lines.append(f"void main() {{ {fnty} fp = f_{name}; const auto r = run_{name}(fp); println(\"RESULT {{r}}\"); }}")
    return "\n".join(lines) + "\n"


def render_c(case):
    name = case["name"]
    mode = case["mode"]
    params = case["params"]
    vals = case["values"]
    lines = ["#include <stdint.h>", "#include <stdbool.h>", "#include <stdio.h>"]
    lines.extend(c_structs())
    lines.append("")
    sig = sig_c(params)
    ret = case["ret"]
    rv = case["ret_value"]
    body = clit(ret, rv) if rv is not None else sum_c(params)
    rt = ctype(ret)
    if mode in ("direct", "indirect"):
        lines.append(f"{rt} f_{name}({sig}) {{ return {body}; }}")
    elif mode == "export":
        lines.append(f"extern {rt} f_{name}({sig});")
        lines.append(f"int64_t run_{name}(void) {{ return (int64_t)f_{name}({args_c(params, vals)}); }}")
    else:
        lines.append(f"extern {rt} f_{name}({sig});")
        lines.append(f"int64_t run_{name}({rt} (*cb)({sig})) {{ return (int64_t)cb({args_c(params, vals)}); }}")
    return "\n".join(lines) + "\n"


def write_file(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def run_one(case, backend):
    case_dir = os.path.join(OUT, case["name"])
    os.makedirs(case_dir, exist_ok=True)
    os.chmod(case_dir, 0o755)
    d = os.path.join(case_dir, backend)
    os.makedirs(d, exist_ok=True)
    os.chmod(d, 0o755)
    zk = os.path.join(d, "main.zk")
    c = os.path.join(d, "side.c")
    binp = os.path.join(d, "bin")
    write_file(zk, render_zk(case))
    write_file(c, render_c(case))
    args = [ZARK, "build", zk, c, "-o", binp]
    if backend == "llvm":
        args.append("--llvm")
    elif backend == "O":
        args.append("-O")
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode != 0:
        return ("build", p.returncode, (p.stdout + p.stderr).strip(), None)
    os.chmod(binp, 0o755)
    try:
        r = subprocess.run([binp], capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        return ("timeout", None, "", None)
    out = r.stdout + r.stderr
    m = None
    for line in out.splitlines():
        mm = re.match(r"RESULT (-?[0-9]+)$", line.strip())
        if mm:
            m = int(mm.group(1))
    return ("run", r.returncode, out.strip(), m)


def status_for(result, expected):
    kind, code, out, got = result
    if kind != "run":
        return "BUILD" if kind == "build" else "TIMEOUT", out
    if code != 0:
        return "CRASH", out
    if got == expected:
        return "PASS", out
    return "FAIL", out


def run_export_struct(backend):
    case_dir = os.path.join(OUT, "export_struct")
    os.makedirs(case_dir, exist_ok=True)
    os.chmod(case_dir, 0o755)
    d = os.path.join(case_dir, backend)
    os.makedirs(d, exist_ok=True)
    os.chmod(d, 0o755)
    binp = os.path.join(d, "bin")
    zk = os.path.join(ROOT, "tests", "abi", "export_struct", "main.zk")
    c = os.path.join(ROOT, "tests", "abi", "export_struct", "driver.c")
    args = [ZARK, "build", zk, c, "-o", binp]
    if backend == "llvm":
        args.append("--llvm")
    elif backend == "O":
        args.append("-O")
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode != 0:
        return ("build", p.returncode, (p.stdout + p.stderr).strip(), None)
    os.chmod(binp, 0o755)
    try:
        r = subprocess.run([binp], capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        return ("timeout", None, "", None)
    out = r.stdout + r.stderr
    m = None
    for line in out.splitlines():
        mm = re.match(r"RESULT (-?[0-9]+)$", line.strip())
        if mm:
            m = int(mm.group(1))
    return ("run", r.returncode, out.strip(), m)


def fixed_cases():
    many = [("i64", f"a{i}") for i in range(9)] + [("P", "p")]
    return [
        build_case("direct_zero", "direct", []),
        build_case("direct_p", "direct", [("P", "a"), ("P", "b")]),
        build_case("direct_mixed", "direct", [("M", "m")]),
        build_case("direct_16", "direct", [("D2", "d")]),
        build_case("direct_24", "direct", [("Big", "b")]),
        build_case("direct_nest", "direct", [("Nest", "n")]),
        build_case("direct_many", "direct", many),
        build_case("direct_char", "direct", [("i8", "c"), ("u8", "u"), ("bool", "b")], [-1, 200, True]),
        build_case("direct_i8_ret", "direct", [], ret="i8", ret_value=-1),
        build_case("direct_u8_ret", "direct", [], ret="u8", ret_value=200),
        build_case("direct_i16_ret", "direct", [], ret="i16", ret_value=-300),
        build_case("direct_u16_ret", "direct", [], ret="u16", ret_value=60000),
        build_case("direct_bool_ret", "direct", [], ret="bool", ret_value=True),
        build_case("indirect_p", "indirect", [("P", "a"), ("P", "b")]),
        build_case("indirect_16", "indirect", [("D2", "d")]),
        build_case("export_p", "export", [("P", "a"), ("P", "b")]),
        build_case("export_mixed", "export", [("M", "m")]),
        build_case("callback_p", "callback", [("P", "a"), ("P", "b")]),
        build_case("callback_big", "callback", [("Big", "b")]),
    ]


def random_cases(count, seed):
    rng = random.Random(seed)
    pool = list(SCALARS.keys()) + list(STRUCTS.keys())
    out = []
    for i in range(count):
        n = rng.randint(0, 10)
        params = [(rng.choice(pool), f"a{j}") for j in range(n)]
        mode = "direct"
        out.append(build_case(f"rnd_{seed}_{i}", mode, params))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=int, default=0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--backends", default="native,llvm,O")
    ap.add_argument("--only", default="")
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()

    cases = [{"name": "export_struct", "mode": "export_ret", "params": [], "values": [], "expected": 46, "special": True}]
    cases += fixed_cases()
    if args.cases > 0:
        cases += random_cases(args.cases, args.seed)
    if args.only:
        cases = [c for c in cases if args.only in c["name"]]

    if not os.path.exists(ZARK):
        print(f"compiler not found: {ZARK}")
        return 2

    backends = [b for b in args.backends.split(",") if b]
    os.makedirs(OUT, exist_ok=True)
    os.chmod(OUT, 0o755)
    unexpected = 0
    broken = 0
    print(f"{'case':24} {'mode':9} " + " ".join(f"{b:8}" for b in backends))
    for case in cases:
        row = []
        detail = ""
        for backend in backends:
            if case.get("special"):
                result = run_export_struct(backend)
            else:
                result = run_one(case, backend)
            status, out = status_for(result, case["expected"])
            known = (case["name"], backend) in KNOWN_BROKEN
            if status == "PASS":
                row.append("FIXED" if known else "PASS")
            elif known and not args.strict:
                row.append("KNOWN-BROKEN")
                broken += 1
                if not detail:
                    detail = out.replace("\n", " | ")[:180]
            else:
                row.append(status)
                unexpected += 1
                if not detail:
                    detail = out.replace("\n", " | ")[:180]
        print(f"{case['name']:24} {case['mode']:9} " + " ".join(f"{r:8}" for r in row))
        if detail:
            print(f"    {detail}")
    print()
    print(f"unexpected: {unexpected}, known-broken: {broken}")
    return 1 if unexpected else 0


if __name__ == "__main__":
    sys.exit(main())
