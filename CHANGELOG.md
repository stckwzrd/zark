# Changelog

All notable changes to Zark. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the version follows [SemVer](https://semver.org/): the compiler, the language
and the standard library share one version, and a `-pre` suffix means the checks
and the standard library may still change before the release.

## [0.6.0-pre] - 2026-11-27

A soundness release: the ownership checker no longer accepts two ways to end up
with two owners of the same resource, and an error inside a generic says which
generic it came from.

### Fixed
- `l[i]` and `List.get(i)` with a runtime index on a resource element were a
  bitwise copy while the container still owned the value (#78). They are
  rejected now. A constant index rooted in a local is still tracked; `at(i)`
  borrows, `pop`/`remove_at`/`swap_remove` move an element out, and
  `move_out(&x)` is the explicit escape for code outside the container.
- `for (auto x : list_of_lists)` copied each resource element (#58). The loop
  variable is now a non-owning copy: it can be read and borrowed, but not moved
  out and not mutated through an `invalidates` method (the copy's header would
  change while the container still points at the old buffer).
- `match (u)` on a resource union, `x orelse d` and `x catch d` on a resource
  optional or error union, and a closure that captures a `for` loop variable
  all copied the payload out while the container still owned it (the same class
  as #58). `match` and the unwrap now consume the operand, and a closure cannot
  capture the non-owning loop copy.
- Copying or moving a resource out of a place reached through a pointer or a
  slice (`this->l`, `hp->l`, `s[0]`, `(*p).l`) was a bitwise alias the checker
  wrongly treated as a move. It is rejected now, like `*p`; a field or constant
  index of a local value (`h.l`, `l.items[0]`) still moves. `Map.get` and
  `Map.get_or` are rejected for a resource value (as `List.get` is); borrow with
  `get_ptr(key)`.
- An error inside a generic or prelude function now prints a note naming it
  (`List.get`), because the source location alone points at `<std>`.

### Changed
- `List.pop`, `remove_at`, `swap_remove`, `take` and `clear` are declared
  `invalidates`, which is what they always did.
- The native backend emits one `jno` for a checked signed `+`/`-` (64-bit
  only; narrower types keep the sign trick) and drops unreachable blocks.
  Range facts remove checks that provably cannot fire.
- `zark version` and `zark --version` print the version.

### Reproducible
- The seed reproduces stage 2 byte for byte; stage2 == stage3 and
  native2 == native3 after `./bootstrap.sh`.

## [0.5.0]
- Own x86-64 backend and ELF writer (the default); the native-built compiler
  reaches its own fixed point.

## [0.4.0]
- Self-hosted compiler (stage2 == stage3); `is`, `eprint`, `embed`.

## [0.3.0]
- Files, processes, `sprint`, format specs, `type` aliases, `Arena`,
  self-hosted lexer.

## [0.2.0]
- No hidden allocations, `Allocator`, `*void`, function pointers, tagged
  unions, `..` in literals, `alignof`, `errdefer` on runtime errors.
