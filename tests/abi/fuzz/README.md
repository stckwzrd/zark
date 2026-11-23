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

| direction | case prefix | status on 75f7eb4 |
|---|---|---|
| Zark calls C directly | `direct_*`, `rnd_*` | green |
| Zark calls C through `fn` pointer | `indirect_*` | red for aggregates |
| C calls Zark `export` | `export_*`, `export_struct` | red |
| C calls a Zark callback | `callback_*` | red |

`export_struct` is the 12-line negative control: Zark exports
`P addp(P, P)` with `struct P { i32 x; i32 y; }`, C calls it with the SysV
layout and expects `4 6`. Native crashes; `--llvm` returns garbage; `-O`
returns garbage.

The failure is shape-specific, not direction-wide: `export_mixed`
(`struct { i64; f64; }`) passes on `--llvm` and `-O` and crashes only on
native, while `P` (`i32, i32`) fails everywhere. `indirect_16` (`f64, f64`)
passes on `--llvm`/`-O` and fails on native. The matrix is the source of
truth, not the direction.

`direct_char` sends `i8 -1`, `u8 200`, `bool true`. It was the first real bug
found by the harness: `-O` returned 456, because the `i8` argument was not
sign-extended before the C call. The compiler now emits `signext`/`zeroext`
on small C parameters and returns; the same case plus `direct_i8_ret`,
`direct_u8_ret`, `direct_i16_ret`, `direct_u16_ret` and `direct_bool_ret`
cover the other direction and stay as regressions.

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

- `sizeof`/`alignof`/`offsetof` comparison between C and Zark.
- Struct returns from generated cases (only the hand-written
  `tests/abi/export_struct`).
- Unions, bitfields, packed and over-aligned structs.
- Variadic functions.
- AArch64. The classifier and the CI matrix are step 4.
- Full random signatures for `indirect`/`export`/`callback`; those are
  known-broken until the thunk work lands.
