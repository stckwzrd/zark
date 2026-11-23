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
    "SU": [("u", "UD")],
    "SUA": [("a", "UFF[1]")],
    "SUX": [("x", "i32"), ("u", "UFD"), ("y", "f32")],
    "F1": [("x", "f32")],
    "F4": [("x", "f32"), ("y", "f32"), ("z", "f32"), ("w", "f32")],
    "D1": [("x", "f64")],
    "D3": [("x", "f64"), ("y", "f64"), ("z", "f64")],
    "D4": [("x", "f64"), ("y", "f64"), ("z", "f64"), ("w", "f64")],
    "NH": [("p", "F2"), ("z", "f32")],
    "ND": [("a", "D2"), ("b", "D2")],
    "HA": [("v", "f32[3]")],
    "HDA": [("a", "f64"), ("v", "f64[2]")],
    "HE": [("a", "f32"), ("e", "E"), ("b", "f32")],
    "HZ": [("a", "f32"), ("b", "f32"), ("z", "f32[0]")],
    "F5": [("v", "f32[5]")],
    "FD": [("a", "f32"), ("b", "f64")],
    "AL16": [("a", "i64"), ("b", "i64")],
    "AL16F": [("v", "f32[4]")],
    "AL16N": [("x", "AL16")],
    "AL16FN": [("v", "AL16F")],
    "B17": [("a", "u8[17]")],
    "B32": [("a", "i64"), ("b", "i64"), ("c", "i64"), ("d", "i64")],
    "S5": [("a", "u8[5]")],
    "S6": [("a", "i16"), ("b", "i16"), ("c", "i16")],
    "S7": [("a", "u8[7]")],
}

ALIGNED = {"AL16": 16, "AL16F": 16}

ARM = ["F1", "F4", "D1", "D3", "D4", "NH", "ND", "HA", "HDA", "HE", "HZ", "F5", "FD", "AL16", "AL16F",
       "AL16N", "AL16FN", "B17", "B32", "S5", "S6", "S7"]

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
         "UD", "UDI", "UFD", "UFF", "UIF", "UDD", "UF2", "UP", "UBig", "SU", "SUA", "SUX"] + ARM

VECS = {
    "f32x4": ("float", 4, "f"),
    "f64x2": ("double", 2, "f"),
    "i32x4": ("int32_t", 4, "i"),
    "u8x16": ("uint8_t", 16, "i"),
    "i64x2": ("int64_t", 2, "i"),
}

SHORT_VECS = {
    "f32x2": ("float", 2, "f"),
    "i16x4": ("int16_t", 4, "i"),
    "u8x8": ("uint8_t", 8, "i"),
}

ALL_VECS = {**VECS, **SHORT_VECS}

ARM_HOST = os.uname().machine in ("aarch64", "arm64")

SIZES = {"i8": 1, "u8": 1, "bool": 1, "i16": 2, "u16": 2, "i32": 4, "u32": 4, "f32": 4, "i64": 8, "u64": 8, "f64": 8}

VA_CODE = {"i8": "i", "u8": "i", "bool": "i", "i16": "i", "u16": "i", "i32": "i", "u32": "u",
           "i64": "l", "u64": "l", "f32": "d", "f64": "d"}

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
    "direct_ud",
    "direct_uff_ret",
    "indirect_ufd",
    "export_uf2",
    "export_udd_ret",
    "callback_su",
    "callback_sua_ret",
    "callback_union_mix",
    "variadic_vsum_d",
    "variadic_fix_m",
    "variadic_fix_big",
    "variadic_ret_big_many",
    "variadic_promote",
    "variadic_var_structs",
    "variadic_var_spill",
    "direct_hfa_mix",
    "direct_d4",
    "direct_spill_fp",
    "direct_al16_odd",
    "indirect_nh_ret",
    "indirect_he_ret",
    "export_al16f",
    "export_s7_ret",
    "export_b17",
    "callback_spill_hfa",
    "callback_ha_ret",
    "callback_hz",
    "variadic_fix_hfa",
    "variadic_var_hfa",
    "direct_f32x4",
    "indirect_u8x16_ret",
    "export_i64x2",
    "callback_f64x2_ret",
    "export_vec_spill_f32x4",
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
    align = ALIGNED.get(t, 1)
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
    if t in ALL_VECS:
        return "v_" + t
    return SCALARS[t][0] if t in SCALARS else t


def zktype(t):
    return SCALARS[t][1] if t in SCALARS else t


def make_value(t, ctr):
    if t in ALL_VECS:
        _, n, kind = ALL_VECS[t]
        out = []
        for _ in range(n):
            i = ctr[0]
            ctr[0] += 1
            out.append(float((i % 5) + 1) if kind == "f" else (i % 9) + 1)
        return out
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
    if t in ALL_VECS:
        lane = "f32" if ALL_VECS[t][2] == "f" else "i64"
        return f"{t}(" + ", ".join(zlit(lane, x) for x in v) + ")"
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
    if t in ALL_VECS:
        lane = "f32" if ALL_VECS[t][2] == "f" else "i64"
        return f"({ctype(t)}){{ " + ", ".join(clit(lane, x) for x in v) + " }"
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
    if t in ALL_VECS:
        return "(" + " + ".join(f"((int64_t){var}[{i}])" for i in range(ALL_VECS[t][1])) + ")"
    a = array_parts(t)
    if a is not None:
        return "(" + " + ".join(csum(a[0], f"{var}[{i}]") for i in range(a[1])) + ")" if a[1] else "0"
    if t in UNIONS:
        arms = [f"{var}.tag == {i} ? ({i} + {csum(ft, f'{var}.u.{f}')})" for i, (f, ft) in enumerate(UNIONS[t])]
        return "(" + " : ".join(arms) + " : -1000000)"
    parts = [csum(ft, f"{var}.{f}") for f, ft in STRUCTS[t]]
    return "(" + " + ".join(parts) + ")" if parts else "0"


def zsum(t, var):
    if t in SCALARS:
        return f"({var} as i64)"
    if t in ALL_VECS:
        return "(" + " + ".join(f"({var}[{i}] as i64)" for i in range(ALL_VECS[t][1])) + ")"
    a = array_parts(t)
    if a is not None:
        return "(" + " + ".join(zsum(a[0], f"{var}[{i}]") for i in range(a[1])) + ")" if a[1] else "0"
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
    out = [f"typedef {c} v_{t} __attribute__((vector_size({n * SIZES[t[:t.index('x')]]})));" for t, (c, n, _) in ALL_VECS.items()]
    for name in ORDER:
        if name in UNIONS:
            fields = " ".join(c_field(f, ft) for f, ft in UNIONS[name])
            out.append(f"typedef struct {{ int32_t tag; _Alignas(8) union {{ {fields} }} u; }} {name};")
            continue
        fields = " ".join(c_field(f, ft) for f, ft in STRUCTS[name])
        attr = f"__attribute__((aligned({ALIGNED[name]}))) " if name in ALIGNED else ""
        out.append(f"typedef struct {attr}{{ {fields} }} {name};")
    return out


def z_structs():
    out = []
    for name in ORDER:
        if name in UNIONS:
            fields = " ".join(z_field(f, ft) for f, ft in UNIONS[name])
            out.append(f"union {name} {{ {fields} }}")
            continue
        fields = " ".join(z_field(f, ft) for f, ft in STRUCTS[name])
        prefix = f"align({ALIGNED[name]}) " if name in ALIGNED else ""
        out.append(f"{prefix}struct {name} {{ {fields} }}")
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
    if ret in STRUCTS or ret in UNIONS or ret in ALL_VECS or array_parts(ret) is not None:
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
    if ret in STRUCTS or ret in UNIONS or ret in ALL_VECS or array_parts(ret) is not None:
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


def va_code(t):
    if t in VA_CODE:
        return VA_CODE[t]
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$&*+-/:;<=>?@^_~"[ORDER.index(t)]


def va_lit(t, v):
    if t in SCALARS and SCALARS[t][2] != "b":
        return f"({zlit(t, v)} as {zktype(t)})"
    return zlit(t, v)


def va_case(name, fixed, var, fixed_vals=None, ret="i64", ret_value=None, vsum=None):
    ctr = [0]
    fv = fixed_vals if fixed_vals is not None else [make_value(t, ctr) for t, _ in fixed]
    vals = [make_value(t, ctr) if v is None else v for t, v in var]
    expected = sum(leaf_sum(v) for v in fv) + sum(leaf_sum(v) for v in vals)
    if ret_value is not None:
        expected += leaf_sum(ret_value)
    return {
        "name": name,
        "mode": "variadic",
        "params": fixed,
        "values": fv,
        "var": [t for t, _ in var],
        "var_values": vals,
        "ret": ret,
        "ret_value": ret_value,
        "expected": expected,
        "vsum": vsum,
    }


def render_va_zk(case):
    name = case["name"]
    params = case["params"]
    ret = case["ret"]
    lines = z_structs()
    lines.append("")
    if case["vsum"]:
        lines.append(f"extern i64 f_{name}(i32 n, ...);")
        head = [str(len(case["var"]))]
    else:
        sig = sig_zk(params)
        if sig:
            sig += ", "
        lines.append(f"extern {zktype(ret)} f_{name}({sig}u8* fmt, ...);")
        fmt = "".join(va_code(t) for t in case["var"])
        head = [zlit(t, v) for (t, _), v in zip(params, case["values"])] + [f'"{fmt}"']
    var = [va_lit(t, v) for t, v in zip(case["var"], case["var_values"])]
    if ret in STRUCTS or ret in UNIONS:
        result = f"RESULT {{{zsum(ret, 'r')}}}"
    else:
        result = "RESULT {r}"
    lines.append("")
    lines.append(f"void main() {{ const auto r = f_{name}({', '.join(head + var)}); println(\"{result}\"); }}")
    return "\n".join(lines) + "\n"


def render_va_c(case):
    name = case["name"]
    params = case["params"]
    ret = case["ret"]
    lines = ["#include <stdint.h>", "#include <stdbool.h>", "#include <stdarg.h>"]
    lines.extend(c_structs())
    lines.append("")
    if case["vsum"]:
        t = case["vsum"]
        lines.append(f"int64_t f_{name}(int32_t n, ...) {{")
        lines.append("    va_list ap; va_start(ap, n); int64_t s = 0;")
        lines.append(f"    for (int32_t i = 0; i < n; i++) s += (int64_t)va_arg(ap, {t});")
        lines.append("    va_end(ap); return s;")
        lines.append("}")
        return "\n".join(lines) + "\n"
    sig = sig_c(params)
    if sig:
        sig += ", "
    arms = [
        "case 'i': s += va_arg(ap, int); break;",
        "case 'u': s += va_arg(ap, unsigned); break;",
        "case 'l': s += va_arg(ap, int64_t); break;",
        "case 'd': s += (int64_t)va_arg(ap, double); break;",
    ]
    for t in sorted(set(case["var"])):
        if t not in VA_CODE:
            arms.append(f"case '{va_code(t)}': {{ {t} v = va_arg(ap, {t}); s += {csum(t, 'v')}; break; }}")
    lines.append(f"{ctype(ret)} f_{name}({sig}const char *fmt, ...) {{")
    lines.append(f"    va_list ap; va_start(ap, fmt); int64_t s = {sum_c(params)};")
    lines.append("    for (const char *p = fmt; *p; p++) {")
    lines.append("        switch (*p) {")
    for a in arms:
        lines.append(f"        {a}")
    lines.append("        }")
    lines.append("    }")
    lines.append("    va_end(ap);")
    if ret in STRUCTS:
        lines.append(f"    {ret} r = {clit(ret, case['ret_value'])}; r.{STRUCTS[ret][0][0]} += s; return r;")
    else:
        lines.append("    return s;")
    lines.append("}")
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
    if case["mode"] == "variadic":
        write_file(zk, render_va_zk(case))
        write_file(c, render_va_c(case))
    else:
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
    ] + union_cases() + variadic_cases() + arm_cases() + vec_cases(VECS) + (vec_cases(SHORT_VECS) if ARM_HOST else [])


def vec_cases(vecs):
    out = []
    first = list(vecs)[0]
    for mode in ("direct", "indirect", "export", "callback"):
        for t in vecs:
            out.append(build_case(f"{mode}_{t}", mode, [(t, "a"), ("i32", "x"), (t, "b")]))
            out.append(build_case(f"{mode}_{t}_ret", mode, [], ret=t, ret_value=make_value(t, [1])))
        spill = [("f64", "x")] + [(first, f"v{i}") for i in range(6)] + [("D2", "d"), (first, "w"), ("i64", "n")]
        out.append(build_case(f"{mode}_vec_spill_{first}", mode, spill))
    out.append(va_case(f"variadic_fix_{first}", [(first, f"v{i}") for i in range(7)], [("D2", None), ("f64", None), ("M", None)]))
    return out


def arm_cases():
    out = []
    dbl8 = [("f64", f"d{i}") for i in range(8)]
    int7 = [("i64", f"i{i}") for i in range(7)]
    for mode in ("direct", "indirect", "export", "callback"):
        for t in ARM:
            n = t.lower()
            out.append(build_case(f"{mode}_{n}", mode, [(t, "a"), (t, "b")]))
            out.append(build_case(f"{mode}_{n}_ret", mode, [], ret=t, ret_value=make_value(t, [1])))
        out.append(build_case(f"{mode}_spill_hfa", mode, [("f64", "x"), ("D4", "a"), ("F4", "b"), ("f64", "y"), ("D3", "c"), ("f32", "z")]))
        out.append(build_case(f"{mode}_spill_fp", mode, dbl8 + [("F2", "a"), ("f32", "x"), ("HA", "b"), ("D1", "c")]))
        out.append(build_case(f"{mode}_spill_int", mode, int7 + [("AL16", "a"), ("i32", "x"), ("S7", "b"), ("B32", "c"), ("AL16F", "d")]))
        out.append(build_case(f"{mode}_al16_odd", mode, [("i32", "x"), ("AL16", "a"), ("i64", "y"), ("AL16N", "b"), ("AL16FN", "c")]))
        out.append(build_case(f"{mode}_hfa_mix", mode, [("F1", "a"), ("i8", "c"), ("D3", "b"), ("u16", "u"), ("NH", "n"), ("FD", "m"), ("B17", "s")], [{"x": 1.0}, -3, {"x": 1.0, "y": 2.0, "z": 3.0}, 60000, {"p": {"x": 1.0, "y": 2.0}, "z": 4.0}, {"a": 2.0, "b": 3.0}, {"a": list(range(1, 18))}]))
    hfas = [(t, None) for t in ["F1", "F4", "D1", "D3", "D4", "NH", "ND", "HA", "HDA", "HE", "AL16F", "AL16FN"]]
    others = [(t, None) for t in ["HZ", "F5", "FD", "AL16", "B17", "B32", "S5", "S6", "S7"]]
    out += [
        va_case("variadic_fix_hfa", [("D4", "a"), ("F2", "b")], [("f64", None), ("i64", None), ("F4", None), ("f64", None)]),
        va_case("variadic_fix_al16", [("i32", "x"), ("AL16N", "a")], [("i64", None), ("AL16", None), ("AL16N", None), ("f64", None)]),
        va_case("variadic_var_hfa", [], hfas),
        va_case("variadic_var_arm", [], others),
        va_case("variadic_ret_d4", [], [("f64", None), ("i64", None)], ret="D4", ret_value={"x": 1.0, "y": 2.0, "z": 3.0, "w": 4.0}),
        va_case("variadic_ret_s6", [], [("i64", None), ("f64", None)], ret="S6", ret_value={"a": 1, "b": 2, "c": 3}),
    ]
    return out


def union_cases():
    out = []
    mix = [("UFF", "a"), ("f64", "x"), ("UDI", "b"), ("UF2", "c"), ("UD", "d"), ("i32", "y")]
    for mode in ("direct", "indirect", "export", "callback"):
        for t in list(UNIONS) + ["SU", "SUA", "SUX"]:
            n = t.lower()
            out.append(build_case(f"{mode}_{n}", mode, [(t, "a"), (t, "b")]))
            out.append(build_case(f"{mode}_{n}_ret", mode, [], ret=t, ret_value=make_value(t, [1])))
        out.append(build_case(f"{mode}_union_mix", mode, mix))
    return out


def variadic_cases():
    ints = [("i64", None)] * 10
    dbls = [("f64", None)] * 12
    mixed = [("i64" if i % 2 == 0 else "f64", None) for i in range(22)]
    two = [("i64", None), ("f64", None)]
    promo = [("i8", -1), ("u8", 200), ("i16", -300), ("u16", 60000), ("bool", True),
             ("f32", 2.5), ("i32", -7), ("u32", 4000000000)]
    structs = [(t, None) for t in ["P", "F2", "M", "D2", "Big", "Mix", "F3", "U3", "BC", "Nest", "I3"]]
    unions = [(t, None) for t in ["UD", "UDI", "UFD", "UFF", "UIF", "UDD", "UF2", "UP", "UBig", "SU", "SUX"]]
    spill = [("i64", None)] * 5 + [("M", None), ("i64", None), ("D2", None), ("F2", None)]
    six = [("i64", f"a{i}") for i in range(6)]
    big = {"a": 1, "b": 2, "c": 3}
    m = {"a": 5, "b": 2.0}
    return [
        va_case("variadic_vsum_l", [], ints, vsum="int64_t"),
        va_case("variadic_vsum_d", [], dbls, vsum="double"),
        va_case("variadic_mixed", [], mixed),
        va_case("variadic_fix_p", [("P", "a")], two),
        va_case("variadic_fix_f2", [("F2", "a")], two),
        va_case("variadic_fix_d2", [("D2", "a")], two),
        va_case("variadic_fix_m", [("M", "a")], two),
        va_case("variadic_fix_big", [("Big", "a")], two),
        va_case("variadic_fix_ud", [("UD", "a")], two),
        va_case("variadic_fix_char", [("i8", "c"), ("u8", "u"), ("bool", "b")], [("i16", -3), ("f64", None)], [-1, 200, True]),
        va_case("variadic_fix_spill", six + [("M", "m")], [("f64", None)] * 3 + [("i64", None), ("P", None)]),
        va_case("variadic_fix_many", [("D2", "a"), ("M", "b"), ("Big", "c"), ("F2", "d")], mixed),
        va_case("variadic_ret_p", [], two, ret="P", ret_value={"x": 1, "y": 2}),
        va_case("variadic_ret_f2", [], two, ret="F2", ret_value={"x": 1.0, "y": 2.0}),
        va_case("variadic_ret_d2", [], two, ret="D2", ret_value={"x": 1.0, "y": 2.0}),
        va_case("variadic_ret_m", [], two, ret="M", ret_value=m),
        va_case("variadic_ret_big", [], two, ret="Big", ret_value=big),
        va_case("variadic_ret_big_many", [("P", "a")], mixed, ret="Big", ret_value=big),
        va_case("variadic_ret_m_fix", [("Big", "a"), ("F2", "b")], mixed, ret="M", ret_value=m),
        va_case("variadic_promote", [], promo),
        va_case("variadic_var_structs", [], structs),
        va_case("variadic_var_unions", [], unions),
        va_case("variadic_var_spill", [], spill),
    ]


def random_cases(count, seed):
    rng = random.Random(seed)
    pool = list(SCALARS.keys()) + list(STRUCTS.keys()) + list(UNIONS.keys())
    out = []
    for i in range(count):
        n = rng.randint(0, 10)
        params = [(rng.choice(pool), f"a{j}") for j in range(n)]
        mode = "direct"
        out.append(build_case(f"rnd_{seed}_{i}", mode, params))
    return out


ORACLE_TARGETS = {
    "aarch64": ("aarch64-linux-gnu", ["--arch", "aarch64", "--os", "linux"]),
    "arm64-apple": ("arm64-apple-macosx", ["--arch", "aarch64", "--os", "macos"]),
}

KEEP_ATTRS = ("signext", "zeroext", "inreg", "sret", "byval", "byref", "alignstack", "inalloca", "preallocated")


def split_top(s, sep=","):
    out = []
    depth = 0
    cur = ""
    for ch in s:
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        if ch == sep and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def take_type(s):
    s = s.strip()
    if s[:1] in "[{<":
        depth = 0
        for i, ch in enumerate(s):
            if ch in "([{<":
                depth += 1
            elif ch in ")]}>":
                depth -= 1
                if depth == 0:
                    return s[:i + 1], s[i + 1:]
    if s.startswith('%"'):
        i = s.index('"', 2)
        return s[:i + 1], s[i + 1:]
    parts = s.split(None, 1)
    return parts[0], parts[1] if len(parts) > 1 else ""


def norm_param(p):
    ty, rest = take_type(p)
    attrs = []
    for tok in split_top(rest, " "):
        name = tok.split("(", 1)[0]
        if name in ("sret", "byval", "byref"):
            attrs.append(name)
        elif name in KEEP_ATTRS:
            attrs.append(tok)
    return " ".join([" ".join(ty.split())] + sorted(attrs))


def norm_params(text):
    return [norm_param(p) for p in split_top(text) if p != "..."] + (["..."] if text.strip().endswith("...") else [])


def flatten(t, types):
    t = t.strip()
    if t in types:
        return flatten(types[t], types)
    if t.startswith("<{") or t.startswith("{"):
        inner = t[2:-2] if t.startswith("<{") else t[1:-1]
        return [x for f in split_top(inner) for x in flatten(f, types)]
    m = re.match(r"\[(\d+) x (.*)\]$", t)
    if m:
        return flatten(m.group(2), types) * int(m.group(1))
    return [t]


def norm_ret(text, types):
    attrs = []
    toks = text.split()
    rest = []
    skip = {"declare", "define", "internal", "private", "dso_local", "ccc", "noundef", "tail", "call", "hidden", "nonnull"}
    i = 0
    while i < len(toks):
        if toks[i] in ("signext", "zeroext", "inreg"):
            attrs.append(toks[i])
        elif toks[i] not in skip:
            break
        i += 1
    ty, vsig = take_type(" ".join(toks[i:]))
    return " ".join(attrs + flatten(ty, types)), " ".join(vsig.split())


def parse_module(text):
    types = {}
    funcs = {}
    decls = {}
    cur = None
    for line in text.splitlines():
        m = re.match(r'^(%[^\s=]+) = type (.*)$', line)
        if m:
            types[m.group(1)] = m.group(2)
            continue
        m = re.match(r'^(declare|define) (.*?)@"?([\w.$]+)"?\((.*)\)[^)]*$', line)
        if m:
            sig = (m.group(2), m.group(4))
            if m.group(1) == "declare":
                decls[m.group(3)] = sig
            else:
                cur = m.group(3)
                funcs[cur] = (sig, [])
            continue
        if line.startswith("}"):
            cur = None
            continue
        if cur is not None and " call " in " " + line:
            funcs[cur][1].append(line)
    return types, funcs, decls


def parse_call(line):
    m = re.search(r"\bcall (.*?)([@%][\w.$\"]+)\((.*)\)", line)
    if m is None:
        return None
    return m.group(1), m.group(2), m.group(3)


def sig_view(sig, types):
    ret, vsig = norm_ret(sig[0], types)
    return f"{ret} ({', '.join(norm_params(sig[1]))}){(' ' + vsig) if vsig else ''}"


def call_view(call, types):
    ret, vsig = norm_ret(call[0], types)
    return f"{ret} ({', '.join(norm_params(call[2]))}){(' ' + vsig) if vsig else ''}"


def find_fn(funcs, name):
    for k in (f"vb.{name}$c", f"{name}$c", f"vb.{name}", name):
        if k in funcs:
            return funcs[k]
    return None


def oracle_items(mod, case_name, variadic):
    types, funcs, decls = mod
    items = {}
    if f"f_{case_name}" in decls:
        items["declare"] = sig_view(decls[f"f_{case_name}"], types)
    use = find_fn(funcs, f"use_{case_name}")
    if use is not None:
        for line in use[1]:
            c = parse_call(line)
            if c is None:
                continue
            if c[1] == f"@f_{case_name}":
                items["call"] = call_view(c, types)
            elif c[1].startswith("%"):
                items["indirect"] = call_view(c, types)
    if not variadic:
        g = find_fn(funcs, f"g_{case_name}")
        if g is not None:
            items["export"] = sig_view(g[0], types)
        h = find_fn(funcs, f"h_{case_name}")
        if h is not None:
            items["fnptr"] = sig_view(h[0], types)
    return items


def oracle_lit_c(t, v):
    if t in SCALARS:
        return f"({ctype(t)}){clit(t, v)}"
    return clit(t, v)


def render_oracle(cases):
    zk = z_structs() + [""]
    c = ["#include <stdint.h>", "#include <stdbool.h>"] + c_structs() + [""]
    calls = []
    for case in cases:
        n = case["oname"]
        params = case["params"]
        ret = case["ret"]
        rt = ctype(ret)
        zrt = zktype(ret)
        if case["mode"] == "variadic":
            if case["vsum"]:
                zk.append(f"extern i64 f_{n}(i32 n, ...);")
                c.append(f"int64_t f_{n}(int32_t n, ...);")
                zhead = [str(len(case["var"]))]
                chead = [str(len(case["var"]))]
            else:
                zsig = sig_zk(params)
                csig = sig_c(params)
                zk.append(f"extern {zrt} f_{n}({zsig + ', ' if zsig else ''}u8* fmt, ...);")
                c.append(f"{rt} f_{n}({csig + ', ' if csig else ''}const char *fmt, ...);")
                fmt = "".join(va_code(t) for t in case["var"])
                zhead = [zlit(t, v) for (t, _), v in zip(params, case["values"])] + [f'"{fmt}"']
                chead = [clit(t, v) for (t, _), v in zip(params, case["values"])] + [f'"{fmt}"']
            zvar = [va_lit(t, v) for t, v in zip(case["var"], case["var_values"])]
            cvar = [oracle_lit_c(t, v) for t, v in zip(case["var"], case["var_values"])]
            zk.append(f"void use_{n}() {{ const auto r = f_{n}({', '.join(zhead + zvar)}); }}")
            c.append(f"void use_{n}(void) {{ f_{n}({', '.join(chead + cvar)}); }}")
        else:
            zsig = sig_zk(params)
            csig = sig_c(params) or "void"
            fnty = fn_ty(params, ret)
            za = args_zk(params, case["values"])
            ca = ", ".join(oracle_lit_c(t, v) for (t, _), v in zip(params, case["values"]))
            zk.append(f"extern {zrt} f_{n}({zsig});")
            zk.append(f"export {zrt} g_{n}({zsig}) {{ {zrt} r; return r; }}")
            zk.append(f"{zrt} h_{n}({zsig}) {{ {zrt} r; return r; }}")
            zk.append(f"void use_{n}() {{ const auto r = f_{n}({za}); {fnty} fp = f_{n}; const auto q = fp({za}); {fnty} hp = h_{n}; }}")
            c.append(f"{rt} f_{n}({csig});")
            c.append(f"{rt} g_{n}({csig}) {{ {rt} r; __builtin_memset(&r, 0, sizeof r); return r; }}")
            c.append(f"void use_{n}(void) {{ f_{n}({ca}); {rt} (*fp)({csig}) = f_{n}; fp({ca}); }}")
        calls.append(f"use_{n}();")
    zk.append("void main() { " + " ".join(calls) + " }")
    return "\n".join(zk) + "\n", "\n".join(c) + "\n"


def oracle_cases(extra):
    out = []
    seen = set()
    for case in fixed_cases() + vec_cases(SHORT_VECS) + extra:
        key = (case["mode"] == "variadic", tuple(t for t, _ in case["params"]), case["ret"],
               tuple(case.get("var", [])), case.get("vsum"))
        if key in seen:
            continue
        seen.add(key)
        case = dict(case)
        case["oname"] = f"o{len(out)}"
        out.append(case)
    return out


def run_oracle(targets, extra):
    cases = oracle_cases(extra)
    zk_text, c_text = render_oracle(cases)
    d = os.path.join(OUT, "ir_oracle")
    os.makedirs(d, exist_ok=True)
    zk = os.path.join(d, "main.zk")
    c = os.path.join(d, "side.c")
    write_file(zk, zk_text)
    write_file(c, c_text)
    bad = 0
    for target in targets:
        triple, flags = ORACLE_TARGETS[target]
        z = subprocess.run([ZARK, "ir", zk] + flags, capture_output=True, text=True)
        if z.returncode != 0:
            print(f"{target}: zark ir failed: {(z.stdout + z.stderr).strip()[:400]}")
            bad += 1
            continue
        k = subprocess.run(["clang", f"--target={triple}", "-ffreestanding", "-S", "-emit-llvm", "-O0", "-o", "-", c],
                           capture_output=True, text=True)
        if k.returncode != 0:
            print(f"{target}: clang failed: {k.stderr.strip()[:400]}")
            bad += 1
            continue
        zm = parse_module(z.stdout)
        cm = parse_module(k.stdout)
        n = 0
        mism = 0
        for case in cases:
            variadic = case["mode"] == "variadic"
            zi = oracle_items(zm, case["oname"], variadic)
            ci = oracle_items(cm, case["oname"], variadic)
            ci_names = ["declare", "call"] if variadic else ["declare", "call", "indirect", "export", "fnptr"]
            for item in ci_names:
                want = ci.get(item if item != "fnptr" else "export")
                got = zi.get(item)
                n += 1
                if got is None or got != want:
                    mism += 1
                    print(f"MISMATCH {target} {case['name']} {item}\n    zark:  {got}\n    clang: {want}")
        print(f"{target}: {len(cases)} signatures, {n} items, {mism} mismatches")
        bad += mism
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=int, default=0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--backends", default="native,llvm,O")
    ap.add_argument("--only", default="")
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--ir-oracle", default="")
    args = ap.parse_args()

    if args.ir_oracle:
        targets = [t for t in args.ir_oracle.split(",") if t]
        for t in targets:
            if t not in ORACLE_TARGETS:
                print(f"unknown oracle target: {t} (known: {', '.join(ORACLE_TARGETS)})")
                return 2
        return run_oracle(targets, random_cases(args.cases, args.seed) if args.cases > 0 else [])

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
    if "native" in backends and (sys.platform != "linux" or os.uname().machine != "x86_64"):
        print("native backend not available on this host: skipped")
        backends.remove("native")
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
