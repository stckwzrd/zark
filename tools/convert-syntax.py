import re, sys

KW = set("fn let var const if else while for in return break continue struct enum impl extern export defer errdefer error catch true false null as import match sizeof alignof union type is".split())
ENDS_ID = {"return", "break", "continue", "true", "false", "null"}
OPS3 = ["...", "<<=", ">>="]
OPS2 = ["..", "=>", "==", "!=", "<=", ">=", "<<", ">>", "&&", "||", "+=", "-=", "*=", "/=", "%=", "|=", "&=", "^=", "++", "--", "::", "->"]


class Tok:
    def __init__(self, k, t, s, e):
        self.k, self.t, self.s, self.e = k, t, s, e

    def __repr__(self):
        return f"{self.k}:{self.t}"


def lex(src):
    toks = []
    semis = []
    i, n, depth = 0, len(src), 0
    while i < n:
        c = src[i]
        if c == "\n":
            if depth == 0 and toks and ends_stmt(toks[-1]) and (not semis or semis[-1] != len(toks) - 1):
                semis.append(len(toks) - 1)
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if src.startswith("//", i):
            while i < n and src[i] != "\n":
                i += 1
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c.isalpha() or c == "_":
            j = i
            while j < n and (src[j].isalnum() or src[j] == "_"):
                j += 1
            toks.append(Tok("id", src[i:j], i, j))
            i = j
            continue
        if c.isdigit():
            j = i
            if src.startswith(("0x", "0b", "0o"), i):
                j = i + 2
                while j < n and (src[j].isalnum() or src[j] == "_"):
                    j += 1
            else:
                while j < n and (src[j].isdigit() or src[j] == "_"):
                    j += 1
                if j + 1 < n and src[j] == "." and src[j + 1].isdigit():
                    j += 1
                    while j < n and (src[j].isdigit() or src[j] == "_"):
                        j += 1
                if j < n and src[j] in "eE":
                    j += 1
                    if j < n and src[j] in "+-":
                        j += 1
                    while j < n and src[j].isdigit():
                        j += 1
            toks.append(Tok("num", src[i:j], i, j))
            i = j
            continue
        if c == '"':
            j = i + 1
            bd = 0
            while j < n and not (src[j] == '"' and bd == 0):
                ch = src[j]
                if ch == "\\":
                    j += 2
                    continue
                if ch == "{" and j + 1 < n and src[j + 1] == "{" and bd == 0:
                    j += 2
                    continue
                if ch == "{":
                    bd += 1
                if ch == "}" and bd > 0:
                    bd -= 1
                if ch == '"' and bd > 0:
                    j += 1
                    while j < n and src[j] != '"':
                        if src[j] == "\\":
                            j += 1
                        j += 1
                j += 1
            j += 1
            toks.append(Tok("str", src[i:j], i, j))
            i = j
            continue
        if c == "'":
            j = i + 1
            if j < n and src[j] == "\\":
                j += 1
            j += 2
            toks.append(Tok("char", src[i:j], i, j))
            i = j
            continue
        op = None
        for o in OPS3:
            if src.startswith(o, i):
                op = o
        if op is None:
            for o in OPS2:
                if src.startswith(o, i):
                    op = o
                    break
        if op is None:
            op = c
        toks.append(Tok("op", op, i, i + len(op)))
        if op in "([":
            depth += 1
        if op in ")]":
            depth -= 1
        i += len(op)
    return toks, semis


def ends_stmt(t):
    if t.k in ("num", "str", "char"):
        return True
    if t.k == "id":
        return t.t not in KW or t.t in ENDS_ID
    return t.t in (")", "]", "}", "?")


DECLARED = set()


def camel(s):
    if s in DECLARED:
        return True
    return bool(re.match(r"^[A-Z][A-Za-z0-9]*$", s)) and any(ch.islower() for ch in s)


PRIM = set("i8 i16 i32 i64 isize u8 u16 u32 u64 usize f32 f64 bool str void".split())


class Conv:
    def __init__(self, src, fname="?"):
        self.src = src
        self.T, self.semi_after = lex(src)
        for k in range(len(self.T) - 1):
            if self.T[k].t in ("struct", "enum", "union") and self.T[k + 1].k == "id" and re.match(r"^[A-Z][A-Za-z0-9]*$", self.T[k + 1].t):
                DECLARED.add(self.T[k + 1].t)
        self.edits = []
        self.fname = fname
        self.aliases = set()
        self.match_open = set()
        self.agg_open = set()
        self.close_semi = set()
        self.nosemi = set()
        self.pair = {}
        st = []
        for i, t in enumerate(self.T):
            if t.k == "op" and t.t in "([{":
                st.append(i)
            elif t.k == "op" and t.t in ")]}":
                if st:
                    j = st.pop()
                    self.pair[j] = i
                    self.pair[i] = j
        for i, t in enumerate(self.T):
            if t.t == "import" and t.k == "id":
                j = i + 1
                if j + 2 < len(self.T) and self.T[j].k == "str" and self.T[j + 1].t == "as":
                    self.aliases.add(self.T[j + 2].t)

    # ---------------------------------------------------------- edits
    def rep(self, a, b, text):
        self.edits.append((a, b, text, 0))

    def ins(self, pos, text, order=1):
        self.edits.append((pos, pos, text, order))

    def is_tok(self, i, text):
        return 0 <= i < len(self.T) and self.T[i].k != "str" and self.T[i].t == text

    # ---------------------------------------------------------- types
    def ptype(self, i):
        T = self.T
        t = T[i]
        if t.t == "fn" and t.k == "id":
            j = i + 1
            clos = False
            if self.is_tok(j, "["):
                clos = True
                j += 2
            assert self.is_tok(j, "("), "fn type"
            j += 1
            params = []
            while not self.is_tok(j, ")"):
                p, j = self.ptype(j)
                params.append(p)
                if self.is_tok(j, ","):
                    j += 1
            j += 1
            ret = None
            if self.type_start(j):
                ret, j = self.ptype(j)
            return ("fn", clos, params, ret), j
        if t.t == "*":
            e, j = self.ptype(i + 1)
            return ("ptr", e), j
        if t.t == "!":
            e, j = self.ptype(i + 1)
            return ("err", e), j
        if t.t == "?":
            e, j = self.ptype(i + 1)
            return ("opt", e), j
        if t.t == "[":
            if self.is_tok(i + 1, "]"):
                e, j = self.ptype(i + 2)
                return ("slice", e), j
            k = self.pair[i]
            ln = self.src[T[i + 1].s:T[k - 1].e]
            e, j = self.ptype(k + 1)
            return ("arr", ln, e), j
        assert t.k == "id", f"type expected at {t.t}"
        name = t.t
        j = i + 1
        if self.is_tok(j, ".") and T[j + 1].k == "id" and name in self.aliases and (j - 1) not in self.semi_set:
            name = name + "::" + T[j + 1].t
            j += 2
        args = []
        if self.is_tok(j, "["):
            k = self.pair[j]
            j += 1
            while j < k:
                a, j = self.ptype(j)
                args.append(a)
                if self.is_tok(j, ","):
                    j += 1
            j = k + 1
        return ("name", name, args), j

    def type_start(self, j):
        if j >= len(self.T):
            return False
        t = self.T[j]
        if t.t in ("{",) or t.k in ("num", "str", "char"):
            return False
        if self.is_semi_between(j):
            return False
        return (t.k == "id" and t.t not in KW) or t.t in ("*", "!", "?", "[") or (t.k == "id" and t.t == "fn")

    def is_semi_between(self, j):
        return j > 0 and (j - 1) in self.semi_set

    def tstr(self, n, cast=False):
        k = n[0]
        if k == "name":
            s = n[1]
            if n[2]:
                s += "<" + ", ".join(self.tstr(a, cast) for a in n[2]) + ">"
            return s
        if k == "ptr":
            return ("*" + self.tstr(n[1], cast)) if cast else (self.tstr(n[1], cast) + "*")
        if k == "slice":
            return ("[]" + self.tstr(n[1], cast)) if cast else (self.tstr(n[1], cast) + "[]")
        if k == "arr":
            if cast:
                return "[" + n[1] + "]" + self.tstr(n[2], cast)
            dims = [n[1]]
            e = n[2]
            while e[0] == "arr":
                dims.append(e[1])
                e = e[2]
            return self.tstr(e, cast) + "".join("[" + d + "]" for d in dims)
        if k == "err":
            return "!" + self.tstr(n[1], cast)
        if k == "opt":
            return "?" + self.tstr(n[1], cast)
        if k == "fn":
            s = "fn[](" if n[1] else "fn("
            s += ", ".join(self.tstr(p, cast) for p in n[2]) + ")"
            if n[3] is not None:
                s += " -> " + self.tstr(n[3], cast)
            return s
        raise Exception(k)

    # ---------------------------------------------------------- driver
    def convert(self):
        self.semi_set = set(self.semi_after)
        T = self.T
        n = len(T)
        segs = []
        i = 0
        while i < n:
            j = self.decl_end(i)
            segs.append((i, j))
            i = j + 1
        impls = {}
        out_segs = []
        for (a, b) in segs:
            if T[a].t == "impl" and T[a].k == "id":
                nm = T[a + 1].t
                lb = a + 2
                if self.is_tok(lb, "["):
                    lb = self.pair[lb] + 1
                body_tokens = (lb + 1, self.pair[lb])
                impls.setdefault(nm, []).append(body_tokens)
        self.impl_bodies = impls
        declared = set()
        for (a, b) in segs:
            if T[a].t in ("struct", "union", "enum") and T[a].k == "id":
                declared.add(T[a + 1].t)
        self.declared = declared
        for (a, b) in segs:
            self.decl(a, b)
        return self.apply()

    def decl_end(self, i):
        T = self.T
        j = i
        depth = 0
        while j < len(T):
            t = T[j]
            if t.k == "op" and t.t == "{":
                j = self.pair[j]
                if T[i].t in ("struct", "enum", "union", "impl", "fn", "extern", "export", "test") or True:
                    return j
            if t.k == "op" and t.t == "(":
                j = self.pair[j]
            j += 1
            if j - 1 in self.semi_set and depth == 0:
                return j - 1
        return len(T) - 1

    def decl(self, a, b):
        T = self.T
        t = T[a]
        kw = t.t if t.k == "id" else ""
        if kw == "impl":
            self.remove_impl(a, b)
            return
        if kw in ("fn", "extern", "export"):
            self.func(a, b, None)
            return
        if kw in ("struct", "union"):
            self.struct(a, b)
            return
        if kw == "enum":
            self.agg_open.add(a + 2)
            for k in range(a, b + 1):
                if k in self.semi_set:
                    self.nosemi.add(k)
            for (x, y) in self.impl_bodies.get(T[a + 1].t, []):
                self.add_methods(T[a + 1].t, x, y, b)
            return
        if kw in ("const", "var"):
            self.glob(a, b)
            return
        if kw == "type":
            ty, j = self.ptype(a + 3)
            self.rep(T[a + 3].s, T[j - 1].e, self.tstr(ty))
            return
        if kw == "test":
            self.scan(a + 2, b)
            return

    def remove_impl(self, a, b):
        T = self.T
        nm = T[a + 1].t
        if nm not in self.declared:
            self.impl_outside(a, b)
            return
        self.rep(T[a].s, T[b].e, "")
        for k in range(a, b + 1):
            self.nosemi.add(k)

    def impl_outside(self, a, b):
        T = self.T
        nm = T[a + 1].t
        lb = a + 2
        recv = ""
        if self.is_tok(lb, "["):
            recv = re.sub(r"\s+", " ", self.src[T[lb + 1].s:T[self.pair[lb] - 1].e])
            lb = self.pair[lb] + 1
        rb = self.pair[lb]
        self.rep(T[a].s, T[lb].e, "")
        self.rep(T[rb].s, T[rb].e, "")
        self.nosemi.add(rb)
        i = lb + 1
        while i < rb:
            j = self.fn_end(i, rb)
            self.func(i, j, nm, outside=True, recv=recv)
            i = j + 1

    # ---------------------------------------------------------- globals
    def glob(self, a, b):
        T = self.T
        kw = T[a].t
        name = T[a + 1].t
        j = a + 2
        ty = None
        if self.is_tok(j, ":"):
            ty, j = self.ptype(j + 1)
        tys = self.tstr(ty) if ty else "auto"
        if kw == "const":
            head = "const " + tys + " " + name
        else:
            head = tys + " " + name
        self.rep(T[a].s, T[j - 1].e, head)
        self.scan(j, b + 1)

    # ---------------------------------------------------------- functions
    def func(self, a, b, owner, outside=False, recv=""):
        T = self.T
        i = a
        pre = ""
        while T[i].t in ("extern", "export"):
            pre += T[i].t + " "
            i += 1
        assert T[i].t == "fn", f"fn expected in {self.fname} at {T[i]}"
        name = T[i + 1].t
        j = i + 2
        tpl = ""
        if self.is_tok(j, "["):
            k = self.pair[j]
            inner = self.src[T[j + 1].s:T[k - 1].e]
            inner = re.sub(r"\s+", " ", inner)
            tpl = "template<" + inner + "> "
            j = k + 1
        assert self.is_tok(j, "("), "params"
        pe = self.pair[j]
        params, is_method, variadic = self.params(j + 1, pe)
        j = pe + 1
        ret = None
        if self.type_start(j) and not self.is_tok(j, "{"):
            ret, j = self.ptype(j)
        has_body = self.is_tok(j, "{")
        rets = self.tstr(ret) if ret else "void"
        plist = [f"{self.tstr(t)} {n}" for (n, t) in params]
        if variadic:
            plist.append("...")
        qual = (owner + "::" + name) if outside else name
        if outside and recv:
            assert not tpl, "generic method in generic out-of-class impl"
            qual = owner + "<" + recv + ">::" + name
            tpl = "template<" + recv + "> "
        head = pre + tpl + rets + " " + qual + "(" + ", ".join(plist) + ")"
        if owner is not None and not is_method:
            head = "static " + head
        self.rep(T[a].s, T[j - 1].e, head)
        if has_body:
            self.scan(j, self.pair[j] + 1)
        return head

    def params(self, i, end):
        T = self.T
        out = []
        method = False
        variadic = False
        while i < end:
            if self.is_tok(i, "..."):
                variadic = True
                i += 1
            elif T[i].t == "self" and not self.is_tok(i + 1, ":"):
                method = True
                i += 1
            elif T[i].t == "self":
                method = True
                _, i = self.ptype(i + 2)
            else:
                nm = T[i].t
                assert self.is_tok(i + 1, ":"), f"param colon at {T[i]} {self.fname}"
                ty, i = self.ptype(i + 2)
                out.append((nm, ty))
            if i < end and self.is_tok(i, ","):
                i += 1
        return out, method, variadic

    # ---------------------------------------------------------- structs
    def struct(self, a, b):
        T = self.T
        is_union = T[a].t == "union"
        nm = T[a + 1].t
        j = a + 2
        if self.is_tok(j, "["):
            k = self.pair[j]
            inner = re.sub(r"\s+", " ", self.src[T[j + 1].s:T[k - 1].e])
            self.rep(T[j].s, T[k].e, "<" + inner + ">")
            j = k + 1
        lb = j
        rb = self.pair[lb]
        self.agg_open.add(lb)
        i = lb + 1
        while i < rb:
            if T[i].k == "id" and self.is_tok(i + 1, ":"):
                ty, k = self.ptype(i + 2)
                self.rep(T[i].s, T[k - 1].e, self.tstr(ty) + " " + T[i].t)
                if self.is_tok(k, ","):
                    self.rep(T[k].s, T[k].e, ";")
                elif (k - 1) not in self.semi_set:
                    self.ins(T[k - 1].e, ";")
                i = k + (1 if self.is_tok(k, ",") else 0)
                continue
            if T[i].k == "id" and is_union:
                if self.is_tok(i + 1, ",") or i + 1 == rb or (i in self.semi_set):
                    if self.is_tok(i + 1, ","):
                        self.rep(T[i + 1].s, T[i + 1].e, ";")
                    elif i not in self.semi_set:
                        self.ins(T[i].e, ";")
                    i += 2 if self.is_tok(i + 1, ",") else 1
                    continue
            i += 1
        for (x, y) in self.impl_bodies.get(nm, []):
            self.add_methods(nm, x, y, rb)

    def add_methods(self, owner, x, y, rb):
        T = self.T
        if x >= y:
            return
        sub = Conv(self.src, self.fname)
        sub.aliases = self.aliases
        sub.semi_set = set(self.semi_after)
        sub.impl_bodies = {}
        sub.owner = owner
        i = x
        while i < y:
            j = sub.fn_end(i, y)
            sub.func(i, j, owner)
            i = j + 1
        sub.close_all(x, y)
        text = sub.apply(T[x].s, T[y - 1].e)
        self.ins(T[rb].s, "\n" + text.strip("\n") + "\n", 2)
        for k in range(x - 1, y + 1):
            self.nosemi.add(k)

    def fn_end(self, i, y):
        T = self.T
        j = i
        while j < y:
            if self.is_tok(j, "{"):
                return self.pair[j]
            if self.is_tok(j, "(") or self.is_tok(j, "["):
                j = self.pair[j]
            j += 1
        return y - 1

    def close_all(self, x, y):
        pass

    # ---------------------------------------------------------- statements / expressions
    def scan(self, i, end):
        T = self.T
        # mark brace kinds
        while i < end:
            t = T[i]
            if t.k == "id" and t.t in ("let", "var"):
                i = self.let(i)
                continue
            if t.k == "id" and t.t in ("if", "while"):
                self.cond_parens(i)
                i += 1
                continue
            if t.k == "id" and t.t == "for":
                i = self.for_(i)
                continue
            if t.k == "id" and t.t == "match":
                k = self.find_open(i + 1)
                self.match_open.add(k)
                i += 1
                continue
            if t.k == "id" and t.t == "fn" and self.is_tok(i + 1, "["):
                i = self.closure(i)
                continue
            if t.k == "id" and t.t == "as":
                ty, j = self.ptype(i + 1)
                self.rep(T[i + 1].s, T[j - 1].e, self.tstr(ty, cast=True))
                i = j
                continue
            if t.k == "id" and t.t in ("sizeof", "alignof") and self.is_tok(i + 1, "("):
                ty, j = self.ptype(i + 2)
                self.rep(T[i + 2].s, T[j - 1].e, self.tstr(ty))
                i = j
                continue
            if t.k == "str" and "self" in t.t:
                self.rep(t.s, t.e, self.fix_str(t.t))
            if t.k == "id" and t.t == "self":
                self.rep(t.s, t.e, "this")
                if self.is_tok(i + 1, "."):
                    self.rep(T[i + 1].s, T[i + 1].e, "->")
                    i += 2
                    continue
            if t.k == "id" and (camel(t.t) or t.t in self.aliases or t.t in PRIM):
                i = self.type_use(i, end)
                continue
            if t.k == "id" and t.t not in KW and self.is_tok(i + 1, "[") and self.generic_ok(i + 1, False):
                i = self.generic_args(i, i + 1, end)
                continue
            if t.k == "op" and t.t == "{" and i not in self.match_open:
                if self.is_literal_open(i):
                    self.literal(i)
            i += 1

    def fix_str(self, s):
        out = []
        i = 0
        bd = 0
        while i < len(s):
            c = s[i]
            if c == "\\":
                out.append(s[i:i + 2])
                i += 2
                continue
            if c == "{" and bd == 0 and s[i:i + 2] == "{{":
                out.append("{{")
                i += 2
                continue
            if c == "{":
                bd += 1
                j = i + 1
                depth = 1
                while j < len(s) and depth:
                    if s[j] == "{":
                        depth += 1
                    elif s[j] == "}":
                        depth -= 1
                    j += 1
                hole = s[i:j]
                hole = re.sub(r"\bself\.", "this->", hole)
                hole = re.sub(r"\bself\b", "this", hole)
                out.append(hole)
                bd = 0
                i = j
                continue
            out.append(c)
            i += 1
        return "".join(out)

    def find_open(self, i):
        T = self.T
        while i < len(T):
            if self.is_tok(i, "{"):
                return i
            if self.is_tok(i, "(") or self.is_tok(i, "["):
                i = self.pair[i]
            i += 1
        return len(T) - 1

    def ret_type_end(self, j):
        T = self.T
        while j >= 0 and (T[j].k == "id" or T[j].t in ("!", "?", "*", "[", "]", ".") or T[j].k == "num"):
            if T[j].t == "fn":
                return False
            j -= 1
        if j < 0 or T[j].t != ")" or j not in self.pair:
            return False
        o = self.pair[j]
        k = o - 1
        if k >= 0 and T[k].t == "]" and k in self.pair:
            k = self.pair[k] - 1
        return k >= 1 and T[k].k == "id" and T[k - 1].t == "fn"

    def is_literal_open(self, i):
        T = self.T
        if i == 0:
            return False
        p = T[i - 1]
        if self.ret_type_end(i - 1):
            return False
        if p.k == "id" and camel(p.t) and not (i >= 2 and T[i - 2].t in ("struct", "union", "enum", "impl")):
            return True
        if p.k == "op" and p.t == ">":
            return True
        if p.k == "id" and p.t in self.aliases:
            return False
        if i >= 3 and p.k == "id" and T[i - 2].t == "." and T[i - 3].k == "id" and (T[i - 3].t in self.aliases):
            return camel(p.t)
        return False

    def type_use(self, i, end):
        T = self.T
        t = T[i]
        j = i + 1
        # alias.member / Type.member -> ::
        if t.t in self.aliases and self.is_tok(j, ".") and T[j + 1].k == "id":
            self.rep(T[j].s, T[j].e, "::")
            if camel(T[j + 1].t) and self.is_tok(j + 2, "["):
                return self.generic_args(j + 1, j + 2, end)
            return j + 1
        if camel(t.t):
            if self.is_tok(j, "[") and self.generic_ok(j):
                return self.generic_args(i, j, end)
            if self.is_tok(j, ".") and j + 1 < len(T) and T[j + 1].k == "id" and not (i > 0 and T[i - 1].t == "."):
                self.rep(T[j].s, T[j].e, "::")
                return j + 1
        return i + 1

    def typey(self, j):
        T = self.T
        k = self.pair[j]
        if k == j + 1:
            return False
        for x in range(j + 1, k):
            tk = T[x]
            if tk.k == "num" or tk.k == "str":
                return False
            if tk.k == "id" and not (tk.t in PRIM or camel(tk.t) or tk.t in self.aliases or tk.t == "fn"):
                return False
            if tk.k == "op" and tk.t not in ("*", "[", "]", ",", ".", "!", "?", "(", ")"):
                return False
        return True

    def generic_ok(self, j, base_camel=True):
        T = self.T
        if not self.typey(j):
            return False
        k = self.pair[j]
        nxt = T[k + 1] if k + 1 < len(T) else None
        if nxt is None:
            return False
        if base_camel:
            return nxt.t in (".", "{", "(")
        return nxt.t == "("

    def generic_args(self, i, j, end):
        T = self.T
        k = self.pair[j]
        args = []
        x = j + 1
        while x < k:
            ty, x = self.ptype(x)
            args.append(self.tstr(ty))
            if self.is_tok(x, ","):
                x += 1
        self.rep(T[j].s, T[k].e, "<" + ", ".join(args) + ">")
        if self.is_tok(k + 1, ".") and T[k + 2].k == "id":
            self.rep(T[k + 1].s, T[k + 1].e, "::")
        if self.is_tok(k + 1, "{"):
            self.literal(k + 1)
            return k + 2
        return k + 1

    def literal(self, lb):
        T = self.T
        rb = self.pair[lb]
        self.close_semi.add(rb)
        i = lb + 1
        inner = list(range(lb + 1, rb))
        if len(inner) == 1 and self.is_tok(inner[0], ".."):
            self.rep(T[lb].e, T[rb].s, "")
            return
        depth_stack = 0
        x = lb + 1
        last_field_end = None
        while x < rb:
            t = T[x]
            if t.k == "op" and t.t in "([{":
                x = self.pair[x] + 1
                continue
            if t.k == "id" and self.is_tok(x + 1, ":") and (self.is_tok(x - 1, ",") or x - 1 == lb):
                self.rep(t.s, T[x + 1].e, "." + t.t + " =")
                x += 2
                continue
            if self.is_tok(x, "..") and (x + 1 == rb):
                a = T[x - 1].e if x - 1 > lb else T[lb].e
                if self.is_tok(x - 1, ","):
                    a = T[x - 2].e
                self.rep(a, T[x].e, "")
                break
            x += 1

    def let(self, i):
        T = self.T
        kw = T[i].t
        name = T[i + 1].t
        j = i + 2
        ty = None
        if self.is_tok(j, ":"):
            ty, j = self.ptype(j + 1)
        tys = self.tstr(ty) if ty else "auto"
        head = ("const " if kw == "let" else "") + tys + " " + name
        self.rep(T[i].s, T[j - 1].e, head)
        return j

    def cond_parens(self, i):
        T = self.T
        k = self.find_open(i + 1)
        if k > i + 1 and T[i + 1].t == "(" and self.pair.get(i + 1) == k - 1:
            return
        self.ins(T[i + 1].s, "(")
        self.ins(T[k - 1].e, ")", 3)

    def for_(self, i):
        T = self.T
        k = self.find_open(i + 1)
        j = i + 1
        names = [T[j].t]
        j += 1
        if self.is_tok(j, ","):
            names.append(T[j + 1].t)
            j += 2
        assert self.is_tok(j, "in"), f"for-in expected {self.fname} {T[j]}"
        if len(names) == 1:
            head = f"for (auto {names[0]} :"
        else:
            head = f"for (auto [{names[0]}, {names[1]}] :"
        self.rep(T[i].s, T[j].e, head)
        self.ins(T[k - 1].e, ")", 3)
        return j + 1

    def closure(self, i):
        T = self.T
        k = i + 1
        ke = self.pair[k]
        caps = [T[x].t for x in range(k + 1, ke) if T[x].k == "id"]
        j = ke + 1
        pe = self.pair[j]
        params, _, _ = self.params(j + 1, pe)
        j = pe + 1
        ret = None
        if self.type_start(j):
            ret, j = self.ptype(j)
        plist = ", ".join(f"{self.tstr(t)} {n}" for (n, t) in params)
        head = "[" + ", ".join("&" + c for c in caps) + "](" + plist + ")"
        if ret is not None:
            head += " -> " + self.tstr(ret)
        self.rep(T[i].s, T[j - 1].e, head)
        body = j
        self.close_semi.add(self.pair[body])
        self.scan(body + 1, self.pair[body])
        return self.pair[body] + 1

    # ---------------------------------------------------------- output
    def apply(self, lo=None, hi=None):
        T = self.T
        edits = list(dict.fromkeys(self.edits))
        for k in self.semi_after:
            if k in self.nosemi:
                continue
            t = T[k]
            if t.t == "}" and k not in self.close_semi:
                continue
            edits.append((t.e, t.e, ";", 5))
        # semicolon before a closing brace of a one-line block
        for i, t in enumerate(T):
            if t.k == "op" and t.t == "}" and i - 1 >= 0 and i not in self.close_semi and i in self.pair:
                o = self.pair[i]
                if o in self.match_open or o in self.agg_open or self.is_literal_open(o):
                    continue
                p = T[i - 1]
                if p.t in (";", "{", "}", ",") and p.k == "op":
                    continue
                if (i - 1) in self.semi_set or (i - 1) in self.nosemi:
                    continue
                if o + 1 == i:
                    continue
                if self.src[p.e:T[i].s].count("\n") == 0 and self.is_block_open(o):
                    edits.append((p.e, p.e, ";", 5))
        edits.sort(key=lambda e: (e[0], e[1] != e[0], e[3]))
        out = []
        pos = lo if lo is not None else 0
        end = hi if hi is not None else len(self.src)
        for (a, b, text, o) in edits:
            if a < pos:
                if a == b and a >= pos - 0:
                    pass
                continue
            if lo is not None and (a < lo or b > hi):
                continue
            out.append(self.src[pos:a])
            out.append(text)
            pos = max(pos, b)
        out.append(self.src[pos:end])
        return "".join(out)

    def is_block_open(self, o):
        T = self.T
        if o in self.match_open or o in self.agg_open:
            return False
        p = T[o - 1]
        if p.k == "id" and p.t in ("enum", "struct", "union"):
            return False
        if self.is_literal_open(o):
            return False
        return True


def convert_source(src, fname="?"):
    DECLARED.clear()
    c = Conv(src, fname)
    return c.convert()


if __name__ == "__main__":
    for f in sys.argv[1:]:
        s = open(f).read()
        open(f, "w").write(convert_source(s, f))
