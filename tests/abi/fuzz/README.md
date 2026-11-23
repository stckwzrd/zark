# C ABI fuzzer (layer 3 baseline)

Generates C and Zark sides of the same signatures independently, builds them
with the selected Zark backends, runs them and compares the checksums. It does
not use `cbind` to generate the Zark side, so a `cbind` bug cannot mask an ABI
bug. The checksum weights every scalar leaf by its position in the argument
list (a variable argument by its index in the format string), so swapped
arguments, members or registers of the same type change it.

## Run

```sh
cd ~/Projects/Zark
python3 tests/abi/fuzz/fuzz.py --backends native,llvm,O
python3 tests/abi/fuzz/fuzz.py --cases 50 --seed 1 --backends native
python3 tests/abi/fuzz/fuzz.py --only export_struct --backends native,llvm,O
```

Requires a built `build/zark` (or `ZARK=/path/to/zark`), clang and Python 3.
Generated sources and binaries go to `build/abi_fuzz/` (git-ignored).

## What is covered

| direction | case prefix | status |
|---|---|---|
| Zark calls C directly | `direct_*`, `rnd_*` | green |
| Zark calls C through `fn` pointer | `indirect_*` | green |
| C calls Zark `export` | `export_*`, `export_struct` | green |
| C calls a Zark callback | `callback_*` | green |
| Zark calls a variadic C function | `variadic_*` | green |

All three backends (`native`, `--llvm`, `-O`) are green, so `KNOWN_BROKEN` is
empty and `tests/run.sh` runs the quick set with `--strict`.

`export_struct` is the 12-line negative control: Zark exports
`P addp(P, P)` with `struct P { i32 x; i32 y; }`, C calls it with the SysV
layout and expects `4 6`. It was red on every backend and is now green
everywhere. `export_big` exports a 24-byte struct through `sret`.

The current fixed set covers `{f32, f32}`, `{f32, f32, f32}`, `{u8, u8, u8}`,
`{i32, i32, i32}`, `i32[3]`, `{bool, i8}`, an empty struct, 16-byte mixed
values in both directions, small integers in both directions, and callbacks
with more than six integer arguments plus an aggregate that spills to the
stack. The failures were shape-specific, not direction-wide; the matrix is
the source of truth.

Unions go by value in all four directions as parameters and results
(`*_ud`, `*_udi`, `*_ufd`, `*_uff`, `*_uif`, `*_udd`, `*_uf2`, `*_up`,
`*_ubig`, the struct wrappers `*_su`, `*_sua`, `*_sux` and `*_union_mix`).
`*_un`, `*_uni`, `*_unf` and `*_unb` mix in variants without a payload
(the C side sets only the tag), and `*_<union>_ret<i>` returns variant `i`
of every union, so each tag value crosses the boundary in every direction.
The C side reads the tag and the active member, the Zark side matches on
the variant, and the generator computes the expected sum of the tag plus one
(so tag 0 still counts) and the payload, weighted by position.
The cases whose payload eightbyte is SSE (`ud`, `ufd`, `uff`, `udd`, `uf2`,
`su`, `sua`, `union_mix`) were red on every backend while unions were
classified as INTEGER.

`direct_char` sends `i8 -1`, `u8 200`, `bool true`. It was the first real bug
found by the harness: `-O` returned 456, because the `i8` argument was not
sign-extended before the C call. The compiler now emits `signext`/`zeroext`
on small C parameters and returns; the same case plus `direct_i8_ret`,
`direct_u8_ret`, `direct_i16_ret`, `direct_u16_ret` and `direct_bool_ret`
cover the other direction and stay as regressions.

The `variadic_*` cases call `long vsum(int n, ...)` with integers and with
doubles past the register limits, and a `vformat`-style C function that walks
a format string with `va_arg`: mixed integers and doubles on the stack, a
fixed struct before `...` (`P`, `F2`, `D2`, `M`, `Big`, `UD`, also after the
integer registers ran out), small integers in the fixed part, aggregate
results (`P`, `F2`, `D2`, `M` in registers, `Big` through `sret`), promoted
`i8`/`u8`/`i16`/`u16`/`bool`/`f32`/`i32`/`u32`, and structs and unions in the
variable part, including one that no longer fits in the registers. They were
red while the fixed part of a variadic call used the internal ABI.

The arm64 cases (`*_f1`, `*_f4`, `*_d1`, `*_d3`, `*_d4`, `*_nh`, `*_nd`, `*_ha`,
`*_hda`, `*_he`, `*_hz`, `*_f5`, `*_fd`, `*_al16`, `*_al16f`, `*_b17`, `*_b32`,
`*_s5`, `*_s6`, `*_s7`, `*_spill_hfa`, `*_spill_fp`, `*_spill_int`,
`*_al16_odd`, `*_hfa_mix` and the `variadic_*hfa*`, `variadic_*al16`,
`variadic_var_arm`, `variadic_ret_d4`, `variadic_ret_s6` cases) cover HFAs of
1 to 4 floats or doubles, nested and with array members, an empty member and a
zero-length array, non-HFA mixed and 16-aligned structs, 17 to 32 byte structs,
3 to 7 byte structs and spills past 8 general and 8 vector registers. They run
everywhere; on arm64 hosts `tests/run.sh` runs the whole fuzzer with
`--backends llvm,O` (the native backend exists only on Linux x86-64 and is
skipped elsewhere).

The vector cases (`*_f32x4`, `*_f64x2`, `*_i32x4`, `*_u8x16`, `*_i64x2`,
`*_vec_spill_f32x4`, `variadic_fix_f32x4`) pass 16-byte SIMD vectors as
`vector_size(16)` C vectors, also when the vector registers run out before a
struct of two doubles. The 8-byte ones (`*_f32x2`, `*_i16x4`, `*_u8x8`,
`*_vec_spill_f32x2`, `variadic_fix_f32x2`) exist only on arm64, where the
compiler accepts them; the IR oracle always includes them.

## IR oracle

`--ir-oracle aarch64,arm64-apple` builds every fixed (and `--cases` random)
signature into one Zark and one C file, runs `zark ir --arch aarch64` and
`clang --target=aarch64-linux-gnu` / `arm64-apple-macosx -O0` and compares
the `extern` declaration, the direct call, the indirect call, the `export`
thunk and the function pointer target: parameter and result types (results
flattened to their leaf types) and the `sret`, `byval`, `signext`, `zeroext`,
`inreg` and `alignstack` attributes. `tests/run.sh` runs it on Linux x86-64.

## Layout check

The `layout` case builds one program per backend in which C prints
`sizeof`, `_Alignof` and `offsetof` of every type in `ORDER` and Zark prints
`sizeof(T)`, `alignof(T)` and each field offset (`(&s.f as u64) - (&s as u64)`).
Both are compared with the values the generator computes itself from the C
layout rules (`layout`, `offsets`); any difference is a `FAIL` that names the
side, the type and the field. It covers scalars of every size, nested
structs, arrays in structs, mixed int/float structs, the empty struct and
unions.

A Zark `union` is tagged, so its C mirror is
`struct { int32_t tag; _Alignas(8) union { ... } u; }`. The generator checks
the C offsets of `tag` and `u`. The Zark side has no field to take the
address of, so it builds the last variant that has a payload with a marker
value in its first scalar leaf, reports the offset where it finds the marker
as `u`, and reports `tag` as 0 when the `i32` at offset 0 holds the variant
index.

## Matrix

- `PASS` — expected checksum.
- `FIXED` — a case listed as known-broken now passes.
- `KNOWN-BROKEN` — expected failure for this case/backend; see `KNOWN_BROKEN`
  in `fuzz.py`.
- `FAIL`, `CRASH`, `BUILD`, `TIMEOUT` — unexpected; the script exits 1.
- `--strict` also treats `KNOWN-BROKEN` as failure.

When a fix lands, remove the corresponding `(case, backend)` pair from
`KNOWN_BROKEN`; the row must stay `PASS`, never regress to `KNOWN-BROKEN`.

## Not yet covered

- Bitfields, packed structs and alignment above 16.
- Random signatures for `indirect`/`export`/`callback`; random mode still
  generates direct calls only.
