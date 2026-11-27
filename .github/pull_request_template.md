## What and why

<!-- A sentence or two: the bug, the issue number, the change. -->

## Checks

- [ ] `./bootstrap.sh` ends with both fixed points and `N passed, 0 failed`
- [ ] `FLAGS=-O tests/run.sh` passes
- [ ] a fix has a test that fails before it (and the golden `.err`/`.tok` files are updated)
- [ ] `SPEC.md` and the guide are updated if a rule changed
- [ ] the seed is refreshed (`tools/update-seed.sh`) if the compiler changed

## Review notes

<!-- Anything the maintainer should look at closely, or why a rule changed. -->
