# C ABI fuzzer (layer 3 baseline)

Generates C and Zark sides of the same signatures independently, builds them
with the selected Zark backends, runs them and compares the checksums. It does
not use `cbind` to generate the Zark side, so a `cbind` bug cannot mask an ABI
bug.

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
The C side reads the tag and the active member, the Zark side matches on
the variant, and the generator computes the expected tag plus payload sum.
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
the C offsets of `tag` and `u`; the Zark side has no field to take the
address of, so only its size and alignment are compared.

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

- Bitfields, packed and over-aligned structs.
- AArch64. The classifier and the CI matrix are step 4.
- Random signatures for `indirect`/`export`/`callback`; random mode still
  generates direct calls only.
