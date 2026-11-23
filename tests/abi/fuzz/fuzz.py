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
    "F2": [("x", "f32"), ("y", "f32")],
    "F3": [("x", "f32"), ("y", "f32"), ("z", "f32")],
    "U3": [("a", "u8"), ("b", "u8"), ("c", "u8")],
    "I3": [("a", "i32"), ("b", "i32"), ("c", "i32")],
    "BC": [("b", "bool"), ("c", "i8")],
    "A3": [("a", "i32[3]")],
    "E": [],
}

UNIONS = {
    "UD": [("A", "f64")],
    "UDI": [("A", "f64"), ("B", "i32")],
    "UFD": [("A", "f32"), ("B", "f64")],
    "UFF": [("A", "f32"), ("B", "f32")],
    "UIF": [("A", "i32"), ("B", "f32")],
    "UDD": [("A", "f64"), ("B", "f64")],
    "UF2": [("A", "F2"), ("B", "f64")],
    "UP": [("A", "P"), ("B", "f32")],
    "UBig": [("A", "D2"), ("B", "i64")],
}

ORDER = ["P", "M", "D2", "Big", "Mix", "Nest", "F2", "F3", "U3", "I3", "BC", "A3", "E",
         "UD", "UDI", "UFD", "UFF", "UIF", "UDD", "UF2", "UP", "UBig"]

SIZES = {"i8": 1, "u8": 1, "bool": 1, "i16": 2, "u16": 2, "i32": 4, "u32": 4, "f32": 4, "i64": 8, "u64": 8, "f64": 8}

KNOWN_BROKEN = set()

QUICK = {
    "layout",
    "direct_p",
    "direct_24",
    "direct_char",
    "direct_f3",
    "direct_bc",
    "direct_a3",
    "direct_e_mix",
    "indirect_p",
    "indirect_f3_ret",
    "export_p",
    "export_struct",
    "export_big",
    "export_f3_ret",
    "callback_p",
    "callback_big",
    "callback_many",
    "callback_f3_ret",
    "callback_e_ret",
}


def array_parts(t):
    if t.endswith("]") and "[" in t:
        i = t.find("[")
        return t[:i], int(t[i + 1:-1])
    return None


def is_struct(t):
    return t in STRUCTS


def round_up(n, a):
    return (n + a - 1) // a * a


def layout(t):
    if t in SIZES:
        return SIZES[t], SIZES[t]
    a = array_parts(t)
    if a is not None:
        size, align = layout(a[0])
        return size * a[1], align
    if t in UNIONS:
        size = 0
        align = 8
        for _, ft in UNIONS[t]:
            fs, fa = layout(ft)
            size = max(size, fs)
            align = max(align, fa)
        return round_up(4, align) + round_up(size, align), align
    off = 0
    align = 1
    for _, ft in STRUCTS[t]:
        fs, fa = layout(ft)
        off = round_up(off, fa) + fs
        align = max(align, fa)
    return round_up(off, align), align


def offsets(t):
    if t in UNIONS:
        return [("tag", 0), ("u", round_up(4, layout(t)[1]))]
    out = []
    off = 0
    for f, ft in STRUCTS[t]:
        fs, fa = layout(ft)
        off = round_up(off, fa)
        out.append((f, off))
        off += fs
    return out


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
    a = array_parts(t)
    if a is not None:
        return [make_value(a[0], ctr) for _ in range(a[1])]
    if t in UNIONS:
        tag = ctr[0] % len(UNIONS[t])
        return {"tag": tag, "p": make_value(UNIONS[t][tag][1], ctr)}
    return {f: make_value(ft, ctr) for f, ft in STRUCTS[t]}


def leaf_sum(v):
    if isinstance(v, dict):
        return sum(leaf_sum(x) for x in v.values())
    if isinstance(v, list):
        return sum(leaf_sum(x) for x in v)
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
    a = array_parts(t)
    if a is not None:
        return "[" + ", ".join(zlit(a[0], x) for x in v) + "]"
    if t in UNIONS:
        f, ft = UNIONS[t][v["tag"]]
        return f"{t}::{f}({zlit(ft, v['p'])})"
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
    a = array_parts(t)
    if a is not None:
        return "{ " + ", ".join(clit(a[0], x) for x in v) + " }"
    if t in UNIONS:
        f, ft = UNIONS[t][v["tag"]]
        return f"({t}){{ .tag = {v['tag']}, .u.{f} = {clit(ft, v['p'])} }}"
    fields = []
    for f, ft in STRUCTS[t]:
        fields.append(f".{f} = {clit(ft, v[f])}")
    return "(" + t + "){ " + ", ".join(fields) + " }"


def csum(t, var):
    if t in SCALARS:
        return f"((int64_t){var})"
    a = array_parts(t)
    if a is not None:
        return "(" + " + ".join(csum(a[0], f"{var}[{i}]") for i in range(a[1])) + ")"
    if t in UNIONS:
        arms = [f"{var}.tag == {i} ? ({i} + {csum(ft, f'{var}.u.{f}')})" for i, (f, ft) in enumerate(UNIONS[t])]
        return "(" + " : ".join(arms) + " : -1000000)"
    parts = [csum(ft, f"{var}.{f}") for f, ft in STRUCTS[t]]
    return "(" + " + ".join(parts) + ")" if parts else "0"


def zsum(t, var):
    if t in SCALARS:
        return f"({var} as i64)"
    a = array_parts(t)
    if a is not None:
        return "(" + " + ".join(zsum(a[0], f"{var}[{i}]") for i in range(a[1])) + ")"
    if t in UNIONS:
        return f"usum_{t}({var})"
    parts = [zsum(ft, f"{var}.{f}") for f, ft in STRUCTS[t]]
    return "(" + " + ".join(parts) + ")" if parts else "0"


def c_field(f, ft):
    a = array_parts(ft)
    if a is not None:
        return f"{ctype(a[0])} {f}[{a[1]}];"
    return f"{ctype(ft)} {f};"


def z_field(f, ft):
    a = array_parts(ft)
    if a is not None:
        return f"{zktype(a[0])}[{a[1]}] {f};"
    return f"{zktype(ft)} {f};"


def c_structs():
    out = []
    for name in ORDER:
        if name in UNIONS:
            fields = " ".join(c_field(f, ft) for f, ft in UNIONS[name])
            out.append(f"typedef struct {{ int32_t tag; _Alignas(8) union {{ {fields} }} u; }} {name};")
            continue
        fields = " ".join(c_field(f, ft) for f, ft in STRUCTS[name])
        out.append(f"typedef struct {{ {fields} }} {name};")
    return out


def z_structs():
    out = []
    for name in ORDER:
        if name in UNIONS:
            fields = " ".join(z_field(f, ft) for f, ft in UNIONS[name])
            out.append(f"union {name} {{ {fields} }}")
            continue
        fields = " ".join(z_field(f, ft) for f, ft in STRUCTS[name])
        out.append(f"struct {name} {{ {fields} }}")
    for name in ORDER:
        if name in UNIONS:
            arms = " ".join(f".{f}(x) => {{ return {i} + {zsum(ft, 'x')}; }}" for i, (f, ft) in enumerate(UNIONS[name]))
            out.append(f"i64 usum_{name}({name} v) {{ match v {{ {arms} }} return -1000000; }}")
    return out


def render_layout_zk():
    lines = z_structs()
    lines.append("")
    lines.append("extern void c_layout();")
    lines.append("void main() {")
    lines.append("    c_layout();")
    for name in ORDER:
        lines.append(f"    println(\"Z size {name} {{sizeof({name})}} {{alignof({name})}}\");")
        if name in UNIONS:
            continue
        lines.append(f"    {name} s_{name};")
        for f, _ in STRUCTS[name]:
            lines.append(f"    const u64 o_{name}_{f} = (&s_{name}.{f} as u64) - (&s_{name} as u64);")
            lines.append(f"    println(\"Z off {name}.{f} {{o_{name}_{f}}}\");")
    lines.append("}")
    return "\n".join(lines) + "\n"


def render_layout_c():
    lines = ["#include <stdint.h>", "#include <stdbool.h>", "#include <stddef.h>", "#include <stdio.h>"]
    lines.extend(c_structs())
    lines.append("")
    lines.append("void c_layout(void) {")
    for name in ORDER:
        lines.append(f"    printf(\"C size {name} %zu %zu\\n\", sizeof({name}), _Alignof({name}));")
        for f, _ in offsets(name):
            lines.append(f"    printf(\"C off {name}.{f} %zu\\n\", offsetof({name}, {f}));")
    lines.append("    fflush(stdout);")
    lines.append("}")
    return "\n".join(lines) + "\n"


def check_layout(out):
    got = {}
    for line in out.splitlines():
        p = line.split()
        if len(p) >= 4 and p[0] in ("C", "Z"):
            got[(p[0], p[1], p[2])] = " ".join(p[3:])
    bad = []
    for name in ORDER:
        size, align = layout(name)
        want = {("size", name): f"{size} {align}"}
        for f, off in offsets(name):
            want[("off", f"{name}.{f}")] = str(off)
        for (kind, key), v in want.items():
            sides = ["C"] if kind == "off" and name in UNIONS else ["C", "Z"]
            for side in sides:
                g = got.get((side, kind, key))
                if g != v:
                    bad.append(f"{side} {kind} {key} = {g}, expected {v}")
    return bad


def sig_c(params):
    return ", ".join(f"{ctype(t)} {n}" for t, n in params)


def sig_zk(params):
    return ", ".join(f"{zktype(t)} {n}" for t, n in params)


def fn_ty(params, ret="i64"):
    return "fn(" + ", ".join(zktype(t) for t, _ in params) + ") -> " + zktype(ret)


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
        expected = leaf_sum(ret_value)
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
    if ret in STRUCTS or array_parts(ret) is not None:
        result = f"RESULT {{{zsum(ret, 'r')}}}"
    else:
        result = "RESULT {(r as i64)}"
    if mode == "direct":
        lines.append(f"void main() {{ const auto r = f_{name}({args_zk(params, vals)}); println(\"{result}\"); }}")
    elif mode == "indirect":
        lines.append(f"void main() {{ {fn_ty(params, ret)} fp = f_{name}; const auto r = fp({args_zk(params, vals)}); println(\"{result}\"); }}")
    elif mode == "export":
        lines.append(f"extern i64 run_{name}();")
        lines.append(f"void main() {{ const auto r = run_{name}(); println(\"RESULT {{r}}\"); }}")
    else:
        fnty = fn_ty(params, ret)
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
    if ret in STRUCTS or array_parts(ret) is not None:
        run_body = f"{rt} r = "
        run_ret = csum(ret, "r")
    else:
        run_body = "return (int64_t)"
        run_ret = ""
    if mode in ("direct", "indirect"):
        lines.append(f"{rt} f_{name}({sig}) {{ return {body}; }}")
    elif mode == "export":
        lines.append(f"extern {rt} f_{name}({sig});")
        if run_ret:
            lines.append(f"int64_t run_{name}(void) {{ {run_body}f_{name}({args_c(params, vals)}); return {run_ret}; }}")
        else:
            lines.append(f"int64_t run_{name}(void) {{ return (int64_t)f_{name}({args_c(params, vals)}); }}")
    else:
        lines.append(f"extern {rt} f_{name}({sig});")
        if run_ret:
            lines.append(f"int64_t run_{name}({rt} (*cb)({sig})) {{ {run_body}cb({args_c(params, vals)}); return {run_ret}; }}")
        else:
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


def run_layout(backend):
    case_dir = os.path.join(OUT, "layout")
    os.makedirs(case_dir, exist_ok=True)
    os.chmod(case_dir, 0o755)
    d = os.path.join(case_dir, backend)
    os.makedirs(d, exist_ok=True)
    os.chmod(d, 0o755)
    zk = os.path.join(d, "main.zk")
    c = os.path.join(d, "side.c")
    binp = os.path.join(d, "bin")
    write_file(zk, render_layout_zk())
    write_file(c, render_layout_c())
    args = [ZARK, "build", zk, c, "-o", binp]
    if backend == "llvm":
        args.append("--llvm")
    elif backend == "O":
        args.append("-O")
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode != 0:
        return "BUILD", (p.stdout + p.stderr).strip()
    os.chmod(binp, 0o755)
    try:
        r = subprocess.run([binp], capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", ""
    if r.returncode != 0:
        return "CRASH", (r.stdout + r.stderr).strip()
    bad = check_layout(r.stdout)
    if bad:
        return "FAIL", "\n".join(bad)
    return "PASS", ""


def run_special(name, backend):
    case_dir = os.path.join(OUT, name)
    os.makedirs(case_dir, exist_ok=True)
    os.chmod(case_dir, 0o755)
    d = os.path.join(case_dir, backend)
    os.makedirs(d, exist_ok=True)
    os.chmod(d, 0o755)
    binp = os.path.join(d, "bin")
    zk = os.path.join(ROOT, "tests", "abi", name, "main.zk")
    c = os.path.join(ROOT, "tests", "abi", name, "driver.c")
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
    spill = [("i64", f"a{i}") for i in range(7)] + [("P", "p")]
    return [
        build_case("direct_zero", "direct", []),
        build_case("direct_p", "direct", [("P", "a"), ("P", "b")]),
        build_case("direct_mixed", "direct", [("M", "m")]),
        build_case("direct_16", "direct", [("D2", "d")]),
        build_case("direct_24", "direct", [("Big", "b")]),
        build_case("direct_nest", "direct", [("Nest", "n")]),
        build_case("direct_many", "direct", many),
        build_case("direct_f2", "direct", [("F2", "v")]),
        build_case("direct_f3", "direct", [("F3", "v")]),
        build_case("direct_u3", "direct", [("U3", "v")]),
        build_case("direct_i3", "direct", [("I3", "v")]),
        build_case("direct_bc", "direct", [("BC", "v")]),
        build_case("direct_a3", "direct", [("A3", "v")]),
        build_case("direct_e", "direct", [("E", "v")]),
        build_case("direct_e_mix", "direct", [("E", "v"), ("i64", "x")]),
        build_case("direct_e_ret", "direct", [], ret="E", ret_value={}),
        build_case("direct_char", "direct", [("i8", "c"), ("u8", "u"), ("bool", "b")], [-1, 200, True]),
        build_case("direct_f2_ret", "direct", [], ret="F2", ret_value={"x": 1.0, "y": 2.0}),
        build_case("direct_f3_ret", "direct", [], ret="F3", ret_value={"x": 1.0, "y": 2.0, "z": 3.0}),
        build_case("direct_i3_ret", "direct", [], ret="I3", ret_value={"a": 1, "b": 2, "c": 3}),
        build_case("direct_mixed_ret", "direct", [], ret="M", ret_value={"a": 5, "b": 2.0}),
        build_case("direct_i8_ret", "direct", [], ret="i8", ret_value=-1),
        build_case("direct_u8_ret", "direct", [], ret="u8", ret_value=200),
        build_case("direct_i16_ret", "direct", [], ret="i16", ret_value=-300),
        build_case("direct_u16_ret", "direct", [], ret="u16", ret_value=60000),
        build_case("direct_bool_ret", "direct", [], ret="bool", ret_value=True),
        build_case("indirect_p", "indirect", [("P", "a"), ("P", "b")]),
        build_case("indirect_16", "indirect", [("D2", "d")]),
        build_case("indirect_24", "indirect", [("Big", "b")]),
        build_case("indirect_mixed", "indirect", [("M", "m")]),
        build_case("indirect_f2", "indirect", [("F2", "v")]),
        build_case("indirect_f3", "indirect", [("F3", "v")]),
        build_case("indirect_u3", "indirect", [("U3", "v")]),
        build_case("indirect_i3", "indirect", [("I3", "v")]),
        build_case("indirect_bc", "indirect", [("BC", "v")]),
        build_case("indirect_a3", "indirect", [("A3", "v")]),
        build_case("indirect_e", "indirect", [("E", "v")]),
        build_case("indirect_e_mix", "indirect", [("E", "v"), ("i64", "x")]),
        build_case("indirect_e_ret", "indirect", [], ret="E", ret_value={}),
        build_case("indirect_char", "indirect", [("i8", "c"), ("u8", "u"), ("bool", "b")], [-1, 200, True]),
        build_case("indirect_f3_ret", "indirect", [], ret="F3", ret_value={"x": 1.0, "y": 2.0, "z": 3.0}),
        build_case("indirect_mixed_ret", "indirect", [], ret="M", ret_value={"a": 5, "b": 2.0}),
        build_case("indirect_many", "indirect", spill),
        build_case("indirect_i8_ret", "indirect", [], ret="i8", ret_value=-1),
        build_case("export_p", "export", [("P", "a"), ("P", "b")]),
        build_case("export_mixed", "export", [("M", "m")]),
        build_case("export_f2", "export", [("F2", "v")]),
        build_case("export_f3", "export", [("F3", "v")]),
        build_case("export_u3", "export", [("U3", "v")]),
        build_case("export_i3", "export", [("I3", "v")]),
        build_case("export_bc", "export", [("BC", "v")]),
        build_case("export_a3", "export", [("A3", "v")]),
        build_case("export_e", "export", [("E", "v")]),
        build_case("export_e_mix", "export", [("E", "v"), ("i64", "x")]),
        build_case("export_e_ret", "export", [], ret="E", ret_value={}),
        build_case("export_char", "export", [("i8", "c"), ("u8", "u"), ("bool", "b")], [-1, 200, True]),
        build_case("export_f3_ret", "export", [], ret="F3", ret_value={"x": 1.0, "y": 2.0, "z": 3.0}),
        build_case("export_i8_ret", "export", [], ret="i8", ret_value=-1),
        build_case("callback_p", "callback", [("P", "a"), ("P", "b")]),
        build_case("callback_big", "callback", [("Big", "b")]),
        build_case("callback_f2", "callback", [("F2", "v")]),
        build_case("callback_f3", "callback", [("F3", "v")]),
        build_case("callback_u3", "callback", [("U3", "v")]),
        build_case("callback_i3", "callback", [("I3", "v")]),
        build_case("callback_bc", "callback", [("BC", "v")]),
        build_case("callback_a3", "callback", [("A3", "v")]),
        build_case("callback_e", "callback", [("E", "v")]),
        build_case("callback_e_mix", "callback", [("E", "v"), ("i64", "x")]),
        build_case("callback_e_ret", "callback", [], ret="E", ret_value={}),
        build_case("callback_f3_ret", "callback", [], ret="F3", ret_value={"x": 1.0, "y": 2.0, "z": 3.0}),
        build_case("callback_many", "callback", spill),
        build_case("callback_char", "callback", [("i8", "c"), ("u8", "u"), ("bool", "b")], [-1, 200, True]),
        build_case("callback_i8_ret", "callback", [], ret="i8", ret_value=-1),
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
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()

    cases = [
        {"name": "layout", "mode": "layout", "params": [], "values": [], "expected": 0, "layout": True},
        {"name": "export_struct", "mode": "export_ret", "params": [], "values": [], "expected": 46, "special": True, "dir": "export_struct"},
        {"name": "export_big", "mode": "export_ret", "params": [], "values": [], "expected": 33, "special": True, "dir": "export_big"},
    ]
    cases += fixed_cases()
    if args.cases > 0:
        cases += random_cases(args.cases, args.seed)
    if args.quick:
        cases = [c for c in cases if c["name"] in QUICK]
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
            if case.get("layout"):
                status, out = run_layout(backend)
            else:
                if case.get("special"):
                    result = run_special(case["dir"], backend)
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
