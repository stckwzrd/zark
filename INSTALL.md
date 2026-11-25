# Installing Zark

Zark builds from source with one command. The repository contains a bootstrap seed (the compiler's own LLVM IR), so the only compiler you need is clang.

```
git clone https://github.com/stckwzrd/zark.git
cd zark
sh scripts/install-deps.sh
./bootstrap.sh
./install.sh
```

- `scripts/install-deps.sh` installs the build tools with the package manager it finds (apt, dnf, pacman, apk, zypper, xbps). On macOS it asks for the Xcode command line tools if clang is missing.
- `./bootstrap.sh` builds the compiler in stages, checks that it reproduces itself, runs the test suite and leaves the result in `build/zark`. It takes a few minutes.
- `./install.sh` copies `build/zark` to `~/.local/bin` (set `PREFIX=/usr/local` to change that). Zark is a single binary, the standard library is embedded.

Check it:

```
zark run examples/hello.zk
```

`bootstrap.sh` already ran the test suite. To run it again (and the LLVM and `-O` passes):

```
ZARK=build/zark tests/run.sh
ZARK=build/zark tests/run.sh --llvm
ZARK=build/zark tests/run.sh -O
```

The suite needs `python3` for the fuzzers and generators; `scripts/install-deps.sh` installs it.

## What you need

| Tool | Why |
|---|---|
| clang 18 or newer | builds the seed, links programs, runs `--release` |
| a C library with headers | glibc, musl or the macOS SDK |
| binutils (`ld`) | linking on Linux |
| bash, gzip, diffutils, make | the bootstrap script |
| python3 | the test suite that `bootstrap.sh` runs (fuzzers and generators) |

## Supported systems

| System | Status | Backend |
|---|---|---|
| Linux x86-64, glibc (Debian, Ubuntu, Fedora, Arch, openSUSE) | built and tested | own x86-64 backend by default, LLVM with `--llvm` / `-O` |
| Linux x86-64, musl (Alpine) | built and tested | same |
| Linux arm64 | supported | LLVM only |
| macOS, Apple Silicon and Intel | supported | LLVM only |
| Windows | through WSL2 | same as Linux |

Windows without WSL is not supported: the runtime uses `fork`, `poll` and POSIX threads.

The own native backend writes x86-64 ELF files, so it exists only on x86-64 Linux. On every other system Zark uses clang to compile the LLVM IR, which is fully supported. `zark build --native` on those systems prints an error.

On arm64 (Linux and macOS) passing structs by value to C functions is not supported yet: the compiler lowers extern calls with the x86-64 System V rules. Pass pointers instead. `tests/abi` runs only on x86-64.

The x86-only parts of the language (`examples/baremetal`, the port I/O and privileged instruction helpers, the `Atomic` functions in the prelude) only make sense on x86-64.

## Linux

### Debian, Ubuntu and derivatives

```
sudo apt-get update
sudo apt-get install -y clang binutils diffutils gzip make bash git python3
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

### Fedora, RHEL, Rocky, Alma

```
sudo dnf install -y clang binutils diffutils gzip make bash git python3 glibc-devel
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

### Arch, Manjaro

```
sudo pacman -Syu --needed clang binutils diffutils gzip make bash git python glibc linux-api-headers
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

### openSUSE

```
sudo zypper install -y clang binutils diffutils gzip make bash git python3 glibc-devel
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

### Alpine (musl)

```
sudo apk add clang gcc binutils musl-dev diffutils gzip make bash git python3
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

`gcc` is needed on Alpine only for `libgcc` and the C runtime start files that clang links against.

### Void

```
sudo xbps-install -Sy clang binutils diffutils gzip make bash git python3
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

### Other distributions

Install clang 18 or newer, the C library headers, binutils, bash, gzip, diffutils and make with your package manager, then run `./bootstrap.sh`.

### Linux on arm64 (Raspberry Pi, servers, Asahi)

The same commands as for your distribution. The bootstrap skips the native backend steps and builds everything through LLVM.

## macOS

```
xcode-select --install
git clone https://github.com/stckwzrd/zark.git && cd zark
./bootstrap.sh && ./install.sh
```

The Xcode command line tools provide clang, `ld`, `make` and python3. If you use Homebrew LLVM instead, put it first in `PATH`. This works on Apple Silicon and on Intel Macs. Add `~/.local/bin` to `PATH` in your shell profile if `install.sh` tells you to.

## Windows

Install WSL2 and a Linux distribution, then follow the Linux steps inside it.

```
wsl --install -d Ubuntu-24.04
```

Open the Ubuntu shell and run the Debian/Ubuntu commands above. Clone the repository inside the WSL file system (for example in `~`), not under `/mnt/c`: it is much faster and keeps the line endings right.

## Docker

```
docker run --rm -it -v "$PWD":/src -w /src debian:stable sh -c "sh scripts/install-deps.sh && ./bootstrap.sh && bash"
```

## Troubleshooting

- `cmp: command not found`: install diffutils.
- `cannot find crtbeginS.o` or `-lgcc` on Alpine: install `gcc`.
- `ld: not found`: install binutils.
- `error: the native backend only supports x86-64 Linux`: you passed `--native` on another system, drop the flag.
- Programs print `fatal: ...` and a backtrace when they crash. Set `ZARK_CRASH_HANDLER=0` to get a plain core dump instead.
- Do not share one `.zark-cache` between different systems (for example a Docker bind mount used from Linux and macOS): delete it when you switch.
- The compiler caches objects in `.zark-cache` next to where you run it; delete the directory to start clean.
- Docker on Fedora with SELinux: a bind-mounted workspace is labelled `user_home_t`, and the container's `container_t` cannot read it (`permission denied` for `bootstrap.sh`). Mount it with `:z` (`-v "$PWD":/src:z`) or run the container with `--security-opt label=disable`.
- A hang in `tests/cbuild.sh` on a machine where `clang` is a ccache wrapper is fixed by `tests/compiler.sh`; if you see it again, check that the wrapper is not being exec'd by a shim you added.
- `pthread_create: Resource temporarily unavailable` in the threaded tests: raise `ulimit -u` (the suite starts several processes and threads).
