---
title: Showcase: a multithreaded ray tracer
order: 2.5
section: Start
description: One larger program that uses interfaces, SIMD, threads, JSON, unions, generics, operators, closures, error handling and tests together
---

This page walks through `examples/showcase/`, a small ray tracer written in Vibe. It reads a scene from JSON, renders it on several threads and prints the picture as ASCII art. The same program is used as a test of the compiler: its output is checked on every backend.

```sh
vibe run examples/showcase/main.vibe
vibe run examples/showcase/main.vibe -- --ppm scene.ppm
vibe test examples/showcase/main.vibe
```

The program is built through LLVM automatically, because it uses SIMD vectors.

## Where each feature lives

| File | What it shows |
|---|---|
| `vec.vibe` | a `Vec3` struct on top of a SIMD `f32x4`, operator overloading (`+ - *` and unary `-`), a constructor, `const` methods, a generic `clamp<T: Ord>`, and `test` blocks |
| `scene.vibe` | an `interface Shape` implemented by two structs without any declaration, a tagged `union Material` with a payload, `?Hit` optionals, and loading a scene with the `std/json` module and `!T` errors |
| `render.vibe` | a generic `Grid<T>`, `match` on the union, recursion for reflections, worker threads with an atomic row counter and a `WaitGroup`, a closure that captures its context explicitly, and the wrapping operator `*%` in a checksum |
| `main.vibe` | an `Arena` with `defer`, `embed` of the scene file, a `Writer` over `print`, error handling with `catch`, command-line arguments, and tests of the whole pipeline |

## A vector on SIMD

```vibe
struct Vec3 {
    f32x4 v;

    Vec3(f32 x, f32 y, f32 z) { v = f32x4(x, y, z, 0.0); }

    Vec3 operator+(Vec3 o) const { Vec3 r; r.v = v + o.v; return r; }
    Vec3 operator*(f32 k) const { Vec3 r; r.v = v * k; return r; }

    f32 dot(Vec3 o) const {
        const auto m = v * o.v;
        return m[0] + m[1] + m[2];
    }
}
```

`v + o.v` is one vector instruction. A literal on the right of an operator takes the type of the operator's parameter, so `a * 2.0` works with an `f32`.

## Shapes without inheritance

```vibe
interface Shape {
    ?Hit intersect(Ray r);
}

struct Sphere {
    Vec3 center;
    f32 radius;
    Material mat;

    ?Hit intersect(Ray r) { ... }
}
```

`Sphere` and `Plane` have an `intersect` method with the same signature, so a pointer to either converts to `Shape`. A `List<Shape>` holds both, and a call is one indirect call through a method table. Nothing is allocated for the dispatch.

## A union with data

```vibe
union Material {
    Vec3 Diffuse;
    Vec3 Mirror;
    Vec3 Emissive;
}

match hit.mat {
    .Emissive(c) => return c;
    .Mirror(c) => { ... return shade(sc, bounce, depth + 1).mul(c); }
    .Diffuse(c) => { ... return c * (0.12 + 0.88 * lit); }
}
```

## Errors as values

Reading the scene returns `!Scene`. A missing field, a wrong vector length, an unknown shape and invalid JSON each become an error that the caller can print or test:

```vibe
!Material read_material(json::Value* m) {
    const auto kind = m.get("kind").as_str()?;
    const auto color = read_vec(m.get("color"))?;
    if (kind == "diffuse") { return Material::Diffuse(color); }
    if (kind == "mirror") { return Material::Mirror(color); }
    if (kind == "emissive") { return Material::Emissive(color); }
    return error.UnknownMaterial;
}
```

## Threads without hidden allocation

```vibe
!void render(Scene* sc, Grid<Vec3>* img, i64 workers) {
    auto next_row = thread::AtomicI64{};
    auto wg = thread::WaitGroup{};
    thread::Thread[8] pool;
    wg.add(workers);
    for (auto i : 0..workers) {
        pool[i] = thread::spawn([&sc, &img, &next_row, &wg]() -> void {
            while (true) {
                const auto y = next_row.add(1);
                if (y >= img.h) { break; }
                for (auto x : 0..img.w) { img.set(x, y, trace(sc, x, y)); }
            }
            wg.done();
        })?;
    }
    wg.wait();
    for (auto i : 0..workers) { pool[i].join(); }
}
```

Each worker takes the next free row from an atomic counter, so the rows are shared fairly, and the picture does not depend on the number of threads. A test renders with 1 and with 6 workers and compares the checksums.

## The output

```text
scene: 96x40, 4 shapes
rejected: error.BadVector
rejected: error.UnknownShape
rejected: error.InvalidJson
................................................................................................
................................................................................................
................................................................................................
................................................................................................
................................................................................................
................................................................................................
................................................................................................
................................................................................................
................................................................................................
................................................................................................
................................................................................................
................................................................................................
..........................................................................%%%%%%................
.....................................................................%%%%%%%%%%%%%%%%%..........
..........................................----------::............%%%%%%%%%%%%%%%%%%%%%%........
.......................................---====-------:::........%%%%%%%%%%%%%%%%%%%%%%%%%%......
:::::::::::::::::::...................---====---------:::......%%%%%%%%%%%%%%%%%%%%%%%%%%%%:::::
:::::::::::::::::::::::::::::::::::::----------------::::..::::%%%%%%%%%%%%%%%%%%%%%%%%%%%%%::::
.......................        .....:---------------:::::.. ...%%%%%%%%%%%%%%%%%%%%%%%%%%%%%....
::::::::::::::::::::...       ...::::-------------::::::... :::%%%%%%%%%%%%%%%%%%%%%%%%%%%%%::::
::::---------------.........:   ..--::::------:::::::::...  ---%%%%%%%%%%%%%%%%%%%%%%%%%%%%%::::
-------------------==++*****+    ===.:::::::::::::::.....   ----%%%%%%%%%%%%%%%%%%%%%%%%%%%-----
====================+++++++++++==    ..::::::::::......       ====%%%%%%%%%%%%%%%%%%%%%%%-------
==========+++++++++++=++++++++      ++...............            ===%%%%%%%%%%%%%%%%%%%     ====
++++++++++++++++++++++++    ++++++++++++  ......                 ++    %%%%%%%%%%%%%            
++++++++++++++++++++++++++++++++++++++++                      +++++++                           
++++************************************++++            +++++++++++++++++                     ==
****************************************************++++++++++++++++++++++++++++++++++++++++++++
*************************************************************+++++++++++++++++++++++++++++++++++
********************************************************************++++++++++++++++++++++++++++
***************************************************************************+++++++++++++++++++++
********************************************************************************++++++++++++++++
**************************************************************************************++++++++++
*******************************************************************************************+++++
################********************************************************************************
#######################*************************************************************************
############################********************************************************************
################################****************************************************************
###################################*************************************************************
######################################**********************************************************
checksum 51dbcc6aeca2d7a1
```

## Exercises

- Add a `Triangle` shape: it only needs an `intersect` method.
- Add a `"glass"` material to the `union` and see which `match` the compiler asks you to extend.
- Build with `--check-overflow` and see that the checksum, which uses `*%`, keeps wrapping on purpose.
