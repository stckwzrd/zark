#!/usr/bin/env python3
"""Ownership-check fuzzer: correct idioms must compile and run, known wrong
programs must be rejected with the ownership diagnostic.

Each iteration generates a pair from the same pattern: the good program must
print "ok", the bad one must fail to compile with the expected message.  A
false error on the good program is too strict; an accepted bad program is a
soundness hole.

usage: tools/fuzz_own.py [--count N] [--seed N] [--quick] [--keep] [--zark PATH]
"""

import argparse
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fuzz_crash  # noqa: E402

TAKE = "void take(move List<i64> l) { l.deinit(); }\n"
OWN = """owned struct H {
    i64* p;
    Allocator a;
    static !H open(Allocator a) {
        const auto p = a.alloc<i64>(1)?;
        return H{ .p = p.ptr, .a = a };
    }
    void close() move { this->a.free(this->p[0..1]); }
}
"""
HOLDER = "struct Holder { List<i64> l; }\n"


def fill(tpl, r):
    return (tpl.replace("@A@", str(r.randint(1, 9)))
               .replace("@B@", str(r.randint(1, 9)))
               .replace("@C@", str(r.randint(1, 9))))


def p_basic(r):
    good = """!void main() {
    auto l = List<i64>::init(c_allocator());
    defer l.deinit();
    l.push(@A@)?;
    l.push(@B@)?;
    auto s = 0;
    for (auto x : l) { s += x; }
    println(s, "ok");
}
"""
    bad = """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    auto m = l;
    l.push(@B@)?;
    m.deinit();
}
"""
    return fill(good, r), fill(bad, r), "used after"


def p_take(r):
    good = TAKE + """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    take(l);
    l = List<i64>::init(c_allocator());
    l.push(@B@)?;
    l.deinit();
    println("ok");
}
"""
    bad = TAKE + """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    take(l);
    l.push(@B@)?;
}
"""
    return fill(good, r), fill(bad, r), "used after"


def p_clone(r):
    good = """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    auto c = l.clone()?;
    l.deinit();
    c.push(@B@)?;
    c.deinit();
    println("ok");
}
"""
    bad = """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    auto c = l;
    l.deinit();
    c.deinit();
}
"""
    return fill(good, r), fill(bad, r), "used after"


def p_owned(r):
    good = OWN + """!void main() {
    auto x = H::open(c_allocator())?;
    defer x.close();
    println("ok");
}
"""
    bad = OWN + """!void main() {
    auto x = H::open(c_allocator())?;
    println("ok");
}
"""
    return fill(good, r), fill(bad, r), "not consumed"


def p_closure(r):
    good = """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    const auto f = [l]() -> i64 { return l.len; };
    l.push(@B@)?;
    println(f());
    l.deinit();
    println("ok");
}
"""
    bad = """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    const auto f = [l]() -> i64 { return l.len; };
    l.deinit();
    println(f());
}
"""
    return fill(good, r), fill(bad, r), "captured"


def p_swap(r):
    good = """!void main() {
    auto a = List<i64>::init(c_allocator());
    auto b = List<i64>::init(c_allocator());
    a.push(@A@)?;
    b.push(@B@)?;
    auto t = a;
    a = b;
    b = t;
    a.push(@C@)?;
    b.push(@A@)?;
    a.deinit();
    b.deinit();
    println("ok");
}
"""
    bad = """!void main() {
    auto a = List<i64>::init(c_allocator());
    auto b = List<i64>::init(c_allocator());
    a.push(@A@)?;
    b.push(@B@)?;
    auto t = a;
    a = b;
    b = t;
    a.deinit();
    b.deinit();
    println(a.len);
}
"""
    return fill(good, r), fill(bad, r), "used after"


def p_branch(r):
    good = TAKE + """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    if (@B@ > 0) {
        take(l);
        l = List<i64>::init(c_allocator());
        l.push(@C@)?;
    } else {
        l.push(@C@)?;
    }
    l.deinit();
    println("ok");
}
"""
    bad = TAKE + """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    if (@B@ > 0) {
        take(l);
    } else {
        l.push(@C@)?;
    }
    l.deinit();
}
"""
    return fill(good, r), fill(bad, r), "used after"


def p_loop(r):
    good = TAKE + """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    for (auto i : 0..3) {
        take(l);
        l = List<i64>::init(c_allocator());
        l.push(i)?;
        if (i == 1) { break; }
    }
    l.deinit();
    println("ok");
}
"""
    bad = TAKE + """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    for (auto i : 0..3) {
        take(l);
        l.push(i)?;
    }
    l.deinit();
}
"""
    return fill(good, r), fill(bad, r), "used after"


def p_borrow(r):
    good = """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    const auto p = &l.items[0];
    println(*p);
    l.push(@B@)?;
    l.deinit();
    println("ok");
}
"""
    bad = """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    const auto p = &l.items[0];
    l.push(@B@)?;
    println(*p);
}
"""
    return fill(good, r), fill(bad, r), "points into"


def p_return_local(r):
    good = """i64* keep(i64* p) { return p; }

!void main() {
    i64 g = @A@;
    const auto q = keep(&g);
    println(*q, "ok");
}
"""
    bad = """i64* bad() {
    auto x = @A@;
    return &x;
}

!void main() {
    const auto q = bad();
    println(*q);
}
"""
    return fill(good, r), fill(bad, r), "points into local"


def p_struct_lit(r):
    good = HOLDER + """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    auto h = Holder{ .l = l };
    h.l.push(@B@)?;
    h.l.deinit();
    println("ok");
}
"""
    bad = HOLDER + """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    auto h = Holder{ .l = l };
    l.push(@B@)?;
    h.l.deinit();
}
"""
    return fill(good, r), fill(bad, r), "used after"


def p_overwrite(r):
    good = OWN + """!void main() {
    auto x = H::open(c_allocator())?;
    x.close();
    x = H::open(c_allocator())?;
    x.close();
    println("ok");
}
"""
    bad = OWN + """!void main() {
    auto x = H::open(c_allocator())?;
    x = H::open(c_allocator())?;
    x.close();
}
"""
    return fill(good, r), fill(bad, r), "not consumed"


def p_deref(r):
    good = """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    auto c = l.clone()?;
    l.deinit();
    c.deinit();
    println("ok");
}
"""
    bad = """!void main() {
    auto l = List<i64>::init(c_allocator());
    l.push(@A@)?;
    const auto p = &l;
    const auto y = *p;
    l.deinit();
    y.deinit();
}
"""
    return fill(good, r), fill(bad, r), "copying it out of a pointer"


PATTERNS = [p_basic, p_take, p_clone, p_owned, p_closure, p_swap, p_branch,
            p_loop, p_borrow, p_return_local, p_struct_lit, p_overwrite, p_deref]


def run(zark, code, mode, workdir, timeout):
    path = os.path.join(workdir, "main.zk")
    with open(path, "w") as f:
        f.write(code)
    try:
        p = subprocess.run([zark, mode, "main.zk"], cwd=workdir,
                           capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "timeout", -1, ""
    return None, p.returncode, p.stdout + p.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--zark", default=os.environ.get("ZARK", os.path.join(ROOT, "build", "zark")))
    ap.add_argument("--timeout", type=int, default=60)
    args = ap.parse_args()

    zark = os.path.abspath(args.zark)
    if not os.path.exists(zark):
        print(f"fuzz_own: no compiler at {zark}", file=sys.stderr)
        return 2
    zark = fuzz_crash.stable_copy(zark)
    count = args.count if args.count is not None else (20 if args.quick else 100)
    scratch = os.path.join(ROOT, "scratch", "fuzz_own")
    findings = 0
    for i in range(count):
        seed = args.seed + i
        r = random.Random(seed)
        fn = PATTERNS[seed % len(PATTERNS)]
        good, bad, expect = fn(r)
        d = tempfile.mkdtemp(prefix="zarkown-")
        try:
            why, rc, out = run(zark, good, "run", d, args.timeout)
            if why or rc != 0 or "ok" not in out:
                findings += 1
                tag = f"{seed}_good"
                print(f"seed {seed}: FALSE ERROR in a valid program ({why or 'exit ' + str(rc)})")
                for line in out.splitlines()[:8]:
                    print(f"    {line}")
                os.makedirs(scratch, exist_ok=True)
                open(os.path.join(scratch, tag + ".zk"), "w").write(good)
                open(os.path.join(scratch, tag + ".txt"), "w").write(out)
                if not args.keep:
                    break
                continue
            why, rc, out = run(zark, bad, "ir", d, args.timeout)
            if why == "timeout":
                findings += 1
                print(f"seed {seed}: TIMEOUT on a wrong program")
            elif rc == 0:
                findings += 1
                print(f"seed {seed}: SOUNDNESS HOLE - a wrong program compiled")
                os.makedirs(scratch, exist_ok=True)
                open(os.path.join(scratch, f"{seed}_hole.zk"), "w").write(bad)
            elif fuzz_crash.BAD_RE.search(out):
                findings += 1
                print(f"seed {seed}: COMPILER PANIC on a wrong program")
                for line in out.splitlines()[:8]:
                    print(f"    {line}")
            elif expect not in out:
                findings += 1
                print(f"seed {seed}: WRONG DIAGNOSTIC (expected '{expect}')")
                for line in out.splitlines()[:6]:
                    print(f"    {line}")
                os.makedirs(scratch, exist_ok=True)
                open(os.path.join(scratch, f"{seed}_bad.zk"), "w").write(bad)
                open(os.path.join(scratch, f"{seed}_bad.txt"), "w").write(out)
            if findings and not args.keep:
                break
        finally:
            import shutil
            shutil.rmtree(d, ignore_errors=True)
    if findings:
        print(f"fuzz_own: {findings} finding(s) in {count} pairs")
        return 1
    print(f"fuzz_own: {count} pairs ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
