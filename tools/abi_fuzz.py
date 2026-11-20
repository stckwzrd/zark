# Generator for tools/abi_fuzz.sh: writes p.vibe, lib.c and ref.c for one seed.
import random, sys
seed=int(sys.argv[1]); random.seed(seed)
TY=[("i8","signed char"),("u8","unsigned char"),("i16","short"),("u16","unsigned short"),("i32","int"),("u32","unsigned"),("i64","long"),("f32","float"),("f64","double")]
nstruct=random.randint(1,5)
structs=[]
vs=[];cs=[]
for s in range(nstruct):
    n=random.randint(1,6)
    fields=[random.choice(TY) for _ in range(n)]
    # sometimes nest a previous struct
    nest = structs and random.random()<0.3
    structs.append((fields, (random.randrange(len(structs)) if nest else None)))
def sname(i): return f"S{i}"
def fexpr_c(i, var):
    fields,nest=structs[i]
    parts=[f"(double){var}.f{k}" for k in range(len(fields))]
    if nest is not None: parts.append(fexpr_c(nest, f"{var}.n"))
    return "("+" + ".join(parts)+")"
for i,(fields,nest) in enumerate(structs):
    vs.append("struct %s { %s%s }" % (sname(i), " ".join(f"{v} f{k};" for k,(v,c) in enumerate(fields)), f" {sname(nest)} n;" if nest is not None else ""))
    cs.append("typedef struct { %s%s } %s;" % (" ".join(f"{c} f{k};" for k,(v,c) in enumerate(fields)), f" {sname(nest)} n;" if nest is not None else "", sname(i)))
# functions: each takes a random list of args (structs and scalars) and returns a double checksum; plus maker returning struct
funcs=[]
for fidx in range(random.randint(2,5)):
    args=[]
    for a in range(random.randint(1,12)):
        if random.random()<0.6: args.append(("S",random.randrange(nstruct)))
        else: args.append(("T",random.choice([("i64","long"),("f64","double"),("i32","int"),("f32","float")])))
    funcs.append(args)
def val(t, rnd):
    v,c=t
    if v.startswith("f"): return str(rnd.randint(-50,50))+".5"
    if v.startswith("u"): return str(rnd.randint(0,100))
    return str(rnd.randint(-100,100))
rnd=random.Random(seed*7+1)
def lit(i):
    fields,nest=structs[i]
    parts=[f".f{k} = {val(t,rnd)}" for k,t in enumerate(fields)]
    if nest is not None: parts.append(f".n = {lit(nest)}")
    return f"{sname(i)}{{ {', '.join(parts)} }}"
cs_f=[];vs_f=[];calls=[]
for fi,args in enumerate(funcs):
    cparams=[];body=[];vparams=[];vargs=[]
    for k,(kind,x) in enumerate(args):
        if kind=="S":
            cparams.append(f"{sname(x)} a{k}"); vparams.append(f"{sname(x)} a{k}"); body.append(fexpr_c(x,f"a{k}")+f"*{k+1}")
            vargs.append(lit(x))
        else:
            v,c=x; cparams.append(f"{c} a{k}"); vparams.append(f"{v} a{k}"); body.append(f"(double)a{k}*{k+1}")
            vargs.append(val(x,rnd))
    cs_f.append(f"double fn{fi}({', '.join(cparams)}) {{ return {' + '.join(body)}; }}")
    vs_f.append(f"extern f64 fn{fi}({', '.join(vparams)});")
    calls.append(f"fn{fi}({', '.join(vargs)})")
# makers: struct returned from C, then summed in Vibe via C sum fn
for i in range(nstruct):
    fields,nest=structs[i]
    assigns=" ".join(f"r.f{k} = ({c})(seed * {k+3});" for k,(v,c) in enumerate(fields))
    nestas = f" r.n = mk{nest}(seed + 1);" if nest is not None else ""
    cs_f.append(f"{sname(i)} mk{i}(long seed) {{ {sname(i)} r; {assigns}{nestas} return r; }}")
    cs_f.append(f"double sum{i}({sname(i)} v) {{ return {fexpr_c(i,'v')}; }}")
    vs_f.append(f"extern {sname(i)} mk{i}(i64 seed);")
    vs_f.append(f"extern f64 sum{i}({sname(i)} v);")
    calls.append(f"sum{i}(mk{i}({i+2}))")
open("p.vibe","w").write("\n".join(vs+vs_f)+"\nvoid main() {\n"+"\n".join(f'    println("{{{c}:.6}}");' for c in calls)+"\n}\n")
# C reference main: same calls
def c_lit(i, rnd2=None): pass
open("lib.c","w").write("\n".join(cs+cs_f)+"\n")
# C reference: translate vibe struct literals to C compound literals
import re
def to_c(expr):
    e=re.sub(r'(S\d+)\{', r'(\1){', expr)
    return e
open("ref.c","w").write('#include <stdio.h>\n'+"\n".join(cs)+"\n"+"\n".join(f"double fn{fi}({', '.join(('%s a%d' % ((sname(x) if k=='S' else x[1]), j)) for j,(k,x) in enumerate(args))});" for fi,args in enumerate(funcs))+"\n"+"\n".join(f"{sname(i)} mk{i}(long seed); double sum{i}({sname(i)} v);" for i in range(nstruct))+"\nint main() {\n"+"\n".join(f'    printf("%.6f\\n", (double)({to_c(c)}));' for c in calls)+"\n}\n")
