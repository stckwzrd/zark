---
title: Modules and imports
order: 19
section: Language
description: How to split a program into files: import, import as, namespaces, paths, cycles and the visibility rules in Vibe
---

A program can consist of several files. One file brings in another through `import`. This page describes what exactly is brought in, how names are assigned and which rules the compiler checks.

## A plain import

Suppose two files lie side by side. The first is `shapes.vibe`:

```vibe file=shapes.vibe
struct Rect { i64 w; i64 h; }

i64 area(Rect r) {
    return r.w * r.h;
}

const auto SIDES = 4;
```

The second is the main file. The import is written at the top:

```vibe run
import "shapes.vibe";

void main() {
    const auto r = Rect{ .w = 3, .h = 4 };
    println(area(r), SIDES);
}
```

A plain `import "file.vibe";` puts **all** the names of the file (functions, structs, unions, enums, constants, global variables, type aliases) into the common namespace. They are used without a prefix.

Properties of an import:

- The path is a string, **relative to the file that contains the `import`**, not to the place where you run the compiler.
- Each file is loaded **once**, however many times and from wherever it is imported.
- Imports can be put anywhere at the top level, but by convention they are written at the start.
- Subdirectories are allowed: `import "lib/util.vibe";`.
- Cyclic imports are allowed: a file is loaded once, so the cycle simply stops.

## `import ... as name;`

If the names from a file might collide with yours, import it with an alias. Then all its names get the prefix `name::`:

```vibe file=geometry.vibe
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

```vibe run
import "geometry.vibe" as geo;

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

## One file, one name

The rules the compiler checks:

1. A file is attached to the program under **one** name. You cannot attach `util.vibe` as `a` in one place and as `b` in another.
2. A name belongs to one file.

```vibe file=util.vibe
i64 tool() { return 1; }
```

```vibe error
import "util.vibe" as a;
import "util.vibe" as b;

void main() {}
```

## A plain import "leaks"

If the file `util.vibe` itself does a **plain** `import "base.vibe"`, the names from `base.vibe` end up in the common namespace and become visible everywhere, including the main file:

```vibe file=lib/base.vibe
i64 base_val() { return 41; }
```

```vibe file=lib/util.vibe
import "base.vibe";

i64 helper() { return base_val() + 1; }
```

```vibe run
import "lib/util.vibe" as u;

void main() {
    println(u::helper());
    println(base_val());
}
```

The names from `util.vibe` got the prefix `u::`, but `base_val` from the nested plain import did not. If you want an isolated module, import everything through `as`, and then the prefix is explicit everywhere.

## Paths

The path in `import` is read from the directory of the **current file**. So `lib/util.vibe`, bringing in `"base.vibe"`, looks for it next to itself, in `lib/`, not next to the main file.

A missing file is a compile-time error:

```vibe error
import "missing.vibe" as m;

void main() {}
```

## `extern` and `export` get no prefix

The names of `extern` and `export` are C symbols, and they cannot have a prefix. They are always global, even with `import ... as`. More on the page [interoperating with C](c-interop.md).

## Name conflicts

If two plain imports define the same name, the compiler stops with a duplicate message:

```vibe file=one.vibe
i64 helper() { return 1; }
```

```vibe file=two.vibe
i64 helper() { return 2; }
```

```vibe error
import "one.vibe";
import "two.vibe";

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
├── main.vibe        the main file, contains main()
├── model.vibe       structs and their methods
├── parse.vibe       parsing the input
└── util.vibe        small helpers
```

The main file brings in the others:

```text
import "model.vibe" as model;
import "parse.vibe" as parse;
import "util.vibe";
```

Run it with `vibe run main.vibe`. The other files are pulled in by themselves.

## Only what is reachable is compiled

From the imported files the compiler takes only the functions that can be reached from `main`. An extra import does not bloat the binary, and an unused function is not type-checked (unless it is a generic, whose errors show up on first use).

```vibe file=maybe.vibe
i64 used() { return 1; }

i64 never_called() {
    return "this is not a number";
}
```

```vibe run
import "maybe.vibe";

void main() {
    println(used());
}
```

> **Note:** the error in `never_called` is not detected until the function is called. If you want the whole code checked, call the functions from tests (see [testing](testing.md)).

## What next

- How to bring in C files: [interoperating with C](c-interop.md).
- How to check code in parts: [testing](testing.md).
