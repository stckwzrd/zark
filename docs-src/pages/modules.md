---
title: Modules and imports
order: 19
section: Language
description: How to split a program into files: import, import as, namespaces, paths, cycles and the visibility rules in Zark
---

A program can consist of several files. One file brings in another through `import`. This page describes what exactly is brought in, how names are assigned and which rules the compiler checks.

## A plain import

Suppose two files lie side by side. The first is `shapes.zk`:

```zark file=shapes.zk
struct Rect { i64 w; i64 h; }

i64 area(Rect r) {
    return r.w * r.h;
}

const auto SIDES = 4;
```

The second is the main file. The import is written at the top:

```zark run
import "shapes.zk";

void main() {
    const auto r = Rect{ .w = 3, .h = 4 };
    println(area(r), SIDES);
}
```

A plain `import "file.zk";` puts **all** the names of the file (functions, structs, unions, enums, constants, global variables, type aliases) into the common namespace. They are used without a prefix.

Properties of an import:

- The path is a string, **relative to the file that contains the `import`**, not to the place where you run the compiler.
- Each file is loaded **once**, however many times and from wherever it is imported.
- Imports can be put anywhere at the top level, but by convention they are written at the start.
- Subdirectories are allowed: `import "lib/util.zk";`.
- Cyclic imports are allowed: a file is loaded once, so the cycle simply stops.

## `import ... as name;`

If the names from a file might collide with yours, import it with an alias. Then all its names get the prefix `name::`:

```zark file=geometry.zk
struct Point {
    i64 x;
    i64 y;
    i64 sum() { return this->x + this->y; }
}

enum Axis { X, Y }

union Hit { i64 Yes; No; }

const auto ORIGIN_X = 0;

type Coord = i64;

i64 dist2(Point p) {
    return p.x * p.x + p.y * p.y;
}
```

```zark run
import "geometry.zk" as geo;

void main() {
    const auto p = geo::Point{ .x = 3, .y = 4 };
    println(geo::dist2(p), p.sum(), geo::ORIGIN_X);
    const geo::Axis a = .Y;
    const auto b = geo::Axis.X;
    println(a, b);
    const geo::Hit h = .Yes(5);
    println(h);
    const geo::Coord c = 7;
    println(c);
}
```

The alias is put before any member of the file: a function, a type, a constant, a global variable. The printed form of types also shows the prefix (`geo::Point{ ... }` in an error message or when printing a struct).

Inside the file itself its names work **without a prefix**: the renaming is seen only by those who import it.

Methods and variant literals (`.Y`, `.Yes(5)`) do not need a prefix: they are inferred from the type.

## One file, several names

A file is loaded once, however many times and under whatever names it is imported. Two names for the same file both work:

```zark file=util.zk
i64 tool() { return 1; }
```

```zark run
import "util.zk" as a;
import "util.zk" as b;

void main() { println(a::tool() + b::tool()); }
```

This is what lets a library import `std/thread` as `thread` while your program imports it as `t`. Two rules remain: a name belongs to one file, and a file imported with a name somewhere cannot also be imported plainly (without `as`).

## A plain import "leaks"

If the file `util.zk` itself does a **plain** `import "base.zk"`, the names from `base.zk` end up in the common namespace and become visible everywhere, including the main file:

```zark file=lib/base.zk
i64 base_val() { return 41; }
```

```zark file=lib/util.zk
import "base.zk";

i64 helper() { return base_val() + 1; }
```

```zark run
import "lib/util.zk" as u;

void main() {
    println(u::helper());
    println(base_val());
}
```

The names from `util.zk` got the prefix `u::`, but `base_val` from the nested plain import did not. If you want an isolated module, import everything through `as`, and then the prefix is explicit everywhere.

## Paths

The path in `import` is read from the directory of the **current file**. So `lib/util.zk`, bringing in `"base.zk"`, looks for it next to itself, in `lib/`, not next to the main file.

A missing file is a compile-time error:

```zark error
import "missing.zk" as m;

void main() {}
```

## `extern` and `export` in a module

An `extern` declared in a module imported `as name` gets the prefix like everything else (`name::puts`), while the C symbol it links to stays the same. So a module can declare `extern i32 close(i32 fd);` and your program can still have its own `close`. An `export` is called from C by its exact name, so it stays global. More on the page [interoperating with C](c-interop.md).

## Name conflicts

If two plain imports define the same name, the compiler stops with a duplicate message:

```zark file=one.zk
i64 helper() { return 1; }
```

```zark file=two.zk
i64 helper() { return 2; }
```

```zark error
import "one.zk";
import "two.zk";

void main() {
    println(helper());
}
```

The solution: import both with `as`, or rename the functions.

Your own names and the names of the standard library must not coincide either: you cannot declare your own `max` or `sort` (see the [reference](stdlib.md)).

## How splitting into files is organized

There are no "packages" and no manifest file. A module is simply a file. For a small program this layout is enough:

```text
project/
├── main.zk        the main file, contains main()
├── model.zk       structs and their methods
├── parse.zk       parsing the input
└── util.zk        small helpers
```

The main file brings in the others:

```text
import "model.zk" as model;
import "parse.zk" as parse;
import "util.zk";
```

Run it with `zark run main.zk`. The other files are pulled in by themselves.

## Only what is reachable is compiled

From the imported files the compiler takes only the functions that can be reached from `main`. An extra import does not bloat the binary, and an unused function is not type-checked (unless it is a generic, whose errors show up on first use).

```zark file=maybe.zk
i64 used() { return 1; }

i64 never_called() {
    return "this is not a number";
}
```

```zark run
import "maybe.zk";

void main() {
    println(used());
}
```

> **Note:** the error in `never_called` is not detected until the function is called. If you want the whole code checked, call the functions from tests (see [testing](testing.md)).

## What next

- How to bring in C files: [interoperating with C](c-interop.md).
- How to check code in parts: [testing](testing.md).
